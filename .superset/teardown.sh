#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="${SUPERSET_WORKSPACE_PATH:-$PROJECT_DIR}"

echo "=================================================="
echo "         Dicty Workspace Teardown"
echo "=================================================="

# 1. Stop and remove docker compose services for this workspace if any were started
if [ -f "$WORKSPACE_DIR/docker-compose.yml" ]; then
    if [ -n "$SUPERSET_WORKSPACE_NAME" ]; then
        COMPOSE_PROJECT="dicty_${SUPERSET_WORKSPACE_NAME//[^a-zA-Z0-9_-]/_}"
    else
        DIR_NAME="$(basename "$WORKSPACE_DIR")"
        DIR_HASH="$(printf "%s" "$WORKSPACE_DIR" | md5 2>/dev/null || printf "%s" "$WORKSPACE_DIR" | md5sum 2>/dev/null | awk '{print $1}')"
        DIR_HASH="${DIR_HASH:0:8}"
        COMPOSE_PROJECT="dicty_${DIR_NAME//[^a-zA-Z0-9_-]/_}_${DIR_HASH}"
    fi

    COMPOSE_CMD=""
    if command -v docker &>/dev/null && (cd "$WORKSPACE_DIR" && docker compose version &>/dev/null); then
        COMPOSE_CMD="docker compose -p $COMPOSE_PROJECT"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose -p $COMPOSE_PROJECT"
    fi

    if [ -n "$COMPOSE_CMD" ]; then
        if (cd "$WORKSPACE_DIR" && $COMPOSE_CMD ps -a -q 2>/dev/null | grep -q .); then
            echo "[*] Cleaning up docker compose services for project: $COMPOSE_PROJECT..."
            (cd "$WORKSPACE_DIR" && $COMPOSE_CMD down -v --remove-orphans 2>/dev/null) || true
        fi
    fi
fi

# 2. Terminate tracked background dev processes launched by .superset/run.sh
PID_FILE="$WORKSPACE_DIR/.superset/run.pid"
if [ -f "$PID_FILE" ]; then
    RUN_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$RUN_PID" ] && kill -0 "$RUN_PID" 2>/dev/null; then
        echo "[*] Terminating dev server process (PID $RUN_PID)..."
        pkill -P "$RUN_PID" 2>/dev/null || true
        kill "$RUN_PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$RUN_PID" 2>/dev/null; then
            pkill -9 -P "$RUN_PID" 2>/dev/null || true
            kill -9 "$RUN_PID" 2>/dev/null || true
        fi
    fi
    rm -f "$PID_FILE"
fi

# 3. Clean up lock directory if orphaned
rm -rf "$WORKSPACE_DIR/.superset/.setup.lock"

echo "[+] Dicty workspace teardown completed."
