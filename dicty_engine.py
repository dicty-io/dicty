"""Dicty engine entry point.

This module only wires the FastAPI app together: logging, middleware and
routers. Endpoints live in ``routers/``; shared state and business logic live
in ``services/``.
"""
import os
import sys
import platform

if sys.platform == "win32":
    try:
        if sys.stdout and hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        if sys.stderr and hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import multiprocessing
import threading
import time
from datetime import datetime

import logging
from logging.handlers import RotatingFileHandler

from services.paths import get_log_dir

log_dir = get_log_dir()
log_path = os.path.join(log_dir, "engine.log")

_dicty_logger = logging.getLogger("dicty")
_dicty_logger.setLevel(logging.INFO)

try:
    _dicty_handler = RotatingFileHandler(log_path, maxBytes=5_000_000, backupCount=3)
    _dicty_formatter = logging.Formatter('[%(asctime)s] %(message)s', datefmt='%Y-%m-%dT%H:%M:%SZ')
    _dicty_handler.setFormatter(_dicty_formatter)
    _dicty_logger.addHandler(_dicty_handler)
    _dicty_logger.propagate = False

    if getattr(sys, 'frozen', False):
        _log_file_handle = open(log_path, "a", buffering=1)
        sys.stdout = _log_file_handle
        sys.stderr = _log_file_handle

    print(f"\n--- DICTY ENGINE STARTED AT {datetime.now()} ---")
except Exception:
    pass

if __name__ == "__main__":
    multiprocessing.freeze_support()

# Eagerly import dynamically loaded async & internal modules to prevent PyInstaller zlib race conditions
import anyio._backends._asyncio  # noqa: F401
import asyncio  # noqa: F401
import httpx  # noqa: F401
import requests  # noqa: F401
try:
    import charset_normalizer  # noqa: F401
except ImportError:
    pass
import certifi  # noqa: F401

# Eagerly import application modules to prevent runtime .pyz archive decompression errors
import prompts  # noqa: F401
import llm_service  # noqa: F401
import transcribe_service  # noqa: F401
import transcript_join  # noqa: F401
import dictation_metrics  # noqa: F401
import local_whisper
import local_llm
import meeting_dialogue  # noqa: F401
import modes_service  # noqa: F401
import style_rules  # noqa: F401
import local_corrections  # noqa: F401
import cloud_streaming  # noqa: F401
import model_manager as _model_manager_module  # noqa: F401
import agent_service  # noqa: F401
import notion_service  # noqa: F401
import queue_manager as _queue_manager_module  # noqa: F401
import auth  # noqa: F401
import app_rules  # noqa: F401
import app_rules_defaults  # noqa: F401
try:
    from tts_service import tts_service
except Exception as _tts_err:
    import traceback
    print(f"[-] Warning: tts_service could not be imported: {_tts_err}")
    traceback.print_exc()
    tts_service = None


def trace(msg):
    print(f"[TRACE] {msg}")


from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.requests import Request
from dotenv import load_dotenv

load_dotenv()

from db import init_db
from routers.auth_router import router as auth_router
from telemetry_service import telemetry
import engine_auth
from services.origins import ALLOWED_ORIGINS, is_origin_allowed

trace("Imports done")

is_dev = os.getenv("DICTY_DEV", "0").strip().lower() in ("1", "true", "yes")
app = FastAPI(
    title="DICTY Engine",
    docs_url="/docs" if is_dev else None,
    redoc_url="/redoc" if is_dev else None,
    openapi_url="/openapi.json" if is_dev else None,
)

# Initialize session token immediately
engine_auth.init_token()


@app.get("/health")
async def health_check():
    return {"ok": True}


