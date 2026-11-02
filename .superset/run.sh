#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PID_FILE="$PROJECT_DIR/.superset/run.pid"

# 1. Isolate development backend data to the workspace with restricted permissions (0700)
export DICTY_DATA_DIR="${DICTY_DATA_DIR:-$PROJECT_DIR/.dicty_data}"
mkdir -p "$DICTY_DATA_DIR"
chmod 700 "$DICTY_DATA_DIR" 2>/dev/null || true

# 2. Ensure environment is initialized before creating PID tracking
if [ "$1" = "--backend-only" ] || [ "$DICTY_RUN_BACKEND_ONLY" = "1" ]; then
    if [ ! -f .venv/bin/python3 ] || [ ! -f bin/whisper.cpp/build/bin/whisper-server ]; then
        echo "[*] Backend environment not initialized. Running backend setup first..."
        ./.superset/setup.sh --backend-only
    fi

    echo "[*] Starting Dicty Python backend engine (:8075)..."
    .venv/bin/python3 dicty_engine.py &
    DEV_PID=$!
else
    if [ ! -f .venv/bin/python3 ] || [ ! -f bin/whisper.cpp/build/bin/whisper-server ]; then
        echo "[*] Environment not initialized. Running setup first..."
        ./.superset/setup.sh
    fi

    echo "[*] Launching Dicty in development mode..."
    ./scripts/run_client.sh "$@" &
    DEV_PID=$!
fi

# 3. Track process PID and ensure removal on normal exit or interruption
echo "$DEV_PID" > "$PID_FILE"

cleanup() {
    rm -f "$PID_FILE"
    if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
        pkill -P "$DEV_PID" 2>/dev/null || true
        kill "$DEV_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

wait "$DEV_PID"
