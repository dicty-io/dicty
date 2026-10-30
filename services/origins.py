from typing import Optional

ALLOWED_ORIGINS = [
    "http://localhost:1420",
    "http://127.0.0.1:1420",
    "tauri://localhost",
    # Tauri v2 on Windows serves the WebView2 app from the custom protocol
    # `http://tauri.localhost` by default (useHttpsScheme is not enabled in
    # tauri.conf.json). Windows therefore sends this exact Origin on engine
    # fetches and WebSocket upgrades.
    "http://tauri.localhost",
    "https://tauri.localhost",
    "dicty://localhost",
]

def is_origin_allowed(origin: Optional[str]) -> bool:
    if not origin:
        return True
    return origin in ALLOWED_ORIGINS
