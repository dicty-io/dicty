from fastapi import APIRouter
import asyncio
import dictation_metrics
import engine_auth
import httpx
import meeting_dialogue
import os
import shutil
import tempfile
import time
import uuid
import wave
import numpy as np
from services.paths import AUDIO_PATH, DATA_DIR, INPUT_DIR
from fastapi import File, Form, UploadFile, WebSocket, WebSocketDisconnect
from transcribe_service import TranscribeService
from services.stores import VocabularyManager, history_manager, vocabulary_manager
from services.pipeline import _is_cloud_provider
from services.mode_requests import _resolve_mode_request
from datetime import datetime
from services.origins import is_origin_allowed
from services.audio import mix_audio
from services.state import model_manager, recorder, transcriber
from services import pipeline

router = APIRouter()


@router.websocket("/ws/transcribe/tail")
async def websocket_transcribe_tail(websocket: WebSocket):
    origin = websocket.headers.get("origin")
    sec_fetch_site = websocket.headers.get("sec-fetch-site")
    if sec_fetch_site == "cross-site" or not is_origin_allowed(origin):
        await websocket.close(code=1008, reason="Forbidden origin")
        return
    await websocket.accept(subprotocol=engine_auth.ws_accept_subprotocol(websocket))
    
    # Receive initial configuration with file path
    data = await websocket.receive_json()
    wav_path = data.get("file_path")
    if not wav_path or not isinstance(wav_path, str) or wav_path.startswith("-"):
        await websocket.send_json({"status": "error", "message": "Invalid file path"})
        await websocket.close(code=1008, reason="Invalid file path")
        return

    # Accept only a plain filename (no path separators or traversal components)
    requested_name = wav_path.strip()
    safe_name = os.path.basename(requested_name)
    if (
        not safe_name
        or safe_name != requested_name
        or safe_name in (".", "..")
        or "/" in requested_name
        or "\\" in requested_name
    ):
        await websocket.send_json({"status": "error", "message": "Invalid file path"})
        await websocket.close(code=1008, reason="Invalid file path")
        return
    
    allowed_dirs = [
        os.path.realpath(INPUT_DIR),
        os.path.realpath(tempfile.gettempdir()),
        os.path.realpath(DATA_DIR)
    ]
    resolved_candidate = None
    for ad in allowed_dirs:
        cand = os.path.join(ad, safe_name)
        real_cand = os.path.realpath(cand)
        if os.path.commonpath([ad, real_cand]) != ad:
            continue
        if os.path.exists(real_cand):
            resolved_candidate = real_cand
            break

    if not resolved_candidate:
        await websocket.send_json({"status": "error", "message": "Access denied: file outside permitted directories or not found"})
        await websocket.close(code=1008, reason="Access denied")
        return

    real_wav_path = resolved_candidate
    ext = os.path.splitext(real_wav_path)[1].lower()
    if ext not in [".wav", ".m4a", ".mp3", ".aac", ".flac", ".ogg", ".caf"]:
        await websocket.send_json({"status": "error", "message": "Unsupported file format"})
        await websocket.close(code=1008, reason="Unsupported file format")
        return
    
    transcriber = TranscribeService()
    transcriber.whisper_cpp_path = os.getenv("WHISPER_CPP_PATH")
    transcriber.whisper_model_path = os.getenv("WHISPER_MODEL_PATH")
    vocab_data = vocabulary_manager.get_all()
    
    try:
        while True:
            await asyncio.sleep(2.5) # Process every 2.5 seconds
            if not os.path.exists(real_wav_path):
                continue
                
            temp_wav = os.path.join(INPUT_DIR, f"live_{uuid.uuid4().hex}.wav")
            import subprocess
            
            # Use ffmpeg to safely read the incomplete growing WAV file
            cmd = ["ffmpeg", "-y", "-i", real_wav_path, "-ar", "16000", "-ac", "1", temp_wav]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            if os.path.exists(temp_wav):
                try:
                    text = await transcriber.transcribe(temp_wav, vocab_data)
                    if text and text.strip():
                        await websocket.send_json({"status": "partial", "text": text.strip()})
                except Exception as e:
                    print(f"[!] Live tail transcription error: {e}")
                finally:
                    if os.path.exists(temp_wav):
                        os.remove(temp_wav)
                        
    except WebSocketDisconnect:
        print("[*] WebSocket tail disconnected.")

