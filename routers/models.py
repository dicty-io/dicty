from fastapi import APIRouter
import httpx
import os
import platform
import subprocess
import time
from fastapi import HTTPException
from model_manager import ModelManager
from typing import Optional
from dotenv import load_dotenv
from services.state import model_manager
from services.whisper_server import start_whisper_server, stop_whisper_server
from telemetry_service import telemetry
from services import whisper_server

router = APIRouter()


@router.get("/models")
async def get_models():
    try:
        models = model_manager.get_available_models()
        for m in models:
            m["is_downloaded"] = model_manager.is_model_downloaded(m["id"])
            m["quantization"] = model_manager.get_model_quality(m["id"]) if m.get("is_downloaded") else "q5_0"
            if m.get("is_downloaded") and not m.get("is_cloud"):
                # Show the real on-disk size of the installed file, not the catalog estimate
                p = model_manager.get_model_file_path(m["id"])
                if p:
                    mb = os.path.getsize(p) / (1024 * 1024)
                    m["size"] = f"{mb:.0f} MB" if mb < 1000 else f"{mb/1024:.1f} GB"
        return {"models": models}
    except Exception as e:
        import traceback
        with open("endpoint_crash.txt", "w") as f:
            f.write(traceback.format_exc())
        raise e

@router.get("/models/active")
async def get_active_model():
    return {
        "active_model": model_manager.get_active_model(),
        "active_text_model": model_manager.get_active_text_model(),
    }

@router.get("/models/active_text")
async def get_active_text_model():
    return {"active_text_model": model_manager.get_active_text_model()}

@router.post("/models/active_text/{model_id:path}")
async def set_active_text_model(model_id: str):
    manager = ModelManager()
    if not manager.is_model_downloaded(model_id):
        raise HTTPException(
            status_code=400,
            detail=f"Model '{model_id}' is not installed. Please download it before setting as active."
        )
    manager.set_active_text_model(model_id)
    try:
        import local_llm
        if local_llm.is_server_running():
            local_llm.switch_model(model_id)
    except Exception as e:
        print(f"[*] Note switching local_llm: {e}")
    return {"status": "success", "active_text_model": model_id}

@router.post("/models/active/{model_id:path}")
async def set_active_model(model_id: str):
    manager = ModelManager()
    if not manager.is_model_downloaded(model_id):
        raise HTTPException(
            status_code=400,
            detail=f"Model '{model_id}' is not installed. Please download it before setting as active."
        )
    manager.set_active_model(model_id)
    load_dotenv(override=True)
    if whisper_server.keep_model_loaded:
        stop_whisper_server()
        import time
        time.sleep(1)
        start_whisper_server()
    telemetry.track("model_switched", {"model_id": model_id})

    # Trigger async prewarm and CUDA warmup in background for instant first utterance
    try:
        from transcribe_service import prewarm_faster_whisper
        import threading
        threading.Thread(target=prewarm_faster_whisper, args=(model_id,), daemon=True).start()
    except Exception as err:
        print(f"[*] Prewarm dispatch note: {err}")

    return {"status": "success", "active_model": model_id}

@router.post("/models/prewarm")
async def api_prewarm_model(model_id: Optional[str] = None):
    try:
        from transcribe_service import prewarm_faster_whisper
        import threading
        threading.Thread(target=prewarm_faster_whisper, args=(model_id,), daemon=True).start()
    except Exception as err:
        print(f"[*] Prewarm dispatch note: {err}")
    return {"status": "prewarming_started", "model_id": model_id}

_openrouter_models_cache = {}  # key -> {"timestamp": float, "models": list}

