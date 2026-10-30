from fastapi import APIRouter
import asyncio
import modes_service
from typing import Any, Dict
from fastapi import Body, HTTPException
from services.mode_requests import _modes_call
from services.state import model_manager, recorder
from telemetry_service import telemetry

router = APIRouter()


@router.get("/modes")
async def get_modes():
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.get_document)


@router.put("/modes")
async def replace_modes(payload: Any = Body(...)):
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.replace_modes, payload)


@router.post("/modes")
async def create_mode(payload: Dict[str, Any] = Body(...)):
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.create_mode, payload)


@router.get("/modes/settings")
async def get_mode_settings():
    document = await asyncio.to_thread(_modes_call, modes_service.modes_service.get_document)
    return {
        "ai_location": document.get("ai_location"),
        "automatic_app_rules": document.get("automatic_app_rules"),
        "active_mode_id": document.get("active_mode_id"),
    }


@router.put("/modes/settings")
async def set_mode_settings(payload: Dict[str, Any] = Body(...)):
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.set_settings, payload)


@router.get("/modes/app_rules")
async def get_app_rules():
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.get_app_rules)


@router.put("/modes/app_rules")
async def replace_app_rules(payload: Dict[str, Any] = Body(...)):
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.replace_app_rules, payload)


@router.post("/modes/migrate")
async def migrate_modes(
    payload: Any = Body(...),
    force: bool = False,
    source: str = "payload",
):
    config = payload
    if isinstance(payload, dict) and "config" in payload and not any(
        key in payload
        for key in ("profiles", "prompts", "activeMode", "active_mode", "modes", "dictationFormatStyle")
    ):
        config = payload["config"]
        force = bool(payload.get("force", force))
        source = str(payload.get("source") or source)
    return await asyncio.to_thread(
        _modes_call,
        modes_service.modes_service.migrate_config,
        config,
        force=force,
        source=source,
    )


@router.get("/modes/migration")
async def get_mode_migration():
    document = await asyncio.to_thread(_modes_call, modes_service.modes_service.get_document)
    return document.get("migration") or {}


@router.get("/capabilities")
async def get_capabilities():
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.get_capabilities)


@router.post("/capabilities/fix")
async def fix_capability(payload: Dict[str, Any] = Body(...)):
    """Act on a mode's ``missing`` value: start the model download it needs."""
    mode_id = str(payload.get("mode_id") or "").strip()
    if not mode_id:
        raise HTTPException(status_code=400, detail="mode_id is required")
    target = await asyncio.to_thread(
        _modes_call, modes_service.modes_service.download_target_for_mode, mode_id
    )
    if not target:
        return {"status": "nothing_to_do", "mode_id": mode_id}
    model_id = target["model_id"]
    available = await asyncio.to_thread(
        lambda: {m.get("id") for m in model_manager.get_available_models()}
    )
    if model_id not in available:
        raise HTTPException(status_code=404, detail=f"Model '{model_id}' is not in the catalog")
    if model_manager.is_model_downloaded(model_id):
        return {"status": "already_downloaded", "mode_id": mode_id, "model_id": model_id}
    telemetry.track("model_download_started", {"model_id": model_id, "mode_id": mode_id, "reason": "capability"})
    model_manager.start_download(model_id, "q5_0", lambda m, p: None, lambda m, ok: None)
    return {
        "status": "download_started",
        "mode_id": mode_id,
        "model_id": model_id,
        "size_mb": target.get("size_mb"),
    }


@router.get("/modes/{mode_id}")
async def get_mode(mode_id: str):
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.get_mode, mode_id)


@router.put("/modes/{mode_id}")
async def update_mode(mode_id: str, payload: Dict[str, Any] = Body(...)):
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.update_mode, mode_id, payload)


@router.delete("/modes/{mode_id}")
async def delete_mode(mode_id: str):
    return await asyncio.to_thread(_modes_call, modes_service.modes_service.delete_mode, mode_id)


@router.get("/devices")
async def get_devices():
    return {"devices": recorder.get_input_devices()}
