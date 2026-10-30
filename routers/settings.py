from fastapi import APIRouter
import asyncio
import dictation_metrics
import json
import os
import transcribe_service
from typing import Any, Dict, Optional
from pydantic import BaseModel
from services.state import model_manager
from services.whisper_server import start_whisper_server, stop_whisper_server
from telemetry_service import telemetry
from services import whisper_server

router = APIRouter()


class ClientTelemetryEvent(BaseModel):
    event: str
    properties: Optional[Dict[str, Any]] = None
    user_id: Optional[str] = None

@router.post("/telemetry/event")
async def post_client_telemetry_event(item: ClientTelemetryEvent):
    if item.user_id:
        telemetry.identify(item.user_id)
    telemetry.track(item.event, item.properties)
    return {"status": "ok"}

@router.post("/metrics/{metrics_id}/latency")
async def set_metrics_latency(metrics_id: str, item: Dict[str, Any]):
    ok = await asyncio.to_thread(dictation_metrics.set_latency, metrics_id,
                                 float(item.get("end_to_end_ms", 0)), bool(item.get("pasted", False)))
    return {"status": "ok" if ok else "not_found"}

@router.get("/metrics/recent")
async def get_recent_metrics(limit: int = 10):
    return {"items": await asyncio.to_thread(dictation_metrics.recent, max(1, min(limit, dictation_metrics.MAX_ENTRIES)))}

@router.get("/metrics/models")
async def get_model_metrics(period: str = "all"):
    return {"models": await asyncio.to_thread(dictation_metrics.per_model, period)}

@router.get("/metrics/corrections")
async def get_correction_metrics(period: str = "all"):
    return {"models": await asyncio.to_thread(dictation_metrics.per_correction, period)}

@router.get("/metrics/formatting")
async def get_formatting_metrics(period: str = "all"):
    return {"models": await asyncio.to_thread(dictation_metrics.per_formatting, period)}

@router.get("/metrics/hardware")
async def get_hardware_metrics():
    return await asyncio.to_thread(dictation_metrics.hardware)

class STTKeys(BaseModel):
    openai: Optional[str] = None
    deepgram: Optional[str] = None
    groq: Optional[str] = None
    elevenlabs: Optional[str] = None
    openrouter: Optional[str] = None

@router.post("/settings/stt_keys")
async def set_stt_keys(keys: STTKeys):
    """Receives the user's own speech-to-text provider keys from the app's Keychain. Kept in memory only."""
    transcribe_service.set_user_stt_keys({k: v for k, v in keys.model_dump().items() if v is not None})
    return {"configured": transcribe_service.stt_key_status()}

@router.get("/settings/stt_keys")
async def get_stt_keys_status():
    """Which providers have a key (booleans only, keys are never returned)."""
    return {"configured": transcribe_service.stt_key_status()}

class AuthorNameSetting(BaseModel):
    author_name: str

@router.get("/settings/author_name")
async def get_author_name_setting():
    try:
        cfg = model_manager.get_settings()
        return {"author_name": cfg.get("author_name", "")}
    except Exception:
        return {"author_name": ""}

@router.post("/settings/author_name")
async def set_author_name_setting(req: AuthorNameSetting):
    try:
        from model_manager import SETTINGS_FILE
        cfg = {}
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                cfg = json.load(f)
        cfg["author_name"] = req.author_name.strip()
        with open(SETTINGS_FILE, "w") as f:
            json.dump(cfg, f, indent=2)
        return {"status": "saved", "author_name": cfg["author_name"]}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.get("/telemetry/settings")
async def get_telemetry_settings():
    return {"share_anonymous_usage": telemetry.remote_enabled, "remote_available": telemetry.remote_sink is not None}

class TelemetrySettings(BaseModel):
    share_anonymous_usage: bool

@router.post("/telemetry/settings")
async def set_telemetry_settings(item: TelemetrySettings):
    telemetry.set_remote_enabled(item.share_anonymous_usage)
    return {"share_anonymous_usage": telemetry.remote_enabled}

class SettingsMemoryToggle(BaseModel):
    keep_loaded: bool

@router.post("/settings/keep_model_loaded")
async def set_memory_mode(item: SettingsMemoryToggle):
    whisper_server.keep_model_loaded = item.keep_loaded
    model_manager.set_keep_model_loaded(whisper_server.keep_model_loaded)
    if whisper_server.keep_model_loaded:
        start_whisper_server()
    else:
        stop_whisper_server()
    return {"status": "success", "keep_loaded": whisper_server.keep_model_loaded}
