#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="${SUPERSET_WORKSPACE_PATH:-$PROJECT_DIR}"

echo "=================================================="
echo "         Dicty Workspace Teardown"
echo "=================================================="

# 1. Stop and remove docker compose services for this workspace if any were started
if [ -f "$WORKSPACE_DIR/docker-compose.yml" ]; then
    if [ -n "$SUPERSET_WORKSPACE_NAME" ]; then
        RAW_PROJECT="dicty_${SUPERSET_WORKSPACE_NAME//[^a-zA-Z0-9_-]/_}"
    else
        DIR_NAME="$(basename "$WORKSPACE_DIR")"
        DIR_HASH="$(printf "%s" "$WORKSPACE_DIR" | md5 2>/dev/null || printf "%s" "$WORKSPACE_DIR" | md5sum 2>/dev/null | awk '{print $1}')"
        DIR_HASH="${DIR_HASH:0:8}"
        RAW_PROJECT="dicty_${DIR_NAME//[^a-zA-Z0-9_-]/_}_${DIR_HASH}"
    fi
    # Normalize project name to lowercase per Docker Compose specifications
    COMPOSE_PROJECT="$(printf "%s" "$RAW_PROJECT" | tr '[:upper:]' '[:lower:]')"

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
    if [ -n "$RUN_PID" ]; then
        if kill -0 "$RUN_PID" 2>/dev/null; then
            # Verify process identity before sending signals to prevent signaling recycled PIDs
            PROC_CMD="$(ps -p "$RUN_PID" -o args= 2>/dev/null || true)"
            if echo "$PROC_CMD" | grep -Eq 'dicty_engine|DictyClient|run_client\.sh|run\.sh'; then
                echo "[*] Terminating dev server process (PID $RUN_PID)..."
                pkill -P "$RUN_PID" 2>/dev/null || true
                kill "$RUN_PID" 2>/dev/null || true
                sleep 1
                if kill -0 "$RUN_PID" 2>/dev/null; then
                    pkill -9 -P "$RUN_PID" 2>/dev/null || true
                    kill -9 "$RUN_PID" 2>/dev/null || true
                fi
            else
                echo "[!] Stale PID $RUN_PID does not match dev process (current: '$PROC_CMD'). Skipping signals."
            fi
        fi
    fi
    rm -f "$PID_FILE"
fi

# 3. Clean up setup lock safely without disrupting active setups
LOCK_DIR="$WORKSPACE_DIR/.superset/.setup.lock"
if [ -d "$LOCK_DIR" ]; then
    LOCK_PID_FILE="$LOCK_DIR/pid"
    LOCK_PID=""
    if [ -f "$LOCK_PID_FILE" ]; then
        LOCK_PID="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
    fi

    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        PROC_CMD="$(ps -p "$LOCK_PID" -o args= 2>/dev/null || true)"
        if echo "$PROC_CMD" | grep -Eq 'setup\.sh|make'; then
            echo "[*] Active workspace setup process detected (PID $LOCK_PID). Terminating setup before teardown..."
            pkill -P "$LOCK_PID" 2>/dev/null || true
            kill "$LOCK_PID" 2>/dev/null || true
            sleep 1
            if kill -0 "$LOCK_PID" 2>/dev/null; then
                pkill -9 -P "$LOCK_PID" 2>/dev/null || true
                kill -9 "$LOCK_PID" 2>/dev/null || true
            fi
        fi
    fi

    rm -rf "$LOCK_DIR"
fi

echo "[+] Dicty workspace teardown completed."
