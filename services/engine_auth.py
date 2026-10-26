"""Local engine session token authentication (X-Dicty-Token).

Only the Dicty app and authorized local tools can communicate with the local
engine on 127.0.0.1:8075. Protects against malicious websites, DNS rebinding,
and unauthorized local processes.
"""

import atexit
import hmac
import json
import logging
import os
import secrets
import sys
import threading
import time
from typing import Dict, Optional, Set

import dicty_paths

logger = logging.getLogger("dicty.auth")

_SESSION_TOKEN: Optional[str] = None
_REGISTERED_PID: Optional[int] = None
_TOKEN_FILE_PATH: Optional[str] = None
_TOKEN_LOCK = threading.Lock()
_LOG_LOCK = threading.Lock()
_LAST_FAILURE_LOG_TIME: float = 0.0

TOKEN_FILENAME = "engine.token"
HEADER_NAME = "X-Dicty-Token"
HEADER_NAME_BYTES = b"x-dicty-token"
WS_SUBPROTOCOL = "dicty.v1"
ENV_SESSION_TOKEN = "DICTY_SESSION_TOKEN"
ENV_ALLOW_NO_TOKEN = "DICTY_ALLOW_NO_TOKEN"


def is_packaged() -> bool:
    """True when running from a PyInstaller/frozen bundle."""
    return bool(getattr(sys, "frozen", False))


def is_token_required() -> bool:
    """Token auth is enforced by default, including every packaged build.

    ``DICTY_ALLOW_NO_TOKEN=1`` is a source/development escape hatch only. It is
    intentionally ignored in frozen builds so a bundled app can never silently
    run without authentication.
    """
    if is_packaged():
        return True
    allow_no_token = os.getenv(ENV_ALLOW_NO_TOKEN, "").strip().lower()
    return allow_no_token not in ("1", "true", "yes")


def get_token_file_path() -> str:
    return os.path.join(dicty_paths.get_user_data_dir(), TOKEN_FILENAME)


