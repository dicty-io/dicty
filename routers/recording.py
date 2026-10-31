from fastapi import APIRouter
import asyncio
import cloud_streaming as cloud_streaming_mod
import engine_auth
import local_llm
import os
import snippet_service
import sys
import tempfile
import time
import transcribe_service
import uuid
import wave
from services.paths import AUDIO_PATH, DATA_DIR, INPUT_DIR, SYSTEM_AUDIO_PATH
from pydantic import BaseModel
from fastapi import File, Form, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from transcribe_service import TranscribeService
from services.mode_requests import _resolve_mode_request
from services.status import active_websockets, broadcast_partial_transcription, set_status
from services.stores import app_rules_manager, history_manager, snippets_manager, vocabulary_manager
from services.origins import is_origin_allowed
from services.audio import mix_audio, play_pause_chime, play_resume_chime, play_start_chime, play_stop_chime
from services.state import model_manager, recorder
from telemetry_service import telemetry
from services import pipeline
from services import status

router = APIRouter()


@router.get("/recording/status")
def get_recording_status():
    return {
        "status": status.current_processing_status,
        "is_recording": recorder.is_recording,
        "is_paused": getattr(recorder, "is_paused", False)
    }
class StatusUpdate(BaseModel):
    status: str

@router.post("/recording/status/update")
def update_recording_status(payload: StatusUpdate):
    set_status(payload.status)
    return {"success": True}

@router.post("/recording/start")
async def start_recording(device_id: int = None, language: str = "auto", is_muted: bool = False, mode: str = "dictation", use_vad_streaming: bool = False,
                          cloud_streaming: bool = True, cloud_route: str = "", translate_to_english: bool = False,
                          app_id: str = "", domain: str = "", mode_override: str = "", manual_override_active: bool = False):
    if recorder.is_recording:
        return {"status": "already_recording"}
    
    # Resolve per-app mode before starting
    resolved_mode, mode_reason = app_rules_manager.resolve_mode(
        app_id=app_id,
        domain=domain,
        selected_mode_id=mode,
        recording_override_mode_id=mode_override or None,
        manual_override_active=manual_override_active
    )
    recorder.last_app_id = app_id
    recorder.last_domain = domain
    recorder.last_mode_override = mode_override
    recorder.last_manual_override_active = manual_override_active
    recorder.last_resolved_mode = resolved_mode
    recorder.last_mode_reason = mode_reason

    # Warm the direct cloud STT connection while the user is still speaking
    asyncio.create_task(transcribe_service.prewarm_direct_provider(model_manager.get_active_model(), cloud_route))
    
    # Pre-warm local LLM in parallel while the user speaks if local formatting is active
    try:
        settings = model_manager.get_settings()
        if settings.get("llm_provider") == "local" and local_llm.is_installed():
            local_llm.start_server_async()
    except Exception as e:
        print(f"[!] Local LLM pre-warm on record skipped: {e}")
    
    # 0. Strict readiness check: forbid recording if active model is not ready
    from model_manager import ModelManager
    mm = ModelManager()
    active_model_id = mm.get_active_model()
    
    if not active_model_id:
        raise HTTPException(
            status_code=400,
            detail="No speech model is active. Please select a model in Models Library."
        )

    if active_model_id in mm.downloading:
        pct = int(mm.download_progress.get(active_model_id, 0))
        raise HTTPException(
            status_code=400,
            detail=f"Active model '{active_model_id}' is currently downloading ({pct}%). Please wait for download to complete before recording."
        )

    if not mm.is_model_downloaded(active_model_id):
        raise HTTPException(
            status_code=400,
            detail=f"Active model '{active_model_id}' is not installed. Please download it in Models Library before recording."
        )

    play_start_chime()
    try:
        from services.stores import vocabulary_manager
        vocab_data = vocabulary_manager.get_all()
        words = [v["word"] for v in vocab_data if "word" in v]
        # Bias recognition toward snippet trigger phrases (never their content)
        words += [t for t in snippet_service.whisper_bias_terms(snippets_manager.get_all()) if t not in words]
        custom_prompt_str = ", ".join(words) if words else ""
    except Exception:
        custom_prompt_str = ""
        
    recorder.start(device_id, language=language, custom_prompt=custom_prompt_str, is_muted=is_muted, mode=mode, use_vad_streaming=use_vad_streaming)
    
    # Cloud models: transcribe while the user is speaking (Deepgram live / pause-segmented batch).
    # Not for meetings (mixed system audio is transcribed as a whole) or translation (batch-only feature).
    streaming = "off"
    if cloud_streaming and recorder.is_recording and mode not in ("meeting", "focused_meeting") and not translate_to_english:
        try:
            vocab_words = []
            for v in vocabulary_manager.get_all():
                t = (v.get("replacement") or v.get("word") or "").strip()
                if t and t not in vocab_words:
                    vocab_words.append(t)
            for t in snippet_service.whisper_bias_terms(snippets_manager.get_all()):
                if t not in vocab_words:
                    vocab_words.append(t)
            session = cloud_streaming_mod.create_session(
                asyncio.get_running_loop(), active_model_id, getattr(recorder, "actual_sample_rate", 16000),
                route_provider=cloud_route, language=language, vocab_words=vocab_words)
            if session is not None:
                recorder.attach_stream_session(session)
                streaming = session.label
                print(f"[*] Cloud streaming active: {session.label}")
        except Exception as stream_err:
            print(f"[!] Cloud streaming unavailable, will use batch: {stream_err}")
    telemetry.track("recording_started", {
        "language": language,
        "device_id": device_id,
        "is_muted": is_muted,
        "app_id": app_id,
        "resolved_mode": resolved_mode,
        "mode_reason": mode_reason
    })
    return {
        "status": "recording_started",
        "streaming": streaming,
        "resolved_mode": resolved_mode,
        "mode_reason": mode_reason
    }

