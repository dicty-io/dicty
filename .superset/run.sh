#!/bin/bash
set -e

if [ ! -f .venv/bin/python3 ]; then
  ./scripts/setup_runner_env.sh
fi

echo "[*] Starting Dicty engine on http://127.0.0.1:8075..."
exec .venv/bin/python3 dicty_engine.py
