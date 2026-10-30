from fastapi import APIRouter
import json
import local_llm
import os
from pydantic import BaseModel
from fastapi import HTTPException
from typing import Optional

router = APIRouter()


# ==============================================================================
# OFFLINE FORMATTING ADD-ON MANAGEMENT ENDPOINTS
# ==============================================================================

@router.get("/addons/local-llm/status")
async def get_local_llm_addon_status():
    """Returns installation, running state, download progress, and disk usage for the offline LLM add-on."""
    return local_llm.get_status()


class LocalLLMInstallRequest(BaseModel):
    model_id: str = ""


@router.get("/addons/local-llm/models")
async def get_local_llm_models():
    """Returns available local models catalog with download status and active model."""
    return {
        "models": local_llm.get_available_models(),
        "active_model_id": local_llm.get_active_model_id(),
        "status": local_llm.get_status(),
    }


@router.post("/addons/local-llm/models/select")
async def select_local_llm_model(req: LocalLLMInstallRequest):
    """Switches the active local model and restarts the local runner if running."""
    if not req.model_id:
        raise HTTPException(status_code=400, detail="Missing model_id parameter.")
    ok = local_llm.switch_model(req.model_id)
    if not ok:
        raise HTTPException(status_code=400, detail=f"Model '{req.model_id}' is not downloaded yet or is invalid.")
    return local_llm.get_status()


@router.post("/addons/local-llm/models/download")
async def download_local_llm_model(req: LocalLLMInstallRequest):
    """Triggers download of a specific model from the catalog."""
    return local_llm.start_installation(model_id=req.model_id or None)


@router.delete("/addons/local-llm/models/{model_id}")
async def delete_local_llm_model(model_id: str):
    """Deletes a specific local model file from disk to reclaim storage."""
    res = local_llm.delete_model(model_id)
    if res.get("status") == "error":
        raise HTTPException(status_code=400, detail=res.get("message", "Failed to delete model."))
    return res


@router.post("/addons/local-llm/install")
async def install_local_llm_addon(req: Optional[LocalLLMInstallRequest] = None, model_id: str = ""):
    """Starts background installation of the runner and chosen local SLM model."""
    target_mid = (req.model_id if req and req.model_id else model_id) or None
    return local_llm.start_installation(model_id=target_mid)


@router.post("/addons/local-llm/cancel")
async def cancel_local_llm_addon_install():
    """Cancels any in-progress download of the offline LLM add-on."""
    local_llm.cancel_installation()
    return {"status": "cancelled"}


@router.delete("/addons/local-llm")
async def uninstall_local_llm_addon():
    """Stops the local LLM server and removes all downloaded binaries and models, freeing disk space."""
    res = local_llm.uninstall_addon()
    # If the user was using local LLM, switch back to cloud
    try:
        from model_manager import SETTINGS_FILE
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                current_settings = json.load(f)
            if current_settings.get("llm_provider") == "local":
                current_settings["llm_provider"] = "openrouter"
                if current_settings.get("llm_model") in [local_llm.DEFAULT_MODEL_ID, "qwen2.5-1.5b-instruct"]:
                    current_settings["llm_model"] = "openai/gpt-4o-mini"
                with open(SETTINGS_FILE, "w") as f:
                    json.dump(current_settings, f, indent=2)
    except Exception as e:
        print(f"[!] Warning: Failed to reset settings during addon uninstall: {e}")
    return res


@router.post("/addons/local-llm/toggle")
async def toggle_local_llm_server():
    """Starts or stops the local LLM server."""
    if not local_llm.is_installed():
        raise HTTPException(status_code=400, detail="Add-on is not installed.")
    if local_llm.is_server_running():
        local_llm.stop_server()
    else:
        local_llm.start_server()
    return local_llm.get_status()
