#!/bin/bash
# compile_whisper.sh
# Compiles the local whisper.cpp binary with the best possible optimizations for macOS.

set -e

# 1. Resolve persistent runner cache directory
if [ -n "$RUNNER_CACHE_DIR" ]; then
    CACHE_DIR="$RUNNER_CACHE_DIR/whisper"
elif [ -n "$RUNNER_WORKSPACE" ]; then
    RUNNER_ROOT="$(cd "$RUNNER_WORKSPACE/../.." && pwd)"
    CACHE_DIR="$RUNNER_ROOT/_cache/whisper"
elif [ -d "$HOME/actions-runner" ]; then
    CACHE_DIR="$HOME/actions-runner/_cache/whisper"
elif [ -d "$HOME/Documents/actions-runner" ]; then
    CACHE_DIR="$HOME/Documents/actions-runner/_cache/whisper"
else
    CACHE_DIR="$HOME/.dicty_cache/whisper"
fi

WHISPER_DIR="bin/whisper.cpp"
TARGET_BIN_DIR="$WHISPER_DIR/build/bin"

# 2. Check if pre-compiled binaries are already cached and statically linked
if [ -f "$CACHE_DIR/whisper-cli" ] && [ -f "$CACHE_DIR/whisper-server" ]; then
    if otool -L "$CACHE_DIR/whisper-cli" 2>/dev/null | grep -q "@rpath/libwhisper"; then
        echo "[!] Stale dynamic whisper cache detected. Removing to force static recompilation..."
        rm -f "$CACHE_DIR/whisper-cli" "$CACHE_DIR/whisper-server"
    else
        echo "[+] Reusing cached static whisper.cpp binaries from: $CACHE_DIR"
        mkdir -p "$TARGET_BIN_DIR"
        cp -f "$CACHE_DIR/whisper-cli" "$TARGET_BIN_DIR/"
        cp -f "$CACHE_DIR/whisper-server" "$TARGET_BIN_DIR/"
        chmod +x "$TARGET_BIN_DIR/whisper-cli" "$TARGET_BIN_DIR/whisper-server"
        echo "[+] Restored whisper binaries from runner cache successfully!"
        exit 0
    fi
fi

echo "[*] Precompiled static whisper binaries not found in cache ($CACHE_DIR). Starting compilation..."

# Use pip to install cmake in the local virtual environment to avoid Homebrew permission issues
if [ ! -x "./.venv/bin/cmake" ]; then
    echo "[*] cmake not found in .venv. Installing via pip..."
    ./.venv/bin/python3 -m pip install cmake
fi

CMAKE_BIN="$(pwd)/.venv/bin/cmake"

if [ ! -d "$WHISPER_DIR" ]; then
    if [ -d "whisper.cpp" ]; then
        WHISPER_DIR="whisper.cpp"
    else
        echo "[-] Error: whisper.cpp source not found at $WHISPER_DIR."
        echo "[*] Cloning whisper.cpp..."
        mkdir -p bin
        git clone https://github.com/ggerganov/whisper.cpp "$WHISPER_DIR"
    fi
fi

ROOT_DIR="$(pwd)"
cd "$WHISPER_DIR"

# Clean previous builds
rm -rf build

# Detect available CPU cores for bounded parallel compilation
NPROC=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

COMMON_FLAGS=(
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}"
    -DBUILD_SHARED_LIBS=OFF
    -DWHISPER_BUILD_TESTS=OFF
    -DWHISPER_BUILD_EXAMPLES=ON
    -DWHISPER_FATAL_WARNINGS=OFF
    -DGGML_FATAL_WARNINGS=OFF
    -DWHISPER_ALL_WARNINGS=OFF
    -DGGML_ALL_WARNINGS=OFF
    -DCMAKE_C_FLAGS="-Wno-tautological-compare -Wno-unused-function"
    -DCMAKE_CXX_FLAGS="-Wno-tautological-compare -Wno-unused-function"
)

# Detect hardware architecture (handle Rosetta processes running as x86_64 on Apple Silicon)
IS_ARM64=0
if [ "$(uname -m)" = "arm64" ] || [ "$(sysctl -in hw.optional.arm64 2>/dev/null)" = "1" ]; then
    IS_ARM64=1
fi

if [ "$IS_ARM64" = "1" ]; then
    echo "[*] Apple Silicon (ARM64) detected. Enabling Metal GPU and Accelerate."
    "$CMAKE_BIN" -B build \
        -DCMAKE_OSX_ARCHITECTURES="arm64" \
        -DGGML_METAL=1 \
        -DWHISPER_ACCELERATE=1 \
        -DGGML_NATIVE=OFF \
        "${COMMON_FLAGS[@]}"
else
    echo "[*] Intel (x86_64) detected. Enabling Apple Accelerate (BLAS) for maximum CPU performance."
    "$CMAKE_BIN" -B build \
        -DCMAKE_OSX_ARCHITECTURES="x86_64" \
        -DWHISPER_ACCELERATE=1 \
        -DGGML_BLAS=1 \
        -DGGML_NATIVE=OFF \
        "${COMMON_FLAGS[@]}"
fi

echo "[*] Building targets (whisper-cli, whisper-server) with $NPROC cores..."
"$CMAKE_BIN" --build build --config Release --target whisper-cli -j "$NPROC"
"$CMAKE_BIN" --build build --config Release --target whisper-server -j "$NPROC"

# Return to repository root so relative paths match
cd "$ROOT_DIR"

echo "[+] Compilation successful!"
echo "    Binaries are located at: $TARGET_BIN_DIR/"

# Save to persistent runner cache
mkdir -p "$CACHE_DIR"
cp -f "$TARGET_BIN_DIR/whisper-cli" "$CACHE_DIR/"
cp -f "$TARGET_BIN_DIR/whisper-server" "$CACHE_DIR/"
echo "[+] Saved compiled whisper.cpp binaries to runner cache ($CACHE_DIR)!"
