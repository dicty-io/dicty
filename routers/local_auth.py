from fastapi import APIRouter
import time
from typing import Any, Dict
from fastapi import Request
import logging

_dicty_logger = logging.getLogger("dicty")

router = APIRouter()


# =========================================================================
# OAUTH LOCAL LOOPBACK HANDSHAKE
# =========================================================================
_pending_oauth_tokens: Dict[str, Any] = {}

@router.post("/auth/token")
async def receive_local_auth_token(req: Request):
    """
    Receives JWT OAuth token from the browser (Google OAuth completion page)
    or client via loopback HTTP to bypass browser protocol prompts.
    """
    try:
        data = await req.json()
        token = data.get("token", "").strip() if isinstance(data, dict) else ""
        if token:
            _pending_oauth_tokens["latest"] = {
                "token": token,
                "timestamp": time.time()
            }
            _dicty_logger.info("[*] Received OAuth token via local loopback endpoint.")
            return {"status": "ok", "message": "Token received"}
        return {"status": "error", "message": "Empty token"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@router.get("/auth/pending_token")
def get_pending_auth_token():
    """
    Returns and consumes any recently received OAuth token (within last 120s).
    Used by Swift UI client to auto-complete Google Sign-In even if browser
    blocks dicty:// deep link.
    """
    latest = _pending_oauth_tokens.get("latest")
    if latest and (time.time() - latest.get("timestamp", 0) < 120):
        _pending_oauth_tokens.pop("latest", None)
        return {"token": latest["token"]}
    return {"token": None}