@router.post("/transcribe")
async def transcribe_uploaded_audio(
    file: UploadFile = File(...),
    mic_file: UploadFile = File(None),
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
    enable_diarization: str = Form("false"),
    diarization_model: str = Form(""),
    target_language: str = Form("none"),
    translation_method: str = Form("none"),
    translation_model: str = Form(""),
    incognito_mode: str = Form("false"),
    mute_microphone: str = Form("false"),
    tags: str = Form(""),
    speaker_separation: str = Form(""),
    speaker_you_label: str = Form("You"),
    meeting_show_timestamps: str = Form("false"),
    enable_self_correction: str = Form("false"),
    self_correction_model: str = Form(""),
    target_app_name: str = Form(""),
    target_app_bundle_id: str = Form("")
):
    translate_bool = translate_to_english.lower() == "true"
    auto_complete_bool = enable_auto_completion.lower() == "true"
    diarize_bool = enable_diarization.lower() == "true"
    incognito_bool = incognito_mode.lower() == "true"
    mute_mic_bool = mute_microphone.lower() == "true"
    self_correction_bool = enable_self_correction.lower() == "true"
    self_correction_model = self_correction_model.strip() if self_correction_model else ""
    mode_style, correction_location, self_correction_bool, self_correction_model = _resolve_mode_request(
        mode, mode_id, mode_style, correction_location, self_correction_bool, self_correction_model
    )

    if diarize_bool:
        effective_separation = "smart_llm"
    elif speaker_separation in ("off", "you_others", "smart_llm"):
        effective_separation = speaker_separation
    elif not speaker_separation:
        effective_separation = "you_others" if mode in ("meeting", "focused_meeting") else "off"
    else:
        effective_separation = "off"

    print(f"\n[*] Client uploaded audio for transcription. Mode: {mode}, Style: {dictation_format_style}, Separation: {effective_separation}, GitHub Repo: {github_repo}, Diarization: {diarize_bool}, Mute Mic: {mute_mic_bool}, Target Language: {target_language}, Translation Method: {translation_method}, Incognito: {incognito_bool}, Tags: {tags}")
    
    # 1. Stop the microphone recording that Python was running in the background.
    # Pass use_vad_streaming=False so stop() does not spend up to 1s posting a final VAD chunk
    # to whisper-server (which isn't used in /transcribe anyway).
    if recorder.is_recording:
        await asyncio.to_thread(recorder.stop, AUDIO_PATH, use_vad_streaming=False)
    if mic_file is not None:
        try:
            mic_bytes = await mic_file.read()
            if len(mic_bytes) > 512:
                use_client_mic = not os.path.exists(AUDIO_PATH)
                if not use_client_mic:
                    try:
                        with wave.open(AUDIO_PATH, "rb") as w_py:
                            py_arr = np.frombuffer(w_py.readframes(w_py.getnframes()), dtype=np.int16)
                        if len(py_arr) == 0 or int(np.max(np.abs(py_arr))) < 64:
                            use_client_mic = True
                    except Exception:
                        use_client_mic = True
                if use_client_mic:
                    with open(AUDIO_PATH, "wb") as f_mic_out:
                        f_mic_out.write(mic_bytes)
        except Exception as mic_err:
            print(f"[!] Failed reading client mic_file upload: {mic_err}")
        
    temp_path = os.path.join(INPUT_DIR, f"upload_{uuid.uuid4().hex}.wav")
    with open(temp_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    target_path = temp_path
    mixed_path = None
    mic_audio = None
    if mode in ("meeting", "focused_meeting") and os.path.exists(AUDIO_PATH):
        if not mute_mic_bool:
            # Skip transcribing the microphone track if the user never spoke into it during the meeting.
            # Running a second 100s+ WAV through single-threaded whisper-server serialized both requests
            # on the GPU and doubled transcription time (~12s -> ~24s) just to transcribe silence.
            if meeting_dialogue.track_has_speech(AUDIO_PATH):
                mic_audio = AUDIO_PATH
                mixed_path = os.path.join(INPUT_DIR, f"mixed_{uuid.uuid4().hex}.wav")
                mix_audio(temp_path, AUDIO_PATH, mixed_path)
            else:
                print("[*] Meeting microphone track is silent; skipping mic transcription and mixing.")
            if effective_separation == "off":
                if mixed_path:
                    print(f"[*] Mixing {mode} system audio with microphone audio (separation off)...")
                    target_path = mixed_path
                else:
                    target_path = temp_path
            else:
                print(f"[*] Meeting mode active with speaker separation '{effective_separation}' (tracks separated).")
                target_path = temp_path
        else:
            print(f"[*] Selective meeting mode active: microphone muted, using system audio only.")
            target_path = temp_path
    
    try:
        # Note: Do NOT use recorder.committed_text (mic-only VAD) for /transcribe,
        # because /transcribe handles uploaded audio and mixed system audio (remote voices)
        # which must be transcribed from target_path via Whisper.
        result = await pipeline.process_transcription(
            target_path, mode, dictation_format_style, git_provider, github_token, github_repo, gitlab_host, gitlab_token, gitlab_repo, github_commits, github_prs,
            confluence_url, confluence_space, confluence_user, confluence_token, confluence_page_title,
            target_type, obsidian_path, linear_api_token, linear_workspace_id, linear_search_all,
            llm_provider, llm_base_url, llm_model, llm_api_key, openai_api_key, language, translate_bool,
            enable_auto_completion=auto_complete_bool, pre_transcribed_text=None,
            mode_style=mode_style,
            correction_location=correction_location,
            enable_self_correction=self_correction_bool,
            self_correction_model=self_correction_model,
            enable_diarization=diarize_bool, diarization_model=diarization_model,
            target_language=target_language, translation_method=translation_method,
            translation_model=translation_model,
            is_incognito=incognito_bool,
            tags=tags,
            speaker_separation=effective_separation,
            speaker_you_label=speaker_you_label.strip() or "You",
            meeting_show_timestamps=meeting_show_timestamps.lower() == "true",
            mic_audio_path=mic_audio,
            mixed_audio_path=mixed_path or target_path,
            target_app_name=target_app_name,
            target_app_bundle_id=target_app_bundle_id
        )
        return result
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        if mixed_path and os.path.exists(mixed_path):
            try: os.remove(mixed_path)
            except Exception: pass
        if target_path != temp_path and os.path.exists(target_path):
            os.remove(target_path)


@router.post("/transcribe/file")
async def transcribe_local_file(
    file: UploadFile = File(...),
    target_model: str = Form(""),
    language: str = Form("auto"),
    translate_to_english: str = Form("false"),
    enable_auto_completion: str = Form("false"),
    target_language: str = Form("none"),
    llm_provider: str = Form("openrouter"),
    llm_base_url: str = Form("http://localhost:1234/v1"),
    llm_model: str = Form(""),
    llm_api_key: str = Form(""),
    openai_api_key: str = Form(""),
    incognito_mode: str = Form("false")
):
    translate_bool = translate_to_english.lower() == "true"
    auto_complete_bool = enable_auto_completion.lower() == "true"
    incognito_bool = incognito_mode.lower() == "true"
    print(f"\n[*] Transcribing uploaded file. target_model: {target_model}, language: {language}, translate: {translate_bool}, auto_completion: {auto_complete_bool}, incognito: {incognito_bool}")
    
    temp_path = os.path.join(INPUT_DIR, f"pro_upload_{uuid.uuid4().hex}.tmp")
    with open(temp_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    # Convert uploaded file to 16kHz mono WAV using pydub (handles m4a, mp3, mp4, etc)
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_file(temp_path)
        audio = audio.set_frame_rate(16000).set_channels(1).set_sample_width(2)
        wav_path = os.path.join(INPUT_DIR, f"pro_upload_{uuid.uuid4().hex}.wav")
        audio.export(wav_path, format="wav")
        os.remove(temp_path)
        temp_path = wav_path
    except Exception as e:
        print(f"[-] Failed to convert audio to wav: {e}")
        
    original_model = None
    try:
        # Load specific model if requested and different from active
        if target_model and target_model != "":
            active_model = model_manager.get_active_model()
            if target_model != active_model:
                print(f"[*] Temporarily swapping active model to {target_model}")
                original_model = active_model
                model_manager.set_active_model(target_model)
                
        # Calculate duration
        try:
            with wave.open(temp_path, 'r') as wav:
                frames = wav.getnframes()
                rate = wav.getframerate()
                duration = frames / float(rate)
        except Exception:
            duration = 1.0 # fallback
            
        print(f"[*] Starting transcription of file ({duration:.2f}s)...")
        start_time = time.time()
        
        # Transcribe
        raw_text = await transcriber.transcribe(temp_path, openai_api_key=llm_api_key if llm_provider == "dicty_cloud" else openai_api_key, language=language, translate_to_english=translate_bool, enable_auto_completion=auto_complete_bool, openrouter_key=llm_api_key, provider=llm_provider)
        
        # Target Language LLM Translation
        if target_language and target_language != "none" and target_language != "":
            print(f"[*] Translating transcription to '{target_language}' via LLM...")
            system_prompt = f"You are a professional translator. Translate the following text into the language with language code: {target_language}. If the text appears to be a dialogue, interview, or conversation, format the output to clearly separate different speakers or roles (e.g., using dashes or role names). Output ONLY the translated text, nothing else. Do not add conversational filler."
            
            # Use llm_service if available, or direct httpx
            dicty_cloud_url = os.getenv("DICTY_CLOUD_URL", "https://dicty-backend.dicty-backend.workers.dev")
            
            if not openai_api_key and not llm_base_url and llm_provider != "dicty_cloud":
                return {"status": "error", "message": "No backend API Key provided for action."}
                
            from urllib.parse import urlparse
            if llm_provider == "dicty_cloud":
                url = f"{dicty_cloud_url.rstrip('/')}/v1/chat/completions"
            elif llm_provider in ("lmstudio", "ollama", "local"):
                base = llm_base_url or "http://localhost:1234/v1"
                parsed = urlparse(base)
                # Restrict local providers strictly to loopback interfaces to prevent SSRF
                if parsed.scheme not in ("http", "https") or parsed.hostname not in ("localhost", "127.0.0.1", "::1"):
                    return {"status": "error", "message": "Local LLM base URL must target localhost or 127.0.0.1"}
                port_part = f":{parsed.port}" if parsed.port else ""
                url = f"{parsed.scheme}://127.0.0.1{port_part}/v1/chat/completions"
            else:
                url = "https://openrouter.ai/api/v1/chat/completions"
                    
            api_key_to_use = llm_api_key or openai_api_key or ""
            headers = {
                "Content-Type": "application/json",
                "HTTP-Referer": "https://dicty.io",
                "X-Title": "Dicty"
            }
            if api_key_to_use:
                headers["Authorization"] = f"Bearer {api_key_to_use}"
                
            if llm_model == "qwen/qwen-3.5-flash" or llm_model == "qwen/qwen3.5-flash-02-23":
                llm_model = "openai/gpt-4o-mini"
            payload = {
                "model": llm_model or "openai/gpt-4o-mini",
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": raw_text}
                ],
                "temperature": 0.1
            }
            
            try:
                async with httpx.AsyncClient(timeout=120.0) as client:
                    resp = await client.post(url, json=payload, headers=headers)
                    if resp.status_code == 402:
                        raise Exception("Dicty Cloud credits exhausted (402 Payment Required). Please top-up.")
                    elif resp.status_code != 200:
                        print(f"[-] LLM API Error: {resp.text}")
                    resp.raise_for_status()
                    res_json = resp.json()
                    raw_text = res_json["choices"][0]["message"]["content"]
                    print("[+] Translation complete.")
            except Exception as e:
                print(f"[!] Target Language Translation failed: {e}")
                raw_text += "\n\n[Translation Failed: Unable to complete translation via LLM service]"
        
        end_time = time.time()
        transcription_time = end_time - start_time
        
        # Post-process with vocabulary
        vocab_manager = VocabularyManager()
        vocabulary = vocab_manager.get_all()
        for v in vocabulary:
            if v["word"].lower() in raw_text.lower():
                import re
                raw_text = re.sub(r'(?i)\b' + re.escape(v["word"]) + r'\b', v["replacement"], raw_text)
                
        if not incognito_bool:
            record_id = str(uuid.uuid4())
            timestamp = datetime.now().isoformat()
            history_manager.add_record({
                "id": record_id,
                "timestamp": timestamp,
                "title": None,
                "tags": [],
                "text": raw_text,
                "mode": "file_transcription",
                "audio_file": "",
                "speaking_wpm": 0,
                "engine_wpm": 0,
                "reconcile_result": None
            })
            
        print("[*] Transcription complete!")
        metrics_id = None
        try:
            used_model = target_model or model_manager.get_active_model()
            used_info = next((m for m in model_manager.get_available_models() if m["id"] == used_model), {}) or {}
            used_provider = getattr(TranscribeService, "last_provider", "unknown")
            metrics_id = dictation_metrics.record(
                mode="file_transcription", model_id=used_model, model_name=used_info.get("name") or used_model,
                provider=used_provider, is_cloud=_is_cloud_provider(used_provider),
                audio_duration_s=duration, word_count=len((raw_text or "").split()),
                engine_ms=(time.time() - start_time) * 1000.0, incognito=incognito_bool)
        except Exception as m_err:
            print(f"[!] Metrics record skipped: {m_err}")
        return {
            "status": "success",
            "metrics_id": metrics_id,
            "text": raw_text,
            "duration": duration,
            "transcription_time": transcription_time
        }
        
    finally:
        if original_model is not None:
            print(f"[*] Restoring active model to {original_model}")
            model_manager.set_active_model(original_model)
        # Clean up
        if os.path.exists(temp_path):
            os.remove(temp_path)
