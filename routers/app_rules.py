from fastapi import APIRouter
from typing import Any, Dict, Optional
from pydantic import BaseModel
from fastapi import HTTPException
from services.stores import app_rules_manager, history_manager

router = APIRouter()


# -------------------------------------------------------------------------
# App Rules Endpoints
# -------------------------------------------------------------------------

class AppRulesSettingsUpdate(BaseModel):
    enabled: Optional[bool] = None
    override_scope: Optional[str] = None

class AppRuleCreate(BaseModel):
    match: Optional[Dict[str, Any]] = None
    app_id: Optional[str] = None
    app_name: Optional[str] = None
    mode_id: str
    display_name: Optional[str] = ""
    enabled: Optional[bool] = True

class AppRuleUpdate(BaseModel):
    mode_id: Optional[str] = None
    enabled: Optional[bool] = None
    display_name: Optional[str] = None
    suppress_suggestion: Optional[bool] = None

@router.get("/app-rules")
async def get_app_rules():
    return {
        "settings": app_rules_manager.get_settings(),
        "rules": app_rules_manager.effective_rules()
    }

@router.put("/app-rules/settings")
async def update_app_rules_settings(req: AppRulesSettingsUpdate):
    try:
        updated = app_rules_manager.update_settings(enabled=req.enabled, override_scope=req.override_scope)
        return {
            "status": "success",
            "settings": updated,
            "rules": app_rules_manager.effective_rules()
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/app-rules")
async def add_app_rule(req: AppRuleCreate):
    try:
        match_dict = req.match
        if not match_dict:
            if req.app_id:
                match_dict = {"type": "app", "value": req.app_id}
            else:
                raise HTTPException(status_code=400, detail="Missing match object or app_id")

        disp_name = req.display_name or req.app_name or ""
        rule = app_rules_manager.add_rule(
            match=match_dict,
            mode_id=req.mode_id,
            display_name=disp_name,
            enabled=True if req.enabled is None else bool(req.enabled)
        )
        res = dict(rule)
        res["status"] = "success"
        res["rule"] = rule
        return res
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.patch("/app-rules/{rule_id}")
async def patch_app_rule(rule_id: str, req: AppRuleUpdate):
    try:
        updated = app_rules_manager.update_rule(
            rule_id=rule_id,
            mode_id=req.mode_id,
            enabled=req.enabled,
            display_name=req.display_name,
            suppress_suggestion=req.suppress_suggestion
        )
        if not updated:
            raise HTTPException(status_code=404, detail="Rule not found")
        res = dict(updated)
        res["status"] = "success"
        res["rule"] = updated
        return res
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.delete("/app-rules/{rule_id}")
async def delete_app_rule(rule_id: str):
    success = app_rules_manager.delete_rule(rule_id)
    if not success:
        raise HTTPException(status_code=404, detail="Rule not found")
    return {"status": "success", "deleted": rule_id}

@router.post("/app-rules/reset")
async def reset_app_rules():
    app_rules_manager.reset_all()
    return {
        "status": "success",
        "message": "All app rules restored to defaults",
        "settings": app_rules_manager.get_settings(),
        "rules": app_rules_manager.effective_rules()
    }

@router.get("/app-rules/resolve")
async def resolve_app_rule(
    app_id: str = "",
    domain: str = "",
    selected_mode_id: str = "dictation",
    recording_override_mode_id: Optional[str] = None,
    manual_override_active: bool = False
):
    mode_id, reason = app_rules_manager.resolve_mode(
        app_id=app_id,
        domain=domain,
        selected_mode_id=selected_mode_id,
        recording_override_mode_id=recording_override_mode_id,
        manual_override_active=manual_override_active
    )
    return {"mode_id": mode_id, "reason": reason}

@router.get("/stats/app-rules")
async def get_app_rule_stats():
    history_records = history_manager.get_all()
    stats = app_rules_manager.compute_stats(history_records)
    return {"stats": stats}

class AppRuleAcceptSuggestionPayload(BaseModel):
    app_id: str
    mode_id: str
    display_name: Optional[str] = ""

class AppRuleSuppressSuggestionPayload(BaseModel):
    app_id: str
    display_name: Optional[str] = ""

@router.get("/app-rules/suggestion")
async def get_app_rule_suggestion(app_id: str = "", app_name: str = ""):
    history_records = history_manager.get_all()
    suggestion = app_rules_manager.check_suggestion(history_records, app_id, app_name)
    return {"suggestion": suggestion}

@router.post("/app-rules/accept-suggestion")
async def accept_app_rule_suggestion(payload: AppRuleAcceptSuggestionPayload):
    try:
        rule = app_rules_manager.accept_suggestion(
            app_id=payload.app_id,
            mode_id=payload.mode_id,
            display_name=payload.display_name,
        )
        return {"status": "success", "rule": rule}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/app-rules/suppress-suggestion")
async def suppress_app_rule_suggestion(payload: AppRuleSuppressSuggestionPayload):
    try:
        res = app_rules_manager.suppress_suggestion(
            app_id=payload.app_id,
            display_name=payload.display_name,
        )
        return {"status": "success", "result": res}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