@router.post("/recording/stop")
async def stop_recording(
    file: UploadFile = File(None),
    audio_file_path: str = Form(None),
    mode: str = Form("dictation"),
    dictation_format_style: str = Form("raw"),
    mode_style: str = Form(None),
    mode_id: str = Form(None),
    correction_location: str = Form(None),
    git_provider: str = Form("github"),
    github_token: str = Form(None),
    github_repo: str = Form(None),
    gitlab_host: str = Form("https://gitlab.com"),
    gitlab_token: str = Form(None),
    gitlab_repo: str = Form(None),
    github_commits: str = Form(None),
    github_prs: str = Form(None),
    confluence_url: str = Form(""),
    confluence_space: str = Form(""),
    confluence_user: str = Form(""),
    confluence_token: str = Form(""),
    confluence_page_title: str = Form(""),
    target_type: str = Form(""),
    obsidian_path: str = Form(""),
    linear_api_token: str = Form(""),
    linear_workspace_id: str = Form(""),
    linear_search_all: str = Form("false"),
    llm_provider: str = Form("openrouter"),
    llm_base_url: str = Form("http://localhost:1234/v1"),
    llm_model: str = Form("qwen/qwen-3.5-flash"),
    llm_api_key: str = Form(""),
    openai_api_key: str = Form(""),
    language: str = Form("auto"),
    translate_to_english: str = Form("false"),
    enable_auto_completion: str = Form("false"),
    use_vad_streaming: str = Form("true"),
    enable_diarization: str = Form("false"),
    diarization_model: str = Form(""),
    target_language: str = Form("none"),
    translation_method: str = Form("none"),
    translation_model: str = Form(""),
    incognito_mode: str = Form("false"),
    mute_microphone: str = Form("false"),
    custom_prompt: str = Form(""),
    tags: str = Form(""),
    speaker_separation: str = Form(""),
    speaker_you_label: str = Form("You"),
    meeting_show_timestamps: str = Form("false"),
    enable_self_correction: str = Form("false"),
    self_correction_model: str = Form(""),
    target_app_name: str = Form(""),
    target_app_bundle_id: str = Form(""),
    app_id: str = Form(""),
    domain: str = Form(""),
    mode_override: str = Form(""),
    manual_override_active: str = Form("false"),
    author_name: str = Form("")
):
    translate_bool = translate_to_english.lower() == "true"
    auto_complete_bool = enable_auto_completion.lower() == "true"
    diarize_bool = enable_diarization.lower() == "true"
    incognito_bool = incognito_mode.lower() == "true"
    self_correction_bool = enable_self_correction.lower() == "true"
    self_correction_model = self_correction_model.strip() if self_correction_model else ""
    mode_style, correction_location, self_correction_bool, self_correction_model = _resolve_mode_request(
        mode, mode_id, mode_style, correction_location, self_correction_bool, self_correction_model
    )
    
    if not recorder.is_recording and file is None and not audio_file_path:
        return {"status": "not_recording"}
    
    play_stop_chime()
    t_start = time.perf_counter()
    
    set_status("Packaging audio...")
    t_mic_0 = time.perf_counter()
    success = False
    effective_client_audio = None

    # 0. Zero-copy local client audio (same-machine, bypasses multipart binary upload and disk re-writes)
    if audio_file_path and isinstance(audio_file_path, str) and os.path.exists(audio_file_path):
        real_p = os.path.realpath(audio_file_path)
        allowed_dirs = [
            os.path.realpath(tempfile.gettempdir()),
            os.path.realpath("/private/var/folders"),
            os.path.realpath("/var/folders"),
            os.path.realpath(DATA_DIR),
            os.path.realpath(INPUT_DIR)
        ]
        if any(real_p.startswith(d) for d in allowed_dirs) and real_p.lower().endswith(".wav") and os.path.getsize(real_p) > 256:
            effective_client_audio = real_p
            success = True
            if recorder.is_recording:
                if mode in ("meeting", "focused_meeting"):
                    await asyncio.to_thread(recorder.stop, AUDIO_PATH + ".discard", loopback_output_path=SYSTEM_AUDIO_PATH, use_vad_streaming=(use_vad_streaming.lower() == "true"))
                else:
                    asyncio.create_task(asyncio.to_thread(recorder.stop, AUDIO_PATH + ".discard", use_vad_streaming=False))

    # 1. If client uploaded native mic WAV (macOS AVAudioRecorder), use it immediately without
    # waiting synchronously for Python's PortAudio recorder thread joins and resampling.
    if not success and file is not None:
        try:
            uploaded_bytes = await file.read()
            if len(uploaded_bytes) > 512:
                with open(AUDIO_PATH, "wb") as f_out:
                    f_out.write(uploaded_bytes)
                success = True
                if recorder.is_recording:
                    if mode in ("meeting", "focused_meeting"):
                        await asyncio.to_thread(recorder.stop, AUDIO_PATH + ".discard", loopback_output_path=SYSTEM_AUDIO_PATH, use_vad_streaming=(use_vad_streaming.lower() == "true"))
                    else:
                        asyncio.create_task(asyncio.to_thread(recorder.stop, AUDIO_PATH + ".discard", use_vad_streaming=False))
        except Exception as up_err:
            print(f"[!] Failed reading client mic upload: {up_err}")

    # 2. Fall back to Python recorder if client audio was not provided or failed
    if not success and recorder.is_recording:
        success = await asyncio.to_thread(recorder.stop, AUDIO_PATH, loopback_output_path=SYSTEM_AUDIO_PATH, use_vad_streaming=(use_vad_streaming.lower() == "true"))

    t_mic_ms = (time.perf_counter() - t_mic_0) * 1000.0
    stream_session = recorder.detach_stream_session()
    
    if not success:
        if stream_session:
            stream_session.abort()
        raise HTTPException(status_code=400, detail="Recording failed or was too short.")

    final_text = recorder.committed_text.strip() if getattr(recorder, "committed_text", "") else None
    if final_text == "": final_text = None
    
    # Determine effective app and resolve per-app mode
    effective_app_id = (app_id or target_app_bundle_id or getattr(recorder, "last_app_id", "")).strip()
    effective_domain = (domain or getattr(recorder, "last_domain", "")).strip()
    effective_mode_override = (mode_override or getattr(recorder, "last_mode_override", "")).strip()
    effective_manual = (manual_override_active.lower() == "true") or getattr(recorder, "last_manual_override_active", False)

    resolved_mode_id, resolved_mode_reason = app_rules_manager.resolve_mode(
        app_id=effective_app_id,
        domain=effective_domain,
        selected_mode_id=mode,
        recording_override_mode_id=effective_mode_override or None,
        manual_override_active=effective_manual
    )

    if resolved_mode_reason in ("user_rule", "builtin_rule", "recording_override"):
        if resolved_mode_id in ("message", "email", "code", "note", "book", "punctuation_fast"):
            dictation_format_style = resolved_mode_id
            effective_mode = "dictation"
        elif resolved_mode_id == "librarian":
            effective_mode = "librarian"
        elif resolved_mode_id in ("meeting", "focused_meeting"):
            effective_mode = resolved_mode_id
        else:
            effective_mode = mode if mode != "dictation" else getattr(recorder, "recording_mode", "dictation")
    else:
        effective_mode = mode if mode != "dictation" else getattr(recorder, "recording_mode", "dictation")

    is_meeting_mode = effective_mode in ("meeting", "focused_meeting")
    mute_mic_bool = mute_microphone.lower() == "true" or getattr(recorder, "is_muted", False)
    has_system_audio = os.path.exists(SYSTEM_AUDIO_PATH) and os.path.getsize(SYSTEM_AUDIO_PATH) > 100

    if diarize_bool:
        effective_separation = "smart_llm"
    elif speaker_separation in ("off", "you_others", "smart_llm"):
        effective_separation = speaker_separation
    elif not speaker_separation:
        effective_separation = "you_others" if is_meeting_mode else "off"
    else:
        effective_separation = "off"

    target_audio = effective_client_audio or AUDIO_PATH
    temp_mixed = None
    mic_audio = None
    if is_meeting_mode and has_system_audio:
        mic_input = effective_client_audio or AUDIO_PATH
        if mute_mic_bool:
            print(f"[*] Selective meeting mode active: microphone muted, using system loopback audio only.")
            target_audio = SYSTEM_AUDIO_PATH
        else:
            if effective_separation != "off":
                print(f"[*] Meeting mode active with speaker separation '{effective_separation}' (tracks separated).")
                target_audio = SYSTEM_AUDIO_PATH
                mic_audio = mic_input
                temp_mixed = os.path.join(INPUT_DIR, f"mixed_{uuid.uuid4().hex}.wav")
                mix_audio(SYSTEM_AUDIO_PATH, mic_input, temp_mixed)
            else:
                print(f"[*] Mixing {effective_mode} system loopback audio with microphone audio...")
                temp_mixed = os.path.join(INPUT_DIR, f"mixed_{uuid.uuid4().hex}.wav")
                mix_audio(SYSTEM_AUDIO_PATH, mic_input, temp_mixed)
                target_audio = temp_mixed

    if getattr(recorder, "has_paused", False):
        print("[*] Recording included pause/resume cycles. Using default full-file Whisper transcription for maximum accuracy.")
        final_text = None
    elif use_vad_streaming.lower() != "true":
        print("[*] VAD Streaming disabled by user. Ignoring VAD text to force LLM transcription.")
        final_text = None
    elif is_meeting_mode and has_system_audio:
        print("[*] System audio recorded in meeting mode. Ignoring mic-only VAD text to transcribe full mixed audio.")
        final_text = None
    
    streamed_provider = None
    if stream_session is not None:
        if is_meeting_mode or translate_bool:
            stream_session.abort()
        else:
            set_status("Finalizing live transcription...")
            t_fin = time.perf_counter()
            streamed = await stream_session.finalize()
            fin_ms = (time.perf_counter() - t_fin) * 1000.0
            if streamed:
                final_text = transcribe_service.postprocess_transcript(streamed, vocabulary_manager.get_all())
                streamed_provider = stream_session.label
                TranscribeService.last_whisper_ms = fin_ms
                TranscribeService.last_provider = stream_session.label
                print(f"[+] {stream_session.label}: final text ready {fin_ms:.0f} ms after stop")
            else:
                print(f"[*] {stream_session.label} produced no text; falling back to whole-file transcription")
                final_text = None
    
    skip_cloud_fallback = False
    if stream_session is not None and getattr(stream_session, 'auth_failed', False):
        skip_cloud_fallback = True
        print(f"[*] Cloud streaming failed authentication (401); skipping doomed REST retry and falling straight to local speech engine.")
    
    set_status("Fetching GitHub context...")
    if final_text:
        print("[*] Using VAD stitched text for dictation!")
    
    try:
        res = await pipeline.process_transcription(
            target_audio, effective_mode, dictation_format_style, git_provider, github_token, github_repo, gitlab_host, gitlab_token, gitlab_repo, github_commits, github_prs,
            confluence_url, confluence_space, confluence_user, confluence_token,
            confluence_page_title, target_type, obsidian_path, linear_api_token, linear_workspace_id, linear_search_all,
            llm_provider, llm_base_url, llm_model, llm_api_key, openai_api_key, language, translate_bool,
            enable_auto_completion=auto_complete_bool,
            enable_self_correction=self_correction_bool,
            self_correction_model=self_correction_model,
            pre_transcribed_text=final_text,
            pre_transcribed_provider=streamed_provider,
            mode_style=mode_style,
            correction_location=correction_location,
            enable_diarization=diarize_bool,
            diarization_model=diarization_model,
            target_language=target_language,
            translation_method=translation_method,
            translation_model=translation_model,
            is_incognito=incognito_bool,
            custom_prompt_text=custom_prompt,
            tags=tags,
            speaker_separation=effective_separation,
            speaker_you_label=speaker_you_label.strip() or "You",
            meeting_show_timestamps=meeting_show_timestamps.lower() == "true",
            mic_audio_path=mic_audio,
            mixed_audio_path=temp_mixed or target_audio,
            target_app_name=target_app_name,
            target_app_bundle_id=target_app_bundle_id,
            app_id=effective_app_id,
            mode_id=resolved_mode_id,
            mode_reason=resolved_mode_reason,
            skip_cloud=skip_cloud_fallback
        )
    finally:
        if temp_mixed and os.path.exists(temp_mixed):
            try: os.remove(temp_mixed)
            except: pass
        if os.path.exists(SYSTEM_AUDIO_PATH):
            try: os.remove(SYSTEM_AUDIO_PATH)
            except: pass

    t_total_ms = (time.perf_counter() - t_start) * 1000.0
    whisper_ms = getattr(TranscribeService, 'last_whisper_ms', 0.0)
    provider_name = getattr(TranscribeService, 'last_provider', 'Speech-to-Text')
    llm_ms = res.get('llm_ms', 0.0) if isinstance(res, dict) else 0.0
    post_ms = res.get('post_ms', 0.0) if isinstance(res, dict) else 0.0
    correction_ms = res.get('correction_ms', 0.0) if isinstance(res, dict) else 0.0
    overhead_ms = max(0.0, t_total_ms - t_mic_ms - whisper_ms - llm_ms - post_ms - correction_ms)

    text_word_count = len(res.get("text", "").split()) if (isinstance(res, dict) and "text" in res and res.get("text")) else 0
    speaking_wpm = res.get("avg_speaking_wpm", 0) if isinstance(res, dict) else 0
    engine_wpm = res.get("avg_engine_wpm", 0) if isinstance(res, dict) else 0

    try:
        print("\n" + "+-" + "-" * 68 + "-+")
        print("|          [TIME] DICTY ENGINE STAGE-BY-STAGE TIMING BREAKDOWN         |")
        print("+-" + "-" * 68 + "-+")
        print(f"|  Stage 1: Mic Stop & Audio Buffer Flush   | {t_mic_ms:8.1f} ms                |")
        print(f"|  Stage 2: Audio STT Transcription         | {whisper_ms:8.1f} ms  [{provider_name[:16]:<16}] |")
        print(f"|  Stage 3: Vocabulary & Regex Normalization| {post_ms:8.1f} ms                |")
        if correction_ms > 0:
            print(f"|  Stage 4: Self-Correction ({dictation_format_style[:12]:<12}) | {correction_ms:8.1f} ms                |")
        if llm_ms > 0:
            print(f"|  Stage 5: LLM Reformatting ({dictation_format_style[:12]:<12}) | {llm_ms:8.1f} ms                |")
        print(f"|  Stage 6: Serialization & DB Overhead     | {overhead_ms:8.1f} ms                |")
        print("+-" + "-" * 68 + "-+")
        print(f"|  TOTAL END-TO-END ENGINE LATENCY          | {t_total_ms:8.1f} ms ({t_total_ms/1000.0:4.2f} s)          |")
        print(f"|  Words Transcribed: {text_word_count:<4d}  |  Speaking WPM: {speaking_wpm:<4d}  |  Engine WPM: {engine_wpm:<4d} |")
        print("+-" + "-" * 68 + "-+\n")
        if sys.stdout:
            sys.stdout.flush()
    except Exception:
        pass

    if isinstance(res, dict):
        res["timings"] = {
            "mic_stop_ms": round(t_mic_ms, 1),
            "whisper_ms": round(whisper_ms, 1),
            "provider": provider_name,
            "post_ms": round(post_ms, 1),
            "llm_ms": round(llm_ms, 1),
            "correction_ms": round(correction_ms, 1),
            "overhead_ms": round(overhead_ms, 1),
            "total_ms": round(t_total_ms, 1)
        }
        res["mode_id"] = resolved_mode_id
        res["mode_reason"] = resolved_mode_reason
        res["app_id"] = effective_app_id
        if effective_app_id and resolved_mode_reason in ("recording_override", "manual_override"):
            suggestion = app_rules_manager.check_suggestion(
                history_records=history_manager.get_all(),
                app_id=effective_app_id,
                app_name=target_app_name,
            )
            if suggestion:
                app_rules_manager.mark_suggestion_prompted(effective_app_id)
                res["suggestion"] = suggestion

    try:
        telemetry.track("transcription_completed", {
            "mode": mode,
            "dictation_format_style": dictation_format_style,
            "is_incognito": incognito_bool,
            "total_latency_ms": round(t_total_ms, 1),
            "whisper_latency_ms": round(whisper_ms, 1),
            "llm_latency_ms": round(llm_ms, 1),
            "correction_latency_ms": round(correction_ms, 1),
            "text_word_count": text_word_count,
            "speaking_wpm": speaking_wpm,
            "engine_wpm": engine_wpm
        })
    except Exception:
        pass

    set_status("Idle")
    return res