@router.get("/models/openrouter")
async def get_openrouter_models(force: bool = False, sort: Optional[str] = None):
    global _openrouter_models_cache
    now = time.time()
    cache_key = sort or "most-popular"
    
    # Cache OpenRouter catalog for 24 hours (86400 seconds) unless force=True
    if not force and cache_key in _openrouter_models_cache and (now - _openrouter_models_cache[cache_key]["timestamp"] < 86400):
        return {"models": _openrouter_models_cache[cache_key]["models"]}
        
    api_sort = sort or "most-popular"
    reverse_needed = False
    if api_sort == "throughput-low-to-high":
        api_sort = "throughput-high-to-low"
        reverse_needed = True

    valid_openrouter_sorts = {
        "most-popular",
        "newest",
        "top-weekly",
        "pricing-low-to-high",
        "pricing-high-to-low",
        "context-high-to-low",
        "throughput-high-to-low",
        "latency-low-to-high"
    }
    
    url = "https://openrouter.ai/api/v1/models"
    if api_sort in valid_openrouter_sorts:
        url += f"?sort={api_sort}"

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers={"User-Agent": "Dicty/1.0"})
            if resp.status_code == 200:
                data = resp.json()
                raw_models = data.get("data", [])
                formatted = []
                for m in raw_models:
                    mid = m.get("id", "")
                    if not mid or any(x in mid for x in [":floor", ":extended"]):
                        continue
                    name = m.get("name", mid)
                    desc = m.get("description", "")
                    pricing = m.get("pricing", {})
                    prompt_p = float(pricing.get("prompt", 0) or 0) * 1_000_000
                    compl_p = float(pricing.get("completion", 0) or 0) * 1_000_000
                    ctx_len = m.get("context_length", 0)
                    formatted.append({
                        "id": mid,
                        "name": name,
                        "description": desc,
                        "context_length": ctx_len,
                        "prompt_price_per_m": prompt_p,
                        "completion_price_per_m": compl_p
                    })
                if reverse_needed:
                    formatted.reverse()
                _openrouter_models_cache[cache_key] = {"timestamp": now, "models": formatted}
                return {"models": formatted}
    except Exception as e:
        print(f"[!] Error fetching OpenRouter models (sort={sort}): {e}")
        if cache_key in _openrouter_models_cache:
            return {"models": _openrouter_models_cache[cache_key]["models"]}
        for k, v in _openrouter_models_cache.items():
            if v.get("models"):
                return {"models": v["models"]}
    return {"models": []}

@router.delete("/models/{model_id:path}")
async def delete_model(model_id: str):
    was_active = (model_id == model_manager.get_active_model())
    if was_active:
        stop_whisper_server()
        import time
        time.sleep(0.5)

    success = model_manager.delete_model(model_id)
    if success:
        telemetry.track("model_deleted", {"model_id": model_id})
        new_active = model_manager.get_active_model()
        if was_active and whisper_server.keep_model_loaded and model_manager.is_model_downloaded(new_active):
            load_dotenv(override=True)
            import time
            time.sleep(0.5)
            start_whisper_server()
        return {"status": "success", "active_model": new_active}
    else:
        raise HTTPException(status_code=400, detail="Cannot delete model or model not found")

@router.post("/models/download/cancel")
async def cancel_download_model(model_id: str):
    model_manager.cancel_download(model_id)
    return {"status": "cancelled", "model_id": model_id}

@router.post("/models/download/{model_id}")
async def download_model(model_id: str, quality: str = "q5_0"):
    if model_manager.is_model_downloaded(model_id):
        # Don't overwrite the recorded quality: the file on disk didn't change
        model_manager.download_progress[model_id] = 100.0
        return {"status": "already_downloaded", "model_id": model_id, "quality": model_manager.get_model_quality(model_id)}
    model_manager.set_model_quality(model_id, quality)
        
    telemetry.track("model_download_started", {"model_id": model_id, "quality": quality})

    def _on_progress(m_id, pct):
        print(f"[{m_id}] Download ({quality}): {pct:.2f}%")
        
    def _on_complete(m_id, success):
        print(f"[{m_id}] Download Complete: {success}")
        telemetry.track("model_download_completed", {"model_id": m_id, "quality": quality, "success": success})
        if success and whisper_server.keep_model_loaded:
            start_whisper_server()
        
    model_manager.start_download(model_id, quality, _on_progress, _on_complete)
    return {"status": "download_started", "model_id": model_id, "quality": quality}

@router.get("/models/download/progress")
async def get_download_progress():
    return {"progress": model_manager.download_progress}

@router.post("/models/open")
async def open_models_folder():
    from model_manager import MODELS_DIR
    path = os.path.normpath(os.path.abspath(MODELS_DIR))
    os.makedirs(path, exist_ok=True)
    try:
        if platform.system() == "Darwin":
            subprocess.Popen(["open", path])
        elif platform.system() == "Windows":
            subprocess.Popen(["explorer.exe", path])
        else:
            subprocess.Popen(["xdg-open", path])
    except Exception as e:
        print(f"Failed to open models folder via subprocess: {e}")
        try:
            os.startfile(path)
        except Exception:
            pass
    return {"status": "success", "path": path}