app.add_middleware(engine_auth.EngineAuthMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def security_origin_check(request: Request, call_next):
    # Cross-origin protection: block malicious web browsers visiting external sites from querying localhost engine
    origin = request.headers.get("origin")
    sec_fetch_site = request.headers.get("sec-fetch-site")

    # If the request originated from an external browser webpage
    if origin and not is_origin_allowed(origin):
        return JSONResponse(
            status_code=403,
            content={"error": "Forbidden: Cross-origin access from external web pages is prohibited."}
        )
    if sec_fetch_site == "cross-site":
        return JSONResponse(
            status_code=403,
            content={"error": "Forbidden: Cross-site access from browser is prohibited."}
        )

    return await call_next(request)


init_db()
trace("init_db done")

# Importing the routers instantiates the shared services (recorder, model manager, stores).
from routers import (
    app_rules as app_rules_router,
    content as content_router,
    diagnostics as diagnostics_router,
    history as history_router,
    integrations as integrations_router,
    librarian as librarian_router,
    local_auth as local_auth_router,
    local_llm as local_llm_router,
    models as models_router,
    modes as modes_router,
    recording as recording_router,
    settings as settings_router,
    transcribe as transcribe_router,
    tts as tts_router,
    updates as updates_router,
)
from services import whisper_server
from services.lifecycle import free_port, _install_process_lifecycle_guards
from services.whisper_server import start_whisper_server, stop_whisper_server

# Registration order matches the original single-file engine. FastAPI matches
# routes in this order, so keep it when adding routers (e.g. auth_router owns
# POST /auth/token and must stay ahead of local_auth_router).
app.include_router(settings_router.router)
app.include_router(recording_router.router)
app.include_router(auth_router)
app.include_router(content_router.router)
app.include_router(modes_router.router)
app.include_router(diagnostics_router.router)
app.include_router(transcribe_router.router)
app.include_router(models_router.router)
app.include_router(local_llm_router.router)
app.include_router(history_router.router)
app.include_router(app_rules_router.router)
app.include_router(integrations_router.router)
app.include_router(updates_router.router)
app.include_router(librarian_router.router)
app.include_router(tts_router.router)
app.include_router(local_auth_router.router)
trace("routers included")

# Re-exports kept for callers and tests that import from dicty_engine.
from llm_service import LLMService  # noqa: E402,F401
from transcribe_service import TranscribeService  # noqa: E402,F401
from services.paths import DATA_DIR  # noqa: E402,F401
from services.pipeline import process_transcription, apply_self_correction  # noqa: E402,F401
from services.state import recorder, transcriber, model_manager, updater, git  # noqa: E402,F401
from services.stores import (  # noqa: E402,F401
    history_manager,
    vocabulary_manager,
    snippets_manager,
    app_rules_manager,
    local_pending_manager,
)


@app.on_event("startup")
def startup_event():
    telemetry.track("engine_started", {"engine_port": 8075})
    try:
        cleanup_res = history_manager.cleanup_retention()
        if cleanup_res.get("deleted_records", 0) > 0 or cleanup_res.get("scrubbed_audio", 0) > 0:
            print(f"[*] Retention cleanup on startup: {cleanup_res}")
    except Exception as e:
        print(f"[-] Retention cleanup error on startup: {e}")

    def retention_worker():
        while True:
            time.sleep(3600)  # Run hourly
            try:
                history_manager.cleanup_retention()
            except Exception:
                pass
    t = threading.Thread(target=retention_worker, daemon=True)
    t.start()

    if whisper_server.keep_model_loaded:
        start_whisper_server()

    # Pre-warm local faster-whisper model in RAM asynchronously for instant first-utterance dictation
    def _prewarm_models(target_model_id: str = None):
        try:
            from transcribe_service import prewarm_faster_whisper
            prewarm_faster_whisper(target_model_id)
        except Exception as e:
            print(f"[-] Model prewarm skipped: {e}")
        try:
            if tts_service:
                tts_service.prewarm()
        except Exception:
            pass
    threading.Thread(target=_prewarm_models, daemon=True).start()


@app.on_event("shutdown")
def shutdown_event():
    stop_whisper_server()


if __name__ == "__main__":
    try:
        free_port(8075)
        # Previous engines killed with SIGKILL (e.g. by free_port above) leave their whisper-server behind
        local_whisper.kill_all_orphans()
        local_llm.kill_all_orphans()
        _install_process_lifecycle_guards()

        def _prewarm_local_llm():
            try:
                import json
                from model_manager import SETTINGS_FILE
                if os.path.exists(SETTINGS_FILE):
                    with open(SETTINGS_FILE) as f:
                        cfg = json.load(f)
                    if cfg.get("llm_provider") == "local" and local_llm.is_installed():
                        print("[*] Pre-warming local LLM server for instant offline formatting...")
                        local_llm.start_server()
            except Exception as e:
                print(f"[!] Pre-warming local LLM skipped: {e}")

        threading.Thread(target=_prewarm_local_llm, daemon=True, name="local-llm-prewarm").start()

        trace("Starting uvicorn...")
        import uvicorn
        trace("Uvicorn imported, running app...")
        uvicorn.run(app, host="127.0.0.1", port=8075, http="h11", ws="websockets")
        trace("Uvicorn exited cleanly")
    except Exception as e:
        trace(f"FATAL EXCEPTION: {e}")
        import traceback
        with open("crash_dump.txt", "w") as f:
            f.write(traceback.format_exc())
        raise
