#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

LOCK_DIR="$PROJECT_DIR/.superset/.setup.lock"

acquire_lock() {
    local timeout=180
    local waited=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        if [ "$waited" -eq 0 ]; then
            echo "[*] Another workspace setup is currently running. Waiting for lock..."
        fi
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$timeout" ]; then
            echo "[!] Setup lock wait timeout reached ($timeout s). Cleaning stale lock..."
            rm -rf "$LOCK_DIR"
            break
        fi
    done
}

release_lock() {
    rm -rf "$LOCK_DIR"
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
