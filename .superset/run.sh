#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PID_FILE="$PROJECT_DIR/.superset/run.pid"

# 1. Prevent concurrent dev server launches sharing the same workspace
if [ -f "$PID_FILE" ]; then
    EXISTING_PID="$(sed -n '1p' "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        echo "[!] Dicty dev server is already running in this workspace (PID $EXISTING_PID)."
        exit 0
    fi
fi

# 2. Isolate development backend data to the workspace with restricted permissions (0700)
export DICTY_DATA_DIR="${DICTY_DATA_DIR:-$PROJECT_DIR/.dicty_data}"
mkdir -p "$DICTY_DATA_DIR"
chmod 700 "$DICTY_DATA_DIR" 2>/dev/null || true

# 3. Ensure environment is initialized before launching dev processes
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

# 4. Record process PID and launch start time to reliably track identity across exec
DEV_LSTART="$(ps -p "$DEV_PID" -o lstart= 2>/dev/null || true)"
printf "%s\n%s\n%s\n" "$DEV_PID" "$DEV_LSTART" "$PROJECT_DIR" > "$PID_FILE"

cleanup() {
    # Only remove PID file if it still belongs to this specific launch
    if [ -f "$PID_FILE" ]; then
        RECORDED_PID="$(sed -n '1p' "$PID_FILE" 2>/dev/null || true)"
        if [ "$RECORDED_PID" = "$DEV_PID" ]; then
            rm -f "$PID_FILE"
        fi
    fi
    if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
        pkill -P "$DEV_PID" 2>/dev/null || true
        kill "$DEV_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

wait "$DEV_PID"
