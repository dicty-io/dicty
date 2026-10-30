from fastapi import APIRouter
import asyncio
import os
import uuid
from pydantic import BaseModel
from services.paths import HISTORY_DIR
from fastapi import HTTPException, Request
from typing import Optional
from datetime import datetime
from services.stores import history_manager
try:
    from tts_service import tts_service
except Exception as _tts_err:
    import traceback
    print(f"[-] Warning: tts_service could not be imported: {_tts_err}")
    traceback.print_exc()
    tts_service = None
import logging

_dicty_logger = logging.getLogger("dicty")

router = APIRouter()


class TTSRequest(BaseModel):
    text: str
    voice: Optional[str] = "af_heart"
    blend_voice: Optional[str] = None
    blend_ratio: Optional[float] = 0.5
    expressiveness: Optional[float] = 0.0
    speed: Optional[float] = 1.0
    sentence_pause: Optional[float] = 0.25
    clause_pause: Optional[float] = 0.10
    continuous: Optional[bool] = False
    save_record: Optional[bool] = False

@router.get("/tts/status")
async def get_tts_status():
    if not tts_service:
        return {"installed": False, "error": "TTS service not available"}
    return tts_service.get_status()

@router.get("/tts/voices")
async def get_tts_voices():
    if not tts_service:
        return []
    return tts_service.get_status().get("voices", [])

@router.post("/tts/download")
async def download_tts(req: Request, voice_id: Optional[str] = None):
    if not tts_service:
        raise HTTPException(status_code=500, detail="TTS service not available")
    target_voice_id = voice_id
    if not target_voice_id:
        try:
            body = await req.json()
            if isinstance(body, dict):
                target_voice_id = body.get("voice_id")
        except Exception:
            pass
    return tts_service.start_download_background(voice_id=target_voice_id)

@router.post("/tts/voice/delete")
async def delete_tts_voice(req: Request):
    if not tts_service:
        raise HTTPException(status_code=500, detail="TTS service not available")
    try:
        body = await req.json()
        if not isinstance(body, dict):
            raise HTTPException(status_code=400, detail="Invalid request body, expected JSON object")
        voice_id = body.get("voice_id", "")
        success = tts_service.delete_voice(voice_id)
        return {"status": "success" if success else "not_found", "voice_id": voice_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/tts/speak")
async def speak_text(req: TTSRequest):
    if not tts_service:
        raise HTTPException(status_code=500, detail="TTS service not initialized")
    try:
        from fastapi import Response
        audio_wav = await asyncio.to_thread(
            tts_service.synthesize,
            text=req.text,
            voice=req.voice or "af_heart",
            blend_voice=req.blend_voice,
            blend_ratio=req.blend_ratio if req.blend_ratio is not None else 0.5,
            expressiveness=req.expressiveness if req.expressiveness is not None else 0.0,
            speed=req.speed or 1.0,
            sentence_pause=req.sentence_pause if req.sentence_pause is not None else 0.25,
            clause_pause=req.clause_pause if req.clause_pause is not None else 0.10,
            continuous=bool(req.continuous),
        )

        record_id = None
        if req.save_record:
            try:
                record_id = f"tts_{uuid.uuid4().hex[:12]}"
                os.makedirs(HISTORY_DIR, exist_ok=True)
                audio_file_path = os.path.join(HISTORY_DIR, f"{record_id}.wav")
                with open(audio_file_path, "wb") as f:
                    f.write(audio_wav)
                
                import wave, io
                with wave.open(io.BytesIO(audio_wav), "rb") as wf:
                    dur_sec = wf.getnframes() / float(wf.getframerate())
                
                voice_label = req.voice or "af_heart"
                if req.blend_voice and req.blend_voice != voice_label:
                    voice_label = f"{voice_label} + {req.blend_voice}"
                
                history_record = {
                    "id": record_id,
                    "text": req.text.strip(),
                    "timestamp": datetime.now().isoformat(),
                    "mode": "tts",
                    "audio_file": audio_file_path,
                    "duration": round(dur_sec, 2),
                    "voice": voice_label,
                    "tags": ["TTS"]
                }
                history_manager.add_record(history_record)
                _dicty_logger.info(f"Saved TTS record {record_id} to history.")
            except Exception as se:
                _dicty_logger.warning(f"Failed to persist TTS record to history: {se}")

        headers = {}
        if record_id:
            headers["X-Record-Id"] = record_id
        return Response(content=audio_wav, media_type="audio/wav", headers=headers)
    except FileNotFoundError as fnf:
        raise HTTPException(status_code=404, detail=str(fnf))
    except Exception as e:
        _dicty_logger.error(f"TTS synthesis failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
