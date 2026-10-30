from fastapi import APIRouter
import httpx
import os
import tempfile
from pydantic import BaseModel
from services.paths import DATA_DIR
from fastapi import Form, HTTPException, Request
from llm_service import LLMService
from typing import List, Optional
from datetime import datetime
from prompts import get_dictation_book_system_prompt, get_dictation_code_system_prompt, get_dictation_custom_system_prompt, get_dictation_email_system_prompt, get_dictation_meeting_system_prompt, get_dictation_message_system_prompt, get_dictation_note_system_prompt, get_meeting_summary_system_prompt
from services.stores import history_manager, local_pending_manager
from services.status import set_status
from services import pipeline

router = APIRouter()


@router.post("/history/summarize/{record_id}")
async def summarize_history(
    record_id: str,
    llm_provider: str = Form("openrouter"),
    llm_base_url: str = Form("http://localhost:1234/v1"),
    llm_model: str = Form("qwen/qwen-3.5-flash"),
    llm_api_key: str = Form(""),
    openai_api_key: str = Form(""),
    notes: Optional[str] = Form(None)
):
    from prompts import get_meeting_summary_system_prompt
    import auth
    
    record = history_manager.get_all()
    record = next((r for r in record if r["id"] == record_id), None)
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
        
    source_text = record.get("text", "")
    if not source_text:
        return {"status": "error", "message": "No text to summarize"}
        
    if notes is not None:
        notes_val = notes.strip() if notes.strip() else None
        history_manager.update_record(record_id, {"notes": notes_val})
        record["notes"] = notes_val

    from llm_service import LLMService
    
    set_status("Summarizing...")
    system_prompt = get_meeting_summary_system_prompt()
    
    user_notes = record.get("notes") or ""
    prompt_parts = []
    if user_notes.strip():
        prompt_parts.append(
            f"### Additional User Notes & Context:\n{user_notes.strip()}\n"
            f"(Note: Use the notes above to clarify company-specific terms, attendees, acronyms, or topics.)"
        )
    prompt_parts.append(f"### Meeting Transcript:\n{source_text}")
    prompt = "\n\n".join(prompt_parts)
    
    try:
        llm = LLMService()
        summary = await llm.generate(
            prompt=prompt,
            system_prompt=system_prompt,
            model=llm_model,
            api_key=openai_api_key if llm_provider == "openai" else llm_api_key,
            provider=llm_provider,
            base_url=llm_base_url
        )
        creds = 2 if llm_provider == "dicty_cloud" else 0
    except httpx.HTTPStatusError as e:
        status = e.response.status_code
        if status == 400:
            error_msg = "Selected model is not supported or parameters are invalid."
        elif status == 401:
            error_msg = "Invalid API Key. Please check your settings."
        elif status == 402:
            error_msg = "Insufficient credits or balance."
        elif status == 429:
            error_msg = "Rate limit exceeded. Please try again later."
        else:
            error_msg = f"Server returned error code {status}."
        print(f"[!] Summarization HTTP error: {e}")
        return {"status": "error", "message": error_msg}
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"[!] Summarization error: {e}")
        return {"status": "error", "message": f"Summarization failed: {e}"}
    
    if creds > 0 and llm_provider == "dicty_cloud":
        auth.SecureAuthManager.deduct_balance(creds)
        
    # Update total credits used on the record
    current_creds = record.get("credits_used", 0) or 0
    updated = history_manager.update_record(record_id, {
        "summary": summary,
        "credits_used": current_creds + creds
    })
    set_status("Idle")
    
    return {"status": "success", "summary": summary, "record": updated}

@router.get("/history")
async def get_history():
    records = history_manager.get_all()
    for r in records:
        af = r.get("audio_file", "")
        r["has_audio"] = bool(af and os.path.exists(af))
    return {"history": records}

