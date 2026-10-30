#!/bin/bash
# run_client.sh - Launches Dicty Swift UI client locally
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "$DEVELOPER_DIR" ] || [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
    for xcode_path in \
        "/Applications/Xcode.app/Contents/Developer" \
        /Applications/Xcode*.app/Contents/Developer; do
        if [ -d "$xcode_path" ]; then
            export DEVELOPER_DIR="$xcode_path"
            break
        fi
    done
    if [ -z "$DEVELOPER_DIR" ] || [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
        if [ -z "$SDKROOT" ]; then
            for sdk_path in \
                "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk" \
                "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"; do
                if [ -d "$sdk_path" ]; then
                    export SDKROOT="$sdk_path"
                    break
                fi
            done
        fi
    fi
fi

cd "$PROJECT_DIR"
chmod +x scripts/check_engine_endpoint.sh
./scripts/check_engine_endpoint.sh

cd "$PROJECT_DIR/DictyClient"
exec swift run "$@"
