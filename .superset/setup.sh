#!/bin/bash
set -e

# 1. Sync .env from root repository if available, or initialize from .env.example
if [ -n "$SUPERSET_ROOT_PATH" ] && [ -f "$SUPERSET_ROOT_PATH/.env" ] && [ ! -f .env ]; then
  echo "[*] Copying .env from root workspace..."
  cp "$SUPERSET_ROOT_PATH/.env" .env
elif [ ! -f .env ] && [ -f .env.example ]; then
  echo "[*] Initializing .env from .env.example..."
  cp .env.example .env
fi

# 2. Configure executable permissions
chmod +x scripts/*.sh *.sh 2>/dev/null || true

# 3. Setup Python virtual environment & dependencies (cached)
./scripts/setup_runner_env.sh

# 4. Restore compiled whisper.cpp binaries (cached)
./scripts/compile_whisper.sh

echo "[+] Dicty workspace setup complete!"
