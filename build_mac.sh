#!/bin/bash
# build_mac.sh
# This script packages the Dicty backend into a standalone Mac executable using PyInstaller.

echo "[*] Installing build dependencies..."
./.venv/bin/python3 -m pip install pyinstaller

echo "[*] Packaging Dicty backend..."
# We use --add-data to bundle the whisper-cli binary inside the packaged app.
# When the app runs, it will extract whisper-cli to a temporary folder automatically.

# Ensure whisper.cpp is compiled with the best optimizations for this Mac
echo "[*] Ensuring whisper.cpp is compiled natively..."
./scripts/compile_whisper.sh

# Find locally compiled whisper-cli and whisper-server binaries
WHISPER_CLI_BIN="bin/whisper.cpp/build/bin/whisper-cli"
WHISPER_SERVER_BIN="bin/whisper.cpp/build/bin/whisper-server"

if [ ! -f "$WHISPER_CLI_BIN" ] || [ ! -f "$WHISPER_SERVER_BIN" ]; then
    echo "[-] Error: whisper binaries not found in bin/whisper.cpp/build/bin even after compilation."
    exit 1
fi

# Clean previous builds to prevent PyInstaller zlib corruption
rm -rf build/ dist/

# Generate telemetry_config.json from build environment if available
if [ -n "$POSTHOG_API_KEY" ]; then
    echo "{\"posthog_api_key\": \"$POSTHOG_API_KEY\", \"posthog_host\": \"${POSTHOG_HOST:-https://us.i.posthog.com}\"}" > telemetry_config.json
elif [ ! -f "telemetry_config.json" ]; then
    echo "{}" > telemetry_config.json
fi

# PyInstaller command
./.venv/bin/python3 -m PyInstaller --noconfirm \
    --name dicty_engine \
    --onedir \
    --paths="." \
    --paths="services" \
    --paths="integrations" \
    --hidden-import passlib.handlers.bcrypt \
    --hidden-import uvicorn.logging \
    --hidden-import uvicorn.loops \
    --hidden-import uvicorn.loops.auto \
    --hidden-import uvicorn.protocols \
    --hidden-import uvicorn.protocols.http \
    --hidden-import uvicorn.protocols.http.auto \
    --hidden-import uvicorn.protocols.websockets \
    --hidden-import uvicorn.protocols.websockets.auto \
    --hidden-import websockets \
    --hidden-import websockets.legacy.client \
    --hidden-import cloud_streaming \
    --hidden-import="transcript_join" \
    --hidden-import="dicty_paths" \
    --hidden-import="uvicorn.lifespan" \
    --hidden-import="uvicorn.lifespan.on" \
    --hidden-import="uvicorn.lifespan.off" \
    --hidden-import="fastapi" \
    --hidden-import="starlette" \
    --hidden-import="anyio" \
    --hidden-import="pydantic" \
    --hidden-import="pydantic.fields" \
    --hidden-import="pydantic.main" \
    --hidden-import="multipart" \
    --hidden-import="email_validator" \
    --hidden-import="passlib.handlers.bcrypt" \
    --hidden-import="scipy" \
    --hidden-import="scipy.signal" \
    --hidden-import="prompts" \
    --hidden-import="llm_service" \
    --hidden-import="transcribe_service" \
    --hidden-import="model_manager" \
    --hidden-import="audio_recorder" \
    --hidden-import="agent_service" \
    --hidden-import="notion_service" \
    --hidden-import="queue_manager" \
    --hidden-import="pending_manager" \
    --hidden-import="auth" \
    --hidden-import="update_manager" \
    --hidden-import="telemetry_service" \
    --hidden-import="db" \
    --hidden-import="git_service" \
    --hidden-import="github_service" \
    --hidden-import="gitlab_service" \
    --hidden-import="bitbucket_service" \
    --hidden-import="linear_service" \
    --hidden-import="confluence_service" \
    --hidden-import="obsidian_service" \
    --hidden-import="hub_service" \
    --hidden-import="tts_service" \
    --hidden-import="silero_service" \
    --hidden-import="piper_service" \
    --hidden-import="dictation_metrics" \
    --hidden-import="local_whisper" \
    --hidden-import="local_llm" \
    --hidden-import="snippet_service" \
    --hidden-import="meeting_dialogue" \
    --hidden-import="modes_service" \
    --hidden-import="style_rules" \
    --hidden-import="local_corrections" \
    --hidden-import="typing_extensions" \
    --hidden-import="pickletools" \
    --hidden-import="_compat_pickle" \
    --hidden-import="app_rules" \
    --hidden-import="app_rules_defaults" \
    --exclude-module="torch" \
    --exclude-module="torchvision" \
    --exclude-module="torchaudio" \
    --collect-all="onnxruntime" \
    --collect-all="kokoro_onnx" \
    --collect-all="espeakng_loader" \
    --collect-all="phonemizer" \
    --collect-all="certifi" \
    --collect-all="numpy" \
    --add-data "$WHISPER_CLI_BIN:bin" \
    --add-data "$WHISPER_SERVER_BIN:bin" \
    --add-data "models_config.json:." \
    --add-data "telemetry_config.json:." \
    --add-data ".env.example:.env" \
    --add-data "compat_libs/pickletools.py:." \
    --add-data "compat_libs/_compat_pickle.py:." \
    --add-data "compat_libs/typing_extensions.py:." \
    dicty_engine.py

echo "[+] Build complete! Standalone executable is located at dist/dicty_engine"
echo "[*] The Swift UI Client can now be updated to launch 'dist/dicty_engine' silently in the background."
