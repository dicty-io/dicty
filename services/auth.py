import os
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any
from passlib.context import CryptContext
from jose import JWTError, jwt

logger = logging.getLogger("dicty.auth")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

import secrets

from dicty_paths import get_user_data_dir

def _get_or_create_secret_key() -> str:
    env_secret = os.getenv("SECRET_KEY")
    if env_secret and env_secret.strip():
        return env_secret.strip()
    
    secret_file = os.path.join(get_user_data_dir(), ".engine_jwt_secret")
    if os.path.exists(secret_file):
        try:
            with open(secret_file, "r", encoding="utf-8") as f:
                key = f.read().strip()
                if len(key) >= 32:
                    return key
        except Exception:
            pass
            
    new_key = secrets.token_hex(32)
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        mode = 0o600
        fd = os.open(secret_file, flags, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_key)
    except Exception as e:
        logger.warning(f"Could not persist secret key to {secret_file}: {e}")
    return new_key

SECRET_KEY = _get_or_create_secret_key()
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30

SERVICE_NAME = "dicty_engine"
TOKEN_KEY = "jwt_token"
META_FILE = os.path.join(get_user_data_dir(), "auth_meta.json")


def _write_secure_meta(meta: dict) -> bool:
    """Persist session metadata atomically with POSIX 0o600 owner-only permissions."""
    try:
        data = json.dumps(meta, indent=2).encode("utf-8")
        temp_path = f"{META_FILE}.tmp.{os.getpid()}"
        os.makedirs(os.path.dirname(META_FILE), exist_ok=True)
        fd = os.open(temp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(temp_path, META_FILE)
        try:
            os.chmod(META_FILE, 0o600)
        except OSError:
            pass
        return True
    except Exception as e:
        logger.error(f"Failed to write {META_FILE}: {e}")
        return False


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> Optional[dict]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError as e:
        logger.warning(f"JWT signature verification failed: {e}")
        return None

class SecureAuthManager:
    @staticmethod
    def save_session(token: str, email: str, is_pro: bool, compute_balance: int = 0, subscription_tier: str = 'free'):
        meta = {
            "token": token,
            "email": email,
            "is_pro": is_pro,
            "compute_balance": compute_balance,
            "subscription_tier": subscription_tier,
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
        _write_secure_meta(meta)

    @staticmethod
    def get_jwt_token() -> Optional[str]:
        if not os.path.exists(META_FILE):
            return None
        try:
            with open(META_FILE, "r", encoding="utf-8") as f:
                meta = json.load(f)
                return meta.get("token")
        except Exception as e:
            logger.warning(f"Failed to read token from {META_FILE}: {e}")
            return None

    @staticmethod
    def get_session() -> Dict[str, Any]:
        meta = {}
        if os.path.exists(META_FILE):
            try:
                with open(META_FILE, "r", encoding="utf-8") as f:
                    meta = json.load(f)
            except Exception as e:
                logger.error(f"Failed to read {META_FILE}: {e}")

        token = meta.get("token")
        if not token or not meta.get("email"):
            return {
                "logged_in": False,
                "email": None,
                "is_pro": False,
                "compute_balance": 0,
                "subscription_tier": "free",
                "offline_mode": False
            }

        payload = decode_access_token(token)
        if not payload:
            SecureAuthManager.clear_session()
            return {
                "logged_in": False,
                "email": None,
                "is_pro": False,
                "compute_balance": 0,
                "subscription_tier": "free",
                "offline_mode": False
            }

        return {
            "logged_in": True,
            "email": meta.get("email"),
            "is_pro": meta.get("is_pro", False),
            "compute_balance": meta.get("compute_balance", 0),
            "subscription_tier": meta.get("subscription_tier", "free"),
            "offline_mode": False
        }

    @staticmethod
    def deduct_balance(amount: int):
        if amount <= 0:
            return
        
        meta = {}
        if os.path.exists(META_FILE):
            try:
                with open(META_FILE, "r", encoding="utf-8") as f:
                    meta = json.load(f)
            except Exception as e:
                logger.error(f"Failed to read {META_FILE}: {e}")
                return
                
        if "compute_balance" in meta:
            meta["compute_balance"] = max(0, meta["compute_balance"] - amount)
            meta["updated_at"] = datetime.now(timezone.utc).isoformat()
            _write_secure_meta(meta)

    @staticmethod
    def clear_session():
        if os.path.exists(META_FILE):
            try:
                os.remove(META_FILE)
            except Exception as e:
                logger.warning(f"Failed to remove {META_FILE}: {e}")