def init_token(token: Optional[str] = None) -> str:
    """Initialize or rotate the session token and atomically write the token file."""
    global _SESSION_TOKEN, _REGISTERED_PID, _TOKEN_FILE_PATH
    with _TOKEN_LOCK:
        if token and token.strip():
            _SESSION_TOKEN = token.strip()
        else:
            env_token = os.getenv(ENV_SESSION_TOKEN, "").strip()
            if env_token:
                _SESSION_TOKEN = env_token
            else:
                _SESSION_TOKEN = secrets.token_urlsafe(32)

        _REGISTERED_PID = os.getpid()
        _TOKEN_FILE_PATH = get_token_file_path()

        port = 8075
        try:
            port = int(os.getenv("DICTY_PORT", "8075"))
        except ValueError:
            port = 8075

        payload = {
            "token": _SESSION_TOKEN,
            "pid": _REGISTERED_PID,
            "port": port,
        }
        data = json.dumps(payload, indent=2).encode("utf-8")

        temp_path = f"{_TOKEN_FILE_PATH}.tmp.{_REGISTERED_PID}"
        try:
            os.makedirs(os.path.dirname(_TOKEN_FILE_PATH), exist_ok=True)
            # os.open with 0o600 guarantees owner read/write only permissions
            fd = os.open(temp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            os.replace(temp_path, _TOKEN_FILE_PATH)
            try:
                os.chmod(_TOKEN_FILE_PATH, 0o600)
            except OSError:
                pass
        except Exception as e:
            logger.error(f"[Auth] Failed to write token file: {e}")
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except OSError:
                    pass

        log_auth_mode()
        return _SESSION_TOKEN


_AUTH_MODE_LOGGED = False


def log_auth_mode() -> None:
    """Log the effective auth mode once at startup without ever logging the token."""
    global _AUTH_MODE_LOGGED
    if _AUTH_MODE_LOGGED:
        return
    _AUTH_MODE_LOGGED = True
    if is_token_required():
        print("[Auth] Engine token authentication is enforced.", flush=True)
    else:
        print(
            "[Auth] WARNING: engine token authentication is DISABLED by "
            "DICTY_ALLOW_NO_TOKEN (source/dev only).",
            flush=True,
        )


def cleanup_token() -> None:
    """Remove the token file on clean shutdown if it belongs to our PID."""
    global _TOKEN_FILE_PATH, _REGISTERED_PID
    with _TOKEN_LOCK:
        target_path = _TOKEN_FILE_PATH or get_token_file_path()
        if not os.path.exists(target_path):
            return
        try:
            with open(target_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if data.get("pid") == os.getpid():
                os.remove(target_path)
        except Exception:
            pass


atexit.register(cleanup_token)


def get_token() -> str:
    """Get the current session token, initializing or loading from disk if necessary."""
    global _SESSION_TOKEN
    with _TOKEN_LOCK:
        if _SESSION_TOKEN:
            return _SESSION_TOKEN

    env_token = os.getenv(ENV_SESSION_TOKEN, "").strip()
    if env_token:
        return init_token(env_token)

    token_file = get_token_file_path()
    if os.path.isfile(token_file):
        try:
            with open(token_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                tok = data.get("token")
                if tok:
                    with _TOKEN_LOCK:
                        _SESSION_TOKEN = str(tok)
                    return _SESSION_TOKEN
        except Exception:
            pass

    return init_token()


def check(candidate_token: Optional[str]) -> bool:
    """Constant-time token validation."""
    if not candidate_token:
        return False
    expected = get_token()
    if not expected:
        return False
    return hmac.compare_digest(candidate_token.strip(), expected)


def auth_headers() -> Dict[str, str]:
    """Headers dictionary for engine's internal self-calls."""
    return {HEADER_NAME: get_token()}


def _websocket_protocol_entries(raw: str) -> list:
    return [entry.strip() for entry in (raw or "").split(",") if entry.strip()]


def websocket_subprotocol_token(headers_dict: Dict[bytes, str]) -> Optional[str]:
    """Extract a token from `Sec-WebSocket-Protocol: dicty.v1, <token>`.

    Browsers and WebViews cannot set custom headers on WebSocket upgrade
    requests, so this subprotocol is the only portable way to authenticate
    them. HTTP requests must never use this fallback.
    """
    entries = _websocket_protocol_entries(
        headers_dict.get(b"sec-websocket-protocol", "")
    )
    if len(entries) >= 2 and entries[0] == WS_SUBPROTOCOL:
        return entries[1]
    return None


def ws_accept_subprotocol(websocket) -> Optional[str]:
    """Return the subprotocol to echo when accepting a WebSocket connection."""
    entries = _websocket_protocol_entries(
        websocket.headers.get("sec-websocket-protocol", "")
    )
    return WS_SUBPROTOCOL if WS_SUBPROTOCOL in entries else None


def _maybe_log_failure(msg: str) -> None:
    """Log authentication / host verification failure at most once per minute, never logging tokens."""
    global _LAST_FAILURE_LOG_TIME
    now = time.time()
    with _LOG_LOCK:
        if now - _LAST_FAILURE_LOG_TIME >= 60.0:
            _LAST_FAILURE_LOG_TIME = now
            print(f"[Auth] {msg}", flush=True)


def get_allowed_hosts() -> Set[str]:
    port = os.getenv("DICTY_PORT", "8075").strip()
    hosts = {
        "127.0.0.1:8075",
        "localhost:8075",
        f"127.0.0.1:{port}",
        f"localhost:{port}",
        "127.0.0.1",
        "localhost",
        "[::1]:8075",
        f"[::1]:{port}",
        "[::1]",
    }
    if os.getenv("DICTY_TESTING") == "1":
        hosts.update({
            "testserver",
            "testserver:80",
            "testserver:8075",
            f"testserver:{port}",
        })
    return hosts


class EngineAuthMiddleware:
    """Pure ASGI middleware enforcing Host header validation and X-Dicty-Token.

    Handles both 'http' and 'websocket' scopes.
    Exempt endpoints:
    - HTTP OPTIONS (CORS preflight)
    - GET /health (returns {"ok": true})
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        scope_type = scope.get("type")
        if scope_type not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return

        method = scope.get("method", "").upper() if scope_type == "http" else "WEBSOCKET"
        path = scope.get("path", "")

        # 1. Exemptions: OPTIONS and GET /health
        if scope_type == "http" and method == "OPTIONS":
            await self.app(scope, receive, send)
            return

        if scope_type == "http" and method == "GET" and path == "/health":
            await self.app(scope, receive, send)
            return

        # 2. Extract headers
        headers_dict: Dict[bytes, str] = {}
        for k, v in scope.get("headers", []):
            headers_dict[k.lower()] = v.decode("latin1", errors="replace").strip()

        # 3. Host validation (blocks DNS rebinding)
        host_header = headers_dict.get(b"host", "")
        allowed_hosts = get_allowed_hosts()
        is_valid_host = host_header in allowed_hosts

        require_enforcement = is_token_required()

        if not is_valid_host:
            if require_enforcement:
                _maybe_log_failure(f"Forbidden: invalid Host header '{host_header}' on {path}")
                if scope_type == "http":
                    body = b'{"error": "forbidden", "detail": "Invalid Host header"}'
                    await send({
                        "type": "http.response.start",
                        "status": 403,
                        "headers": [
                            (b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode("ascii")),
                        ],
                    })
                    await send({
                        "type": "http.response.body",
                        "body": body,
                        "more_body": False,
                    })
                    return
                else:
                    await send({
                        "type": "websocket.close",
                        "code": 4403,
                        "reason": "forbidden_host",
                    })
                    return
            else:
                _maybe_log_failure(f"Dry-run: request to {path} would be rejected: invalid Host header '{host_header}'")

        # 4. Token validation
        candidate_token = headers_dict.get(HEADER_NAME_BYTES)
        if scope_type == "websocket" and not candidate_token:
            candidate_token = websocket_subprotocol_token(headers_dict)
        is_valid_token = check(candidate_token)

        if not is_valid_token:
            if require_enforcement:
                _maybe_log_failure(f"Unauthorized: missing or invalid X-Dicty-Token on {path}")
                if scope_type == "http":
                    body = b'{"error": "unauthorized"}'
                    await send({
                        "type": "http.response.start",
                        "status": 401,
                        "headers": [
                            (b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode("ascii")),
                        ],
                    })
                    await send({
                        "type": "http.response.body",
                        "body": body,
                        "more_body": False,
                    })
                    return
                else:
                    await send({
                        "type": "websocket.close",
                        "code": 4401,
                        "reason": "unauthorized",
                    })
                    return
            else:
                _maybe_log_failure(f"Dry-run: request to {path} would be rejected: missing or invalid X-Dicty-Token")

        # 5. Passed validation or dry-run
        await self.app(scope, receive, send)
