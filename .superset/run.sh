#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Ensure environment is initialized
if [ ! -f .venv/bin/python3 ] || [ ! -f bin/whisper.cpp/build/bin/whisper-server ]; then
    echo "[*] Environment not initialized. Running setup first..."
    ./.superset/setup.sh
fi

if [ "$1" = "--backend-only" ] || [ "$DICTY_RUN_BACKEND_ONLY" = "1" ]; then
    echo "[*] Starting Dicty Python backend engine (:8075)..."
    exec .venv/bin/python3 dicty_engine.py
fi

echo "[*] Launching Dicty in development mode..."
exec ./scripts/run_client.sh "$@"
