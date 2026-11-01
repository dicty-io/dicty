#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

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

# 2. Run standard project setup (venv, deps, whisper, client build)
make setup

echo "[+] Dicty workspace setup completed successfully!"
