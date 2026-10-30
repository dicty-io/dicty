from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
from fastapi import Query
from services.state import updater

router = APIRouter()


ALLOWED_UPDATE_REPOS = {
    "dicty-io/dicty",
    "vkazmin1/dicty",
}


@router.get("/update/check")
async def update_check(
    current_version: str = "1.0.0",
    repo: Optional[str] = None,
    token: Optional[str] = None
):
    if repo:
        repo_clean = repo.strip().lower()
        if repo_clean not in ALLOWED_UPDATE_REPOS:
            raise HTTPException(status_code=400, detail="Invalid or unauthorized update repository")
    return updater.check_for_updates(current_version, repo=repo, token=token)

@router.get("/update/progress")
async def update_progress():
    is_alive = bool(updater._update_thread and updater._update_thread.is_alive()) if hasattr(updater, "_update_thread") else False
    return {"progress": updater.download_progress, "is_updating": updater.is_updating or is_alive, "error": updater.last_error}

class ApplyUpdateRequest(BaseModel):
    download_url: Optional[str] = None
    asset_name: Optional[str] = None

@router.post("/update/apply")
async def update_apply(
    download_url: Optional[str] = Query(None),
    asset_name: Optional[str] = Query(None),
    req: Optional[ApplyUpdateRequest] = None
):
    url = download_url or (req.download_url if req else None)
    name = asset_name or (req.asset_name if req else None)
    
    if not url or not name:
        return {"status": "error", "success": False, "error": "Missing download_url or asset_name"}
        
    try:
        success = updater.apply_update(url, name)
        if success:
            return {"status": "success", "success": True, "message": "Update triggered and downloading in background."}
        else:
            return {"status": "error", "success": False, "error": updater.last_error or "Failed to trigger update."}
    except Exception as e:
        print(f"[!] Update execution failed: {e}")
        return {"status": "error", "success": False, "error": "Failed to apply update"}