@router.get("/history/audio/{record_id}")
async def get_history_audio(record_id: str, request: Request):
    records = history_manager.get_all()
    record = next((r for r in records if r["id"] == record_id), None)
    if not record or not record.get("audio_file"):
        raise HTTPException(status_code=404, detail="Audio file not found")
    
    audio_path = os.path.realpath(record["audio_file"])
    allowed_dirs = [os.path.realpath(DATA_DIR), os.path.realpath(tempfile.gettempdir())]
    if not any(audio_path.startswith(d + os.sep) or audio_path == d for d in allowed_dirs):
        raise HTTPException(status_code=403, detail="Access denied: audio file path outside allowed directory")
        
    if not os.path.exists(audio_path):
        raise HTTPException(status_code=404, detail="Audio file not found")
    
    with open(audio_path, "rb") as f:
        audio_data = f.read()

    from fastapi import Response

    # AVFoundation probes audio with Range requests. Without 206 support it
    # rejects the asset even though the bytes were served.
    range_header = request.headers.get("range", "")
    if range_header.startswith("bytes="):
        try:
            spec = range_header[6:].split(",", 1)[0].strip()
            start_s, end_s = spec.split("-", 1)
            if start_s:
                start = int(start_s)
                end = int(end_s) if end_s else len(audio_data) - 1
            else:
                suffix_length = int(end_s)
                start = max(0, len(audio_data) - suffix_length)
                end = len(audio_data) - 1
            start = max(0, min(start, len(audio_data) - 1))
            end = max(start, min(end, len(audio_data) - 1))
            return Response(
                content=audio_data[start:end + 1],
                status_code=206,
                media_type="audio/wav",
                headers={
                    "Accept-Ranges": "bytes",
                    "Content-Range": f"bytes {start}-{end}/{len(audio_data)}",
                },
            )
        except (ValueError, IndexError):
            pass

    return Response(
        content=audio_data,
        media_type="audio/wav",
        headers={"Accept-Ranges": "bytes"},
    )

class ReprocessRequest(BaseModel):
    mode: str = "dictation"
    format_style: str = "raw"
    custom_prompt: Optional[str] = None
    retranscribe_audio: bool = False
    language: str = "auto"
    llm_provider: Optional[str] = None
    llm_base_url: Optional[str] = None
    llm_model: Optional[str] = None
    llm_api_key: Optional[str] = None
    openai_api_key: Optional[str] = None
    speaker_separation: Optional[str] = None
    speaker_you_label: Optional[str] = "You"
    meeting_show_timestamps: bool = False
    enable_self_correction: bool = False
    self_correction_model: str = ""

