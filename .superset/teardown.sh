#!/bin/bash
# Teardown workspace services and stop containers if running
if command -v docker &>/dev/null && docker compose ps -q 2>/dev/null | grep -q .; then
  echo "[*] Stopping docker containers..."
  docker compose down 2>/dev/null || true
fi
