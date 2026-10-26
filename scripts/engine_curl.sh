#!/usr/bin/env bash
# scripts/engine_curl.sh - Helper to run curl commands against local Dicty engine with X-Dicty-Token auth.
set -euo pipefail

if [ -n "${DICTY_DATA_DIR:-}" ]; then
    DATA_DIR="$DICTY_DATA_DIR"
else
    case "$(uname -s)" in
        Darwin)
            DATA_DIR="$HOME/Library/Application Support/Dicty"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            WINDOWS_HOME="${USERPROFILE:-$HOME}"
            if command -v cygpath >/dev/null 2>&1; then
                WINDOWS_HOME="$(cygpath -u "$WINDOWS_HOME")"
            fi
            DATA_DIR="$WINDOWS_HOME/.dicty"
            ;;
        *)
            DATA_DIR="$HOME/.dicty"
            ;;
    esac
fi

TOKEN_FILE="$DATA_DIR/engine.token"
PORT="${DICTY_ENGINE_PORT:-8075}"
HOST="${DICTY_ENGINE_HOST:-127.0.0.1}"
BASE_URL="http://${HOST}:${PORT}"

TOKEN=""
if [ -f "$TOKEN_FILE" ]; then
    PYTHON_BIN="$(command -v python3 || command -v python || true)"
    if [ -n "$PYTHON_BIN" ]; then
        TOKEN=$("$PYTHON_BIN" -c 'import json, sys; print(json.load(open(sys.argv[1])).get("token", ""))' "$TOKEN_FILE" 2>/dev/null || true)
    fi
fi

AUTH_HEADERS=()
if [ -n "$TOKEN" ]; then
    AUTH_HEADERS+=(-H "X-Dicty-Token: $TOKEN")
fi

PASSED_ARGS=()
FOUND_URL=0
for arg in "$@"; do
    if [[ "$arg" =~ ^https?:// ]]; then
        FOUND_URL=1
        PASSED_ARGS+=("$arg")
    elif [[ "$arg" == /* ]]; then
        FOUND_URL=1
        PASSED_ARGS+=("${BASE_URL}${arg}")
    else
        PASSED_ARGS+=("$arg")
    fi
done

if [ "$FOUND_URL" -eq 0 ] && [ ${#PASSED_ARGS[@]} -eq 0 ]; then
    echo "Usage: $0 [curl options] <endpoint-or-url>"
    echo "Examples:"
    echo "  $0 /health"
    echo "  $0 /status"
    echo "  $0 -X POST /recording/start"
    exit 1
fi

if [ ${#AUTH_HEADERS[@]} -gt 0 ]; then
    exec curl -sSL "${AUTH_HEADERS[@]}" "${PASSED_ARGS[@]}"
else
    exec curl -sSL "${PASSED_ARGS[@]}"
fi