@router.post("/history/reprocess/{record_id}")
async def reprocess_history(record_id: str, req: ReprocessRequest):
    records = history_manager.get_all()
    record = next((r for r in records if r["id"] == record_id), None)
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
        
    audio_path = record.get("audio_file", "")
    has_audio = bool(audio_path and os.path.exists(audio_path))
    audio_file_sys = record.get("audio_file_sys")
    audio_file_mic = record.get("audio_file_mic")
    has_separate = bool(audio_file_sys and os.path.exists(audio_file_sys))
    
    if req.retranscribe_audio:
        if not has_audio and not has_separate:
            raise HTTPException(status_code=400, detail="Audio file no longer exists on disk to re-transcribe")
        sys_audio = audio_file_sys if has_separate else audio_path
        mic_audio = audio_file_mic if (audio_file_mic and os.path.exists(audio_file_mic)) else None
        sep_mode = req.speaker_separation or record.get("speaker_separation") or ("you_others" if req.mode in ("meeting", "focused_meeting") else "off")
        res = await pipeline.process_transcription(
            audio_path=sys_audio,
            mode=req.mode,
            dictation_format_style=req.format_style,
            llm_provider=req.llm_provider or "openrouter",
            llm_base_url=req.llm_base_url or "http://localhost:1234/v1",
            llm_model=req.llm_model or "qwen/qwen-3.5-flash",
            llm_api_key=req.llm_api_key or "",
            openai_api_key=req.openai_api_key or "",
            language=req.language or "auto",
            custom_prompt_text=req.custom_prompt,
            existing_record_id=record_id,
            speaker_separation=sep_mode,
            speaker_you_label=req.speaker_you_label or "You",
            meeting_show_timestamps=req.meeting_show_timestamps,
            enable_self_correction=req.enable_self_correction,
            self_correction_model=req.self_correction_model,
            mic_audio_path=mic_audio,
            mixed_audio_path=audio_path
        )
        if isinstance(res, dict) and res.get("status") in ["error", "ignored"]:
            return res
        updated = next((r for r in history_manager.get_all() if r["id"] == record_id), None)
        return {"status": "success", "record": updated}
    else:
        # Fast Re-Format (LLM only)
        source_text = record.get("text", "")
        if not source_text:
            raise HTTPException(status_code=400, detail="Record has no text to re-process")
            
        formatted_text = source_text
        summary_text = record.get("summary")
        
        # Determine system prompt
        if req.custom_prompt and req.custom_prompt.strip():
            system_prompt = req.custom_prompt.strip()
        elif req.mode in ["meeting", "focused_meeting"]:
            system_prompt = get_meeting_summary_system_prompt()
        elif req.format_style != "raw":
            if req.format_style == "message":
                system_prompt = get_dictation_message_system_prompt()
            elif req.format_style == "email":
                system_prompt = get_dictation_email_system_prompt()
            elif req.format_style == "note":
                system_prompt = get_dictation_note_system_prompt()
            elif req.format_style == "meeting_summary":
                system_prompt = get_dictation_meeting_system_prompt()
            elif req.format_style == "book":
                system_prompt = get_dictation_book_system_prompt()
            elif req.format_style == "code":
                system_prompt = get_dictation_code_system_prompt()
            else:
                system_prompt = get_dictation_custom_system_prompt()
        else:
            system_prompt = None
            
        if system_prompt:
            set_status("Re-formatting transcript (LLM)...")
            llm = LLMService()
            try:
                llm_res = await llm.generate(
                    prompt=source_text,
                    system_prompt=system_prompt,
                    model=req.llm_model,
                    api_key=req.openai_api_key if req.llm_provider == "openai" else req.llm_api_key,
                    provider=req.llm_provider,
                    base_url=req.llm_base_url
                )
                if llm_res and llm_res.strip():
                    formatted_text = llm_res.strip()
                    if req.mode in ["meeting", "focused_meeting"]:
                        summary_text = formatted_text
            except Exception as e:
                print(f"[!] Re-formatting failed: {e}")
                err_str = str(e)
                if "429" in err_str or "rate limit" in err_str.lower():
                    clean_msg = "Upstream model rate limit reached (429). Please retry in a few seconds or switch model in Settings."
                elif "401" in err_str or "unauthorized" in err_str.lower():
                    clean_msg = "Invalid API key for LLM provider. Please check Settings."
                elif "402" in err_str or "payment" in err_str.lower() or "credits" in err_str.lower():
                    clean_msg = "Insufficient credits on LLM provider."
                elif "timeout" in err_str.lower() or "timed out" in err_str.lower():
                    clean_msg = "Request timed out waiting for LLM response."
                else:
                    clean_msg = err_str.split("For more information check:")[0].strip()
                    if "Client error '" in clean_msg:
                        clean_msg = clean_msg.split("' for url")[0].replace("Client error '", "")
                return {"status": "error", "message": clean_msg}
            finally:
                set_status("Idle")
                
        timestamp = datetime.now().astimezone().isoformat(timespec='seconds')
        updates = {
            "text": formatted_text,
            "mode": req.mode,
            "reprocessed_at": timestamp
        }
        if summary_text:
            updates["summary"] = summary_text
            
        updated = history_manager.update_record(record_id, updates)
        return {"status": "success", "record": updated}

