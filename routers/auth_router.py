import asyncio
import json
import logging
import os
import urllib.error
import urllib.request
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from db import get_db, DB_AVAILABLE
from models import User
from auth import (
    verify_password,
    get_password_hash,
    create_access_token,
    decode_access_token,
    SecureAuthManager
)

logger = logging.getLogger("dicty.auth_router")

router = APIRouter(prefix="/auth", tags=["auth"])

class UserRegister(BaseModel):
    email: EmailStr
    password: str

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class MockGoogleLogin(BaseModel):
    email: EmailStr
    google_id_token: Optional[str] = "mock_token"

class AuthResponse(BaseModel):
    token: str
    email: str
    is_pro: bool
    compute_balance: int = 0
    subscription_tier: str = "free"
    planExpiresAt: Optional[str] = None

class StatusResponse(BaseModel):
    logged_in: bool
    email: Optional[str] = None
    is_pro: bool
    compute_balance: int = 0
    subscription_tier: str = "free"
    offline_mode: bool

CLOUD_URL = os.getenv("DICTY_CLOUD_URL", "https://dicty-backend.dicty-backend.workers.dev").rstrip("/")


def _cloud_auth_request(path: str, email: str, password: str):
    """POST credentials to the cloud backend. Returns (status_code, json_body)."""
    req = urllib.request.Request(
        f"{CLOUD_URL}{path}",
        data=json.dumps({"email": email, "password": password}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "DictyClient/1.0"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode() or "{}")
        except Exception:
            body = {}
        return e.code, body


async def _proxy_credentials_auth(path: str, email: str, password: str) -> AuthResponse:
    # Email/password auth is handled by the cloud backend (it owns the database).
    try:
        code, body = await asyncio.to_thread(_cloud_auth_request, path, email, password)
    except Exception as e:
        logger.warning(f"Cloud auth {path} unreachable: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Cannot reach Dicty Cloud. Check your internet connection and try again.",
        )

    if code != 200:
        detail = body.get("detail") or body.get("error") or f"Authentication failed (status {code})"
        raise HTTPException(status_code=code, detail=detail)

    res = AuthResponse(
        token=body["token"],
        email=body["email"],
        is_pro=bool(body.get("is_pro", False)),
        compute_balance=body.get("compute_balance") or 0,
        subscription_tier=body.get("subscription_tier") or "free",
        planExpiresAt=body.get("planExpiresAt"),
    )
    SecureAuthManager.save_session(res.token, res.email, res.is_pro, res.compute_balance, res.subscription_tier)
    return res


@router.post("/register", response_model=AuthResponse)
async def register(user_in: UserRegister):
    return await _proxy_credentials_auth("/auth/register", user_in.email, user_in.password)


@router.post("/login", response_model=AuthResponse)
async def login(user_in: UserLogin):
    return await _proxy_credentials_auth("/auth/login", user_in.email, user_in.password)

@router.post("/google/mock", response_model=AuthResponse)
async def mock_google_login(user_in: MockGoogleLogin, db: Session = Depends(get_db)):
    import os
    if os.getenv("DICTY_ENABLE_MOCK_AUTH", "0") != "1":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mock authentication endpoint is disabled."
        )
    email = user_in.email
    is_pro = True  # Default Pro to true for mock testing

    compute_balance = 0
    subscription_tier = "free"

    if DB_AVAILABLE and db is not None:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            user = User(email=email, is_pro=is_pro)
            db.add(user)
            db.commit()
            db.refresh(user)
        else:
            is_pro = user.is_pro
            compute_balance = user.compute_balance
            subscription_tier = user.subscription_tier

    token = create_access_token({"sub": email, "provider": "google_mock"})
    SecureAuthManager.save_session(token, email, is_pro, compute_balance, subscription_tier)

    return AuthResponse(token=token, email=email, is_pro=is_pro, compute_balance=compute_balance, subscription_tier=subscription_tier)

class TokenSubmit(BaseModel):
    token: str

@router.post("/token")
async def submit_token(data: TokenSubmit):
    token = data.token.strip().replace('"', '')
    if not token:
        raise HTTPException(status_code=400, detail="Token cannot be empty")

    decoded = None
    try:
        decoded = decode_access_token(token)
    except Exception as e:
        logger.warning(f"Signature validation failed for token: {e}")

    cloud_user = None
    try:
        import urllib.request
        import json
        req = urllib.request.Request(
            "https://dicty-backend.dicty-backend.workers.dev/auth/me",
            headers={
                "Authorization": f"Bearer {token}",
                "User-Agent": "DictyClient/1.0"
            }
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                body = json.loads(response.read().decode())
                cloud_user = body.get("user")
    except Exception as e:
        logger.warning(f"Cloud /auth/me proxy error: {e}")

    if not cloud_user and not decoded:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token: signature verification failed")

    email = None
    if cloud_user:
        email = cloud_user.get("email")
    if not email and decoded:
        raw_email = decoded.get("email") or decoded.get("sub")
        if raw_email and "@" in str(raw_email):
            email = str(raw_email)

    if not email:
        raise HTTPException(status_code=400, detail="Invalid token: unable to determine user email")

    is_pro = False
    compute_balance = 0
    subscription_tier = "free"
    plan_expires_at = None

    if cloud_user:
        is_pro = cloud_user.get("isPro", cloud_user.get("is_pro", False))
        compute_balance = cloud_user.get("computeBalance", cloud_user.get("compute_balance", 0))
        subscription_tier = cloud_user.get("subscriptionTier", cloud_user.get("subscription_tier", "free"))
        plan_expires_at = cloud_user.get("planExpiresAt", cloud_user.get("plan_expires_at"))
    elif decoded:
        is_pro = decoded.get("isPro", decoded.get("is_pro", False))
        compute_balance = decoded.get("computeBalance", decoded.get("compute_balance", 0))
        subscription_tier = decoded.get("subscriptionTier", decoded.get("subscription_tier", "free"))
        plan_expires_at = decoded.get("planExpiresAt", decoded.get("plan_expires_at"))

    SecureAuthManager.save_session(token, email, is_pro, compute_balance, subscription_tier)
    try:
        from routers.local_auth import set_pending_oauth_token
        set_pending_oauth_token(token)
    except Exception:
        pass

    return {
        "token": token,
        "email": email,
        "is_pro": is_pro,
        "compute_balance": compute_balance,
        "subscription_tier": subscription_tier,
        "plan_expires_at": plan_expires_at
    }

@router.post("/logout")
async def logout():
    SecureAuthManager.clear_session()
    return {"message": "Logged out successfully"}

@router.get("/status")
async def get_status():
    try:
        session = SecureAuthManager.get_session()
        if not DB_AVAILABLE:
            session["offline_mode"] = True
        return StatusResponse(**session)
    except Exception as e:
        logger.error(f"Error in /auth/status: {e}")
        return {"logged_in": False, "email": None, "is_pro": False, "compute_balance": 0, "subscription_tier": "free", "offline_mode": True, "error": str(e)}
