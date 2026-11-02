#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# 1. Isolate development backend data to the workspace unless explicitly overridden
export DICTY_DATA_DIR="${DICTY_DATA_DIR:-$PROJECT_DIR/.dicty_data}"
mkdir -p "$DICTY_DATA_DIR"

# 2. Record this dev launcher process PID for workspace teardown
echo "$$" > "$PROJECT_DIR/.superset/run.pid"

# 3. Handle backend-only mode
if [ "$1" = "--backend-only" ] || [ "$DICTY_RUN_BACKEND_ONLY" = "1" ]; then
    if [ ! -f .venv/bin/python3 ] || [ ! -f bin/whisper.cpp/build/bin/whisper-server ]; then
        echo "[*] Backend environment not initialized. Running backend setup first..."
        ./.superset/setup.sh --backend-only
    fi

    echo "[*] Starting Dicty Python backend engine (:8075)..."
    exec .venv/bin/python3 dicty_engine.py
fi

# 4. Handle standard development mode (Swift client + live source engine)
if [ ! -f .venv/bin/python3 ] || [ ! -f bin/whisper.cpp/build/bin/whisper-server ]; then
    echo "[*] Environment not initialized. Running setup first..."
    ./.superset/setup.sh
fi

echo "[*] Launching Dicty in development mode..."
exec ./scripts/run_client.sh "$@"
