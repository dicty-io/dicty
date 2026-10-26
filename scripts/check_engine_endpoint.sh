#!/usr/bin/env bash
# Fail if an engine host, port, or token leaks outside the central client module.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SWIFT_DIR="$PROJECT_DIR/DictyClient/Sources/DictyClient"
SWIFT_OWNERS="^$SWIFT_DIR/EngineEndpoint\\.swift:"

TAURI_SRC="$PROJECT_DIR/DictyClientTauri/src-tauri/src"
TAURI_RUST_OWNERS="^$TAURI_SRC/(engine_auth|engine_http|engine)\\.rs:"

TAURI_WEB_DIR="$PROJECT_DIR/DictyClientTauri/src"
TAURI_WEB_OWNERS="^$TAURI_WEB_DIR/services/engineClient\\.ts:"

FAILED=0

check_pattern() {
    local label="$1"
    local pattern="$2"
    local directory="$3"
    local includes="$4"
    local owners="$5"
    local matches

    matches=$(grep -RInE "$pattern" "$directory" --include="$includes" | grep -Ev "$owners" || true)
    if [ -n "$matches" ]; then
        echo "[-] $label must only appear in its central client module:"
        echo "$matches"
        FAILED=1
    fi
}

check_pattern "Swift engine port 8075" '8075' "$SWIFT_DIR" '*.swift' "$SWIFT_OWNERS"
check_pattern "Swift loopback host with port" '127\.0\.0\.1:' "$SWIFT_DIR" '*.swift' "$SWIFT_OWNERS"
check_pattern "Swift engine auth header" 'X-Dicty-Token' "$SWIFT_DIR" '*.swift' "$SWIFT_OWNERS"
check_pattern "Swift engine token file/env" 'engine\.token|DICTY_SESSION_TOKEN' "$SWIFT_DIR" '*.swift' "$SWIFT_OWNERS"

check_pattern "Tauri engine port 8075" '8075' "$TAURI_SRC" '*.rs' "$TAURI_RUST_OWNERS"
check_pattern "Tauri loopback host with port" '127\.0\.0\.1:' "$TAURI_SRC" '*.rs' "$TAURI_RUST_OWNERS"
check_pattern "Tauri engine auth header" 'X-Dicty-Token' "$TAURI_SRC" '*.rs' "$TAURI_RUST_OWNERS"
check_pattern "Tauri engine token file/env" 'engine\.token|DICTY_SESSION_TOKEN' "$TAURI_SRC" '*.rs' "$TAURI_RUST_OWNERS"

check_pattern "Tauri web engine port 8075" '8075' "$TAURI_WEB_DIR" '*.ts*' "$TAURI_WEB_OWNERS"
check_pattern "Tauri web loopback host with port" '127\.0\.0\.1:' "$TAURI_WEB_DIR" '*.ts*' "$TAURI_WEB_OWNERS"
check_pattern "Tauri web engine auth header" 'X-Dicty-Token' "$TAURI_WEB_DIR" '*.ts*' "$TAURI_WEB_OWNERS"
check_pattern "Tauri web engine token file/env" 'engine\.token|DICTY_SESSION_TOKEN' "$TAURI_WEB_DIR" '*.ts*' "$TAURI_WEB_OWNERS"
check_pattern "Tauri web old WebSocket URL helper" 'getStreamWebSocketUrl' "$TAURI_WEB_DIR" '*.ts*' "$TAURI_WEB_OWNERS"

if [ "$FAILED" -ne 0 ]; then
    echo ""
    echo "[-] Engine endpoint guard failed."
    echo "    Swift: route calls through EngineEndpoint.swift."
    echo "    Tauri Rust: route calls through engine_http.rs."
    echo "    Tauri web: route calls through services/engineClient.ts."
    exit 1
fi

echo "[+] Engine endpoint guard passed."