@router.websocket("/ws/transcribe/stream")
async def websocket_transcribe_stream(websocket: WebSocket):
    origin = websocket.headers.get("origin")
    sec_fetch_site = websocket.headers.get("sec-fetch-site")
    if sec_fetch_site == "cross-site" or not is_origin_allowed(origin):
        await websocket.close(code=1008, reason="Forbidden origin")
        return
    await websocket.accept(subprotocol=engine_auth.ws_accept_subprotocol(websocket))
    active_websockets.append(websocket)
    try:
        while True:
            # Keep connection alive
            await websocket.receive_text()
    except WebSocketDisconnect:
        if websocket in active_websockets:
            active_websockets.remove(websocket)
class PartialText(BaseModel):
    text: str

@router.post("/recording/internal/partial")
async def internal_partial(partial: PartialText):
    await broadcast_partial_transcription(partial.text)
    return {"status": "ok"}

@router.post("/recording/cancel")
async def cancel_recording():
    if recorder.is_recording:
        session = recorder.detach_stream_session()
        if session:
            session.abort()
        recorder.stop(AUDIO_PATH, loopback_output_path=SYSTEM_AUDIO_PATH)
        if os.path.exists(AUDIO_PATH):
            try: os.remove(AUDIO_PATH)
            except: pass
        if os.path.exists(SYSTEM_AUDIO_PATH):
            try: os.remove(SYSTEM_AUDIO_PATH)
            except: pass
    set_status("Idle")
    telemetry.track("recording_canceled")
    return {"status": "cancelled"}

