#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

LOCK_DIR="$PROJECT_DIR/.superset/.setup.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"

acquire_lock() {
    local timeout=180
    local waited=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        local lock_pid=""
        if [ -f "$LOCK_PID_FILE" ]; then
            lock_pid="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
        fi

        # If lock was left by a terminated/crashed process, attempt exclusive atomic recovery
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            local recovery_dir="$LOCK_DIR.stale.$$"
            if mv "$LOCK_DIR" "$recovery_dir" 2>/dev/null; then
                # Under exclusive recovery guard, re-verify PID before removing
                local stale_pid=""
                if [ -f "$recovery_dir/pid" ]; then
                    stale_pid="$(cat "$recovery_dir/pid" 2>/dev/null || true)"
                fi
                if [ -n "$stale_pid" ] && kill -0 "$stale_pid" 2>/dev/null; then
                    # Defunct check raced with reuse; restore lock
                    mv "$recovery_dir" "$LOCK_DIR" 2>/dev/null || rm -rf "$recovery_dir"
                else
                    echo "[*] Removed stale setup lock from defunct PID ${stale_pid:-$lock_pid}."
                    rm -rf "$recovery_dir"
                fi
            fi
            # Always retry normal mkdir acquisition after recovery attempt
            continue
        fi

        if [ "$waited" -eq 0 ]; then
            echo "[*] Another workspace setup is currently running (PID ${lock_pid:-unknown}). Waiting for lock..."
        fi
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$timeout" ]; then
            echo "[-] Error: Setup lock timeout reached ($timeout s) while waiting for PID ${lock_pid:-unknown}." >&2
            echo "[-] Refusing to modify workspace concurrently with active setup." >&2
            exit 1
        fi
    done
    echo "$$" > "$LOCK_PID_FILE"
}

release_lock() {
    if [ -f "$LOCK_PID_FILE" ] && [ "$(cat "$LOCK_PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -rf "$LOCK_DIR"
    fi
}

acquire_lock
trap release_lock EXIT INT TERM

echo "=================================================="
echo "         Dicty Workspace Setup"
echo "=================================================="

# 1. Copy environment file from root repository or fallback to template
if [ -n "$SUPERSET_ROOT_PATH" ] && [ -f "$SUPERSET_ROOT_PATH/.env" ] && [ ! -f .env ]; then
    echo "[+] Copying .env from root repository ($SUPERSET_ROOT_PATH/.env)..."
    cp "$SUPERSET_ROOT_PATH/.env" .env
elif [ ! -f .env ] && [ -f .env.example ]; then
    echo "[+] Initializing .env from .env.example..."
    cp .env.example .env
fi

# 2. Run appropriate project setup (backend-only vs full setup)
if [ "$1" = "--backend-only" ] || [ "$DICTY_SETUP_BACKEND_ONLY" = "1" ]; then
    echo "[*] Running backend-only setup target..."
    make setup-backend
else
    make setup
fi

echo "[+] Dicty workspace setup completed successfully!"