@router.delete("/history/clear")
async def clear_history_all():
    history_manager.clear_all()
    return {"status": "success", "message": "All history cleared"}

@router.delete("/history/{record_id}")
async def delete_history(record_id: str):
    record = history_manager.delete_record(record_id)
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
    return {"status": "success"}

class RetentionSettingsRequest(BaseModel):
    retention_period: Optional[str] = "forever"
    scrub_audio_immediately: Optional[bool] = False

@router.get("/history/settings/retention")
async def get_retention_settings():
    return history_manager.get_retention_settings()

@router.post("/history/settings/retention")
async def update_retention_settings(req: RetentionSettingsRequest):
    data = req.model_dump() if hasattr(req, "model_dump") else req.dict()
    updated = history_manager.save_retention_settings(data)
    cleanup_res = {"deleted_records": 0, "scrubbed_audio": 0, "total_records": len(history_manager.get_all())}
    if updated.get("retention_period") != "forever":
        cleanup_res = history_manager.cleanup_retention(scrub_past_audio=False)
    return {"settings": updated, "cleanup": cleanup_res}

@router.post("/history/cleanup")
async def run_history_cleanup(scrub_past_audio: bool = False):
    res = history_manager.cleanup_retention(scrub_past_audio=scrub_past_audio)
    return {"status": "success", "result": res}

class HistoryRecordUpdateRequest(BaseModel):
    title: Optional[str] = None
    tags: Optional[List[str]] = None
    notes: Optional[str] = None

@router.patch("/history/{record_id}")
async def patch_history_record(record_id: str, req: HistoryRecordUpdateRequest):
    updates = {}
    if req.title is not None:
        updates["title"] = req.title.strip() if req.title.strip() else None
    if req.tags is not None:
        clean_tags = []
        for t in req.tags:
            cleaned = t.strip().lstrip("#").lower()
            if cleaned and cleaned not in clean_tags:
                clean_tags.append(cleaned)
        updates["tags"] = clean_tags
    if req.notes is not None:
        updates["notes"] = req.notes.strip() if req.notes.strip() else None
        
    record = history_manager.update_record(record_id, updates)
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
    return {"status": "success", "record": record}

@router.post("/history/{record_id}/update")
async def post_history_record_update(record_id: str, req: HistoryRecordUpdateRequest):
    return await patch_history_record(record_id, req)

class UpdateHistoryTagsRequest(BaseModel):
    tags: list[str]

@router.put("/history/{record_id}/tags")
@router.patch("/history/{record_id}/tags")
async def update_history_tags(record_id: str, req: UpdateHistoryTagsRequest):
    recs = history_manager.get_all()
    record = next((r for r in recs if r["id"] == record_id), None)
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
    seen = set()
    cleaned = []
    for t in req.tags:
        if t and t.strip():
            t_clean = t.strip().lstrip("#")
            if t_clean and t_clean.lower() not in seen:
                seen.add(t_clean.lower())
                cleaned.append(t_clean)
    updated = history_manager.update_record(record_id, {"tags": cleaned})
    return {"status": "success", "record": updated, "tags": cleaned}


@router.get("/stats")
async def get_stats(period: str = "all"):
    stats_res = history_manager.get_stats(period)
    if len(stats_res) == 4:
        total, avg_s, avg_e, count = stats_res
    else:
        total, avg_s, avg_e = stats_res
        count = 0
    
    # Calculate Librarian Impact
    librarian_updates = 0
    try:
        history = local_pending_manager.get_history()
        librarian_updates = sum(1 for item in history if item.get("status") == "approved")
    except Exception:
        pass
        
    return {
        "period": period,
        "total_words": total,
        "avg_speaking_wpm": avg_s,
        "avg_engine_wpm": avg_e,
        "total_recordings": count,
        "librarian_updates": librarian_updates
    }
