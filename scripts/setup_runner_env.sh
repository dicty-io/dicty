#!/bin/bash
# scripts/setup_runner_env.sh
# Sets up and caches Python virtual environment and pip cache for local development and self-hosted runners.
# Ensures packages are installed ONCE and reused across all subsequent runs in <0.5s.

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# 1. Determine persistent cache directory OUTSIDE the git workspace
# (Because actions/checkout runs 'git clean -ffdx' which deletes any .venv inside the workspace)
if [ -n "$RUNNER_WORKSPACE" ]; then
    RUNNER_ROOT="$(cd "$RUNNER_WORKSPACE/../.." 2>/dev/null && pwd)"
    CACHE_DIR="${RUNNER_ROOT}/_cache"
elif [ -d "$HOME/Documents/actions-runner" ]; then
    CACHE_DIR="$HOME/Documents/actions-runner/_cache"
elif [ -d "$HOME/actions-runner" ]; then
    CACHE_DIR="$HOME/actions-runner/_cache"
else
    CACHE_DIR="$HOME/.dicty_cache"
fi

mkdir -p "$CACHE_DIR/pip" "$CACHE_DIR/whisper"
export PIP_CACHE_DIR="$CACHE_DIR/pip"

PERSISTENT_VENV="$CACHE_DIR/venv"

# 2. Compute checksum of requirement files to detect if dependencies changed
REQ_HASH=""
if command -v md5 &>/dev/null; then
    REQ_HASH=$(md5 -q requirements.txt 2>/dev/null || true)
elif command -v md5sum &>/dev/null; then
    REQ_HASH=$(md5sum requirements.txt 2>/dev/null | awk '{print $1}')
fi

HASH_FILE="$PERSISTENT_VENV/.dicty_req_hash"
NEEDS_INSTALL=0

if [ ! -d "$PERSISTENT_VENV" ] || [ ! -f "$PERSISTENT_VENV/bin/python3" ]; then
    echo "[*] Creating persistent virtual environment in $PERSISTENT_VENV..."
    rm -rf "$PERSISTENT_VENV"
    python3 -m venv "$PERSISTENT_VENV"
    NEEDS_INSTALL=1
elif ! "$PERSISTENT_VENV/bin/python3" -c "import fastapi, httpx, passlib, jose, multipart, email_validator, PyInstaller, cmake, PIL" 2>/dev/null; then
    echo "[!] Core packages missing from $PERSISTENT_VENV. Reinstalling..."
    NEEDS_INSTALL=1
elif [ -f "$HASH_FILE" ] && [ -n "$REQ_HASH" ] && [ "$(cat "$HASH_FILE")" = "$REQ_HASH" ]; then
    NEEDS_INSTALL=0
else
    # Hash changed or missing
    NEEDS_INSTALL=1
fi

if [ $NEEDS_INSTALL -eq 1 ]; then
    echo "[*] Installing/updating Python dependencies (pip cache: $PIP_CACHE_DIR)..."
    "$PERSISTENT_VENV/bin/pip" install --upgrade pip --quiet
    "$PERSISTENT_VENV/bin/pip" install -r requirements.txt --quiet
    if [ -f requirements-desktop.txt ]; then
        "$PERSISTENT_VENV/bin/pip" install -r requirements-desktop.txt --quiet
    fi
    "$PERSISTENT_VENV/bin/pip" install --quiet pyinstaller cmake pillow
    if [ -n "$REQ_HASH" ]; then
        echo "$REQ_HASH" > "$HASH_FILE"
    fi
    echo "[+] Dependencies installed and cached successfully in $PERSISTENT_VENV!"
else
    echo "[+] Reusing cached persistent virtual environment (0.0s download time)!"
fi

# 3. Create/update .venv symlink in workspace root for local scripts
CURRENT_LINK="$(readlink .venv 2>/dev/null || true)"
if [ "$CURRENT_LINK" != "$PERSISTENT_VENV" ]; then
    rm -rf .venv
    ln -sf "$PERSISTENT_VENV" .venv
fi
