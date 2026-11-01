#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="${SUPERSET_WORKSPACE_PATH:-$PROJECT_DIR}"

echo "=================================================="
echo "         Dicty Workspace Teardown"
echo "=================================================="

# 1. Stop and remove docker compose services for this workspace if any were started
if [ -f "$WORKSPACE_DIR/docker-compose.yml" ]; then
    echo "[*] Cleaning up docker compose services..."
    if command -v docker &>/dev/null; then
        (cd "$WORKSPACE_DIR" && docker compose down -v --remove-orphans 2>/dev/null) || \
        (cd "$WORKSPACE_DIR" && docker-compose down -v --remove-orphans 2>/dev/null) || true
    fi
fi

# 2. Terminate background processes associated with this workspace
echo "[*] Terminating processes associated with workspace: $WORKSPACE_DIR"
CURRENT_PID=$$
PIDS_TO_KILL=()

for pid in $(pgrep -f "$WORKSPACE_DIR" 2>/dev/null || true); do
    if [ "$pid" != "$CURRENT_PID" ] && [ "$pid" != "$PPID" ]; then
        PIDS_TO_KILL+=("$pid")
        kill "$pid" 2>/dev/null || true
    fi
done

if [ ${#PIDS_TO_KILL[@]} -gt 0 ]; then
    sleep 1
    for pid in "${PIDS_TO_KILL[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
fi

echo "[+] Dicty workspace teardown completed."
