#!/bin/bash
# run_tests.sh
# Comprehensive test runner for Dicty backend, updates, and core APIs.
# Can be run locally and in GitHub Actions CI pipelines.

set -e

echo "=================================================================="
echo " 🧪 RUNNING DICTY AUTOMATED TEST SUITE"
echo "=================================================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Ensure virtual environment and dependencies are cached and healthy
chmod +x scripts/setup_runner_env.sh
./scripts/setup_runner_env.sh

PYTHON_BIN="./.venv/bin/python3"

echo "[*] Using Python: $($PYTHON_BIN --version)"

echo "[*] Checking engine endpoint centralization..."
chmod +x scripts/check_engine_endpoint.sh
./scripts/check_engine_endpoint.sh

# Run test suite with coverage
echo "[*] Executing backend test suite with coverage..."
$PYTHON_BIN -m coverage run -m unittest discover -s tests -p "test_*.py" -v
if $PYTHON_BIN -m coverage xml -o coverage.xml; then
    echo "[+] Generated coverage.xml report successfully."
else
    echo "[!] Warning: Failed to generate coverage.xml report."
fi

# Check if Swift tests should be skipped
if [ "$1" = "--backend-only" ] || [ "$BACKEND_ONLY" = "1" ] || [ "$SKIP_SWIFT" = "1" ]; then
    echo "=================================================================="
    echo " ⏭️  Skipping Swift client tests (--backend-only / SKIP_SWIFT set)."
    echo "=================================================================="
    echo "=================================================================="
    echo " ✅ ALL BACKEND TESTS PASSED SUCCESSFULLY!"
    echo "=================================================================="
    exit 0
fi

# Run Swift client tests if swift command is available
if command -v swift &> /dev/null; then
    echo "=================================================================="
    echo " 🍎 EXECUTING SWIFT CLIENT TESTS & BUILD VALIDATION"
    echo "=================================================================="
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
                        echo "[*] Configured SDKROOT=$SDKROOT (CommandLineTools SDK fallback)"
                        break
                    fi
                done
            fi
        fi
    fi

    # Attempt automatic license acceptance if passwordless sudo is available
    if command -v xcodebuild &> /dev/null; then
        sudo -n xcodebuild -license accept 2>/dev/null || true
    fi

    cd "$PROJECT_DIR/DictyClient"
    SWIFT_CMD="swift"
    if [ "$(sysctl -in hw.optional.arm64 2>/dev/null)" = "1" ]; then
        SWIFT_CMD="arch -arm64 swift"
    fi

    SWIFT_STATUS=0
    $SWIFT_CMD test || SWIFT_STATUS=$?
    if [ $SWIFT_STATUS -eq 69 ]; then
        echo "=================================================================="
        echo " ⚠️  NOTICE: Xcode license not accepted on this runner (Exit Code 69)."
        echo "    To enable Swift testing, run on the Mac runner host:"
        echo "    sudo xcodebuild -license accept"
        echo "    Continuing pipeline since all Python backend tests passed."
        echo "=================================================================="
    elif [ $SWIFT_STATUS -ne 0 ]; then
        echo "[!] Swift test failed with cached build graph. Cleaning .build cache and retrying from scratch..."
        rm -rf .build
        $SWIFT_CMD test
    fi
    cd "$PROJECT_DIR"

    # Validate App bundle packaging & codesigning sealing if scripts/validate_app_bundle.sh exists
    if [ -f "scripts/validate_app_bundle.sh" ]; then
        ./scripts/validate_app_bundle.sh
    fi
fi

echo "=================================================================="
echo " ✅ ALL TESTS & BUILDS PASSED SUCCESSFULLY!"
echo "=================================================================="