@router.post("/recording/pause")
async def pause_recording():
    if recorder.is_recording:
        play_pause_chime()
        recorder.pause()
        telemetry.track("recording_paused")
        return {"status": "paused"}
    return {"status": "not_recording"}

@router.post("/recording/resume")
async def resume_recording():
    if recorder.is_recording:
        play_resume_chime()
        recorder.resume()
        telemetry.track("recording_resumed")
        return {"status": "resumed"}
    return {"status": "not_recording"}

@router.post("/recording/toggle_pause")
async def toggle_pause_recording():
    if not recorder.is_recording:
        return {"status": "not_recording", "is_recording": False, "is_paused": False}
    
    if getattr(recorder, "is_paused", False):
        play_resume_chime()
        recorder.resume()
        telemetry.track("recording_resumed")
        return {"status": "resumed", "is_recording": True, "is_paused": False}
    else:
        play_pause_chime()
        recorder.pause()
        telemetry.track("recording_paused")
        return {"status": "paused", "is_recording": True, "is_paused": True}

@router.post("/recording/mute")
async def mute_recording(is_muted: bool = True):
    if recorder.is_recording:
        recorder.set_muted(is_muted)
        return {"status": "success", "is_muted": is_muted}
    return {"status": "not_recording", "is_muted": is_muted}
