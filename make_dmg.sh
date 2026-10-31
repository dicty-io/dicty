#!/bin/bash
# make_dmg.sh
# Automated end-to-end script to build Dicty backend, frontend, App Bundle, and DMG installer.

set -e

echo "=================================================================="
echo " 🚀 DICTY MACOS DMG BUILD PIPELINE"
echo "=================================================================="

PROJECT_DIR="$(pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${DIST_DIR}/Dicty.app"
DMG_ROOT="${DIST_DIR}/dmg_root"
DMG_FILE="${DIST_DIR}/Dicty.dmg"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

# 1. Clean previous build artifacts
echo "[*] Cleaning old build artifacts for a fresh release build..."
rm -rf "${PROJECT_DIR}/build" "${PROJECT_DIR}/dist"

# 2. Ensure Python virtual environment and build tools exist (cached persistently across runs)
chmod +x scripts/setup_runner_env.sh
./scripts/setup_runner_env.sh

# 2. Compile native whisper.cpp (Metal GPU accelerated)
echo "[*] Compiling native whisper.cpp binaries (Metal GPU acceleration)..."
./scripts/compile_whisper.sh

# 3. Package Python backend using PyInstaller
echo "[*] Packaging Dicty backend executable (PyInstaller)..."
./build_mac.sh

BACKEND_BIN="${DIST_DIR}/dicty_engine"
if [ ! -d "$BACKEND_BIN" ]; then
    echo "[-] Error: Backend directory not found at $BACKEND_BIN"
    exit 1
fi

# 4. Build Swift UI Client in Release Mode
echo "[*] Building Swift UI Client (Release Mode)..."
if [ -z "$DEVELOPER_DIR" ] || [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
    for xcode_path in \
        "/Applications/Xcode.app/Contents/Developer" \
        /Applications/Xcode*.app/Contents/Developer; do
        if [ -d "$xcode_path" ]; then
            export DEVELOPER_DIR="$xcode_path"
            echo "[*] Configured DEVELOPER_DIR=$DEVELOPER_DIR"
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

if command -v xcodebuild &> /dev/null; then
    sudo -n xcodebuild -license accept 2>/dev/null || true
fi

cd "${PROJECT_DIR}/DictyClient"
BUILD_STATUS=0
swift build -c release || BUILD_STATUS=$?
if [ $BUILD_STATUS -eq 69 ]; then
    echo "=================================================================="
    echo " [!] CRITICAL ERROR: Apple Xcode license is not accepted (Exit 69)."
    echo "     To fix this on your Mac runner, run in Terminal:"
    echo "     sudo xcodebuild -license accept"
    echo "     (or launch Xcode.app from Finder and click 'Agree')"
    echo "=================================================================="
    exit 69
elif [ $BUILD_STATUS -ne 0 ]; then
    echo "[!] Swift release build failed with cached build graph. Cleaning .build cache and retrying from scratch..."
    rm -rf .build
    swift build -c release
fi
cd "${PROJECT_DIR}"

SWIFT_BIN="${PROJECT_DIR}/DictyClient/.build/release/Dicty"
if [ ! -f "$SWIFT_BIN" ]; then
    echo "[-] Error: Swift executable not found at $SWIFT_BIN"
    exit 1
fi

# 5. Assemble Dicty.app Bundle Structure
echo "[*] Assembling Dicty.app bundle..."
rm -rf "$APP_DIR" "$DMG_ROOT" "$DMG_FILE"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy Swift frontend executable
cp "$SWIFT_BIN" "${APP_DIR}/Contents/MacOS/Dicty"
chmod +x "${APP_DIR}/Contents/MacOS/Dicty"

# Copy Swift resource bundle (Fixes Bundle.module fatal error crash and exposes assets for Bundle.main)
SWIFT_BUNDLE=$(find "${PROJECT_DIR}/DictyClient/.build" -name "DictyClient_Dicty.bundle" -type d | grep -E "release|Release" | head -n 1)
if [ -n "$SWIFT_BUNDLE" ] && [ -d "$SWIFT_BUNDLE" ]; then
    echo "[*] Copying Swift resource bundle from $SWIFT_BUNDLE..."
    # 1. Copy the bundle folder itself so Bundle.module can find DictyClient_Dicty.bundle
    rm -rf "${APP_DIR}/Contents/Resources/DictyClient_Dicty.bundle"
    cp -R "$SWIFT_BUNDLE" "${APP_DIR}/Contents/Resources/DictyClient_Dicty.bundle"
    
    # Clean up any legacy or rogue bundle symlink at app root (violates macOS codesigning sealing rules)
    rm -rf "${APP_DIR}/DictyClient_Dicty.bundle"
    
    # 2. Also copy assets directly into Contents/Resources so Bundle.main can find them directly
    if [ -d "${SWIFT_BUNDLE}/Contents/Resources" ]; then
        cp -R "${SWIFT_BUNDLE}/Contents/Resources/"* "${APP_DIR}/Contents/Resources/" 2>/dev/null || true
    else
        cp -R "${SWIFT_BUNDLE}/"* "${APP_DIR}/Contents/Resources/" 2>/dev/null || true
    fi
fi

# Copy embedded backend executable directory (from --onedir)
cp -R "${DIST_DIR}/dicty_engine" "${APP_DIR}/Contents/Resources/dicty_engine"

# Generate native macOS AppIcon.icns from 1024x1024 PNG icon
ICON_PNG="${PROJECT_DIR}/DictyClient/Sources/DictyClient/Icon-macOS-Default-1024.png"
if [ -f "$ICON_PNG" ]; then
    echo "[*] Generating native AppIcon.icns..."
    ICONSET_DIR="${DIST_DIR}/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_PNG" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "$ICON_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "$ICON_PNG" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "$ICON_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "$ICON_PNG" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_PNG" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_PNG" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1
    iconutil -c icns "$ICONSET_DIR" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
fi

# Create Info.plist for Dicty.app
cat << EOF > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Dicty</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.Dicty</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Dicty</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${DICTY_VERSION:-1.0.0}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Dicty requires microphone access for voice dictation and audio transcription.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Dicty requires Screen &amp; System Audio Recording access to capture system audio in Meeting Assistant and Focused Meeting modes.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Dicty requires access to Apple Events to pause background media (Music, Spotify, etc.) during voice recording.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.antigravity.Dicty</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>dicty</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Code-signing
ENTITLEMENTS_ARG=""
if [ -f "DictyClient/Dicty.entitlements" ]; then
    ENTITLEMENTS_ARG="--entitlements DictyClient/Dicty.entitlements"
fi

# --- Verify minimum deployment target for bundled Mach-O binaries ---
echo "[*] Verifying minimum macOS deployment target for bundled Mach-O binaries..."
find "${APP_DIR}/Contents" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -111 \) -print0 |
while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
        MIN_OS=$(otool -l "$f" 2>/dev/null | awk '$1=="minos"{print $2}')
        if [ -n "$MIN_OS" ]; then
            MAJOR_VER=$(echo "$MIN_OS" | cut -d. -f1)
            if [ "$MAJOR_VER" -gt 14 ]; then
                echo "[!] Warning: Mach-O $f has minos $MIN_OS (exceeds macOS 14.0 target)"
            fi
        fi
    fi
done

# --- Release path: Apple Developer ID (required for Gatekeeper-friendly public releases) ---
# Set DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
if [ -n "${DEVELOPER_ID_APPLICATION}" ]; then
    echo "[*] Checking Developer ID identity in keychain: ${DEVELOPER_ID_APPLICATION}"
    FIND_ARGS=("-v" "-p" "codesigning")
    if [ -n "${KEYCHAIN_PATH}" ] && [ -f "${KEYCHAIN_PATH}" ]; then
        FIND_ARGS+=("${KEYCHAIN_PATH}")
    fi
    if ! security find-identity "${FIND_ARGS[@]}" 2>/dev/null | grep -q "${DEVELOPER_ID_APPLICATION}"; then
        echo "[-] Error: DEVELOPER_ID_APPLICATION is set ('${DEVELOPER_ID_APPLICATION}'), but matching certificate is not present in keychain (${KEYCHAIN_PATH:-system search list})."
        exit 1
    fi

    echo "[*] Signing with Developer ID: ${DEVELOPER_ID_APPLICATION}"
    # Notarization requires every nested Mach-O to be signed individually (inside-out),
    # with hardened runtime and a secure timestamp. --deep alone is not sufficient.
    SIGN_ARGS=("--force" "--timestamp" "--options" "runtime")
    if [ -n "${KEYCHAIN_PATH}" ] && [ -f "${KEYCHAIN_PATH}" ]; then
        SIGN_ARGS+=("--keychain" "${KEYCHAIN_PATH}")
    fi
    find "${APP_DIR}/Contents" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -111 \) -print0 |
    while IFS= read -r -d '' f; do
        if file "$f" | grep -q "Mach-O"; then
            codesign "${SIGN_ARGS[@]}" ${ENTITLEMENTS_ARG} --sign "${DEVELOPER_ID_APPLICATION}" "$f"
        fi
    done
    codesign "${SIGN_ARGS[@]}" ${ENTITLEMENTS_ARG} --sign "${DEVELOPER_ID_APPLICATION}" "${APP_DIR}"
    codesign --verify --strict --verbose=2 "${APP_DIR}"
    DICTY_SIGNED_WITH_DEVELOPER_ID=1
else
    # --- Local / open-source build: ad-hoc signing ---
    echo "[*] Signing Dicty.app ad-hoc (codesign --sign -)..."
    codesign --force --deep --options runtime ${ENTITLEMENTS_ARG} --sign - "${APP_DIR}"
fi

echo "[+] Dicty.app bundle assembled and signed successfully!"

# 6. Create Premium Studio-Grade macOS DMG Installer Window
echo "[*] Generating minimalist DMG background graphic..."
./.venv/bin/python3 -c '
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

os.makedirs("dist", exist_ok=True)
width, height = 660, 420

# 1. Dark minimalist canvas (#131418 -> #0F1013)
img = Image.new("RGBA", (width, height), (19, 20, 24, 255))
draw = ImageDraw.Draw(img)

for y in range(height):
    ratio = y / height
    r = int(22 - 6 * ratio)
    g = int(24 - 7 * ratio)
    b = int(28 - 8 * ratio)
    draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

# Subtle ambient glow
glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow)
glow_draw.ellipse([width//2 - 200, height//2 - 140, width//2 + 200, height//2 + 100], fill=(135, 185, 150, 18))
glow = glow.filter(ImageFilter.GaussianBlur(radius=60))
img = Image.alpha_composite(img, glow)

# Create overlay layer for bright label pills and icon cards
overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
overlay_draw = ImageDraw.Draw(overlay)

# Icon centers: Dicty at (180, 175), Applications at (480, 175)
for cx, w_pill in [(180, 90), (480, 130)]:
    # Sleek frosted pedestal container
    overlay_draw.rounded_rectangle(
        [cx - 85, 85, cx + 85, 285],
        radius=22,
        fill=(255, 255, 255, 14),
        outline=(255, 255, 255, 30),
        width=1
    )
    
    # Bright high-contrast label pill behind the text
    overlay_draw.rounded_rectangle(
        [cx - w_pill // 2, 245, cx + w_pill // 2, 275],
        radius=8,
        fill=(255, 255, 255, 240),
        outline=(255, 255, 255, 255),
        width=1
    )

img = Image.alpha_composite(img, overlay)
draw = ImageDraw.Draw(img)

# Bottom minimalist instruction
font = None
for fp in ["/System/Library/Fonts/SFProText-Regular.otf", "/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/Supplemental/Arial.ttf"]:
    if os.path.exists(fp):
        try:
            font = ImageFont.truetype(fp, 13)
            break
        except Exception:
            continue

caption = "Drag Dicty to Applications to install"
if font:
    bbox = draw.textbbox((0, 0), caption, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((width - tw) // 2, 345), caption, fill=(255, 255, 255, 180), font=font)

img.save("dist/dmg_background.png", "PNG")
'

echo "[*] Assembling premium styled DMG volume..."
TEMP_DMG="${DIST_DIR}/temp.dmg"

rm -rf "$TEMP_DMG" "$DMG_FILE"

# Clean up any lingering Dicty volumes from previous runs
for lingering in $(mount | awk '/\/Volumes\/Dicty/{print $3}'); do
    echo "[*] Cleaning up lingering volume at $lingering..."
    hdiutil detach "$lingering" -force 2>/dev/null || umount -f "$lingering" 2>/dev/null || true
done

# Calculate actual size needed with safety margin (in megabytes)
APP_SIZE_MB=$(du -sm "$APP_DIR" | awk '{print $1}')
DMG_SIZE_MB=$((APP_SIZE_MB + 150))
echo "[*] App bundle size: ${APP_SIZE_MB}MB -> creating temporary DMG volume of ${DMG_SIZE_MB}MB..."

# Create temporary writable HFS+ disk image
hdiutil create -size "${DMG_SIZE_MB}m" -volname "Dicty" -fs HFS+ -fsargs "-c c=64,a=16,e=16" "$TEMP_DMG"

# Attach with -nobrowse to prevent Spotlight/Finder from locking files during creation
ATTACH_OUT=$(hdiutil attach "$TEMP_DMG" -readwrite -nobrowse -noverify -noautoopen)
DEV_NODE=$(echo "$ATTACH_OUT" | awk '/Apple_HFS/{print $1; exit}')
if [ -z "$DEV_NODE" ]; then
    DEV_NODE=$(echo "$ATTACH_OUT" | awk 'NR==1{print $1}')
fi
MOUNT_DIR=$(echo "$ATTACH_OUT" | awk '/Apple_HFS/{for (i=3; i<=NF; i++) printf "%s%s", $i, (i==NF ? "" : " "); print ""; exit}')

if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "[-] Error: Failed to determine mountpoint for $TEMP_DMG"
    echo "$ATTACH_OUT"
    exit 1
fi
echo "[+] Attached temporary volume at $MOUNT_DIR (device: $DEV_NODE)"

# Copy App bundle and Applications symlink
cp -R "$APP_DIR" "${MOUNT_DIR}/Dicty.app"
ln -sf /Applications "${MOUNT_DIR}/Applications"

# Set up hidden background folder
mkdir -p "${MOUNT_DIR}/.background"
cp "${DIST_DIR}/dmg_background.png" "${MOUNT_DIR}/.background/background.png"

# Apply Finder layout styles via AppleScript (Skip in headless CI environments)
if [ -z "$CI" ] && [ -z "$GITHUB_ACTIONS" ]; then
    VOL_NAME=$(basename "$MOUNT_DIR")
    echo "[*] Applying Finder window layout and positioning via AppleScript on $VOL_NAME..."
    osascript << EOF
    tell application "Finder"
        tell disk "$VOL_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {300, 150, 960, 570}
            set opts to the icon view options of container window
            set icon size of opts to 128
            set text size of opts to 13
            set arrangement of opts to not arranged
            set background picture of opts to file ".background:background.png"
            set position of item "Dicty.app" of container window to {180, 175}
            set position of item "Applications" of container window to {480, 175}
            update without registering applications
            delay 2
            close
        end tell
    end tell
EOF
else
    echo "[*] Skipping Finder AppleScript layout (Running in headless CI environment)..."
fi

sync
sleep 2

# Detach temporary volume cleanly with multi-tier fallback
DETACHED=false
for i in {1..10}; do
    echo "[*] Detaching temporary volume (attempt $i)..."
    if [ -n "$DEV_NODE" ] && hdiutil detach "$DEV_NODE" -force 2>/dev/null; then
        DETACHED=true
        echo "[+] Volume detached successfully via hdiutil."
        break
    elif [ -n "$DEV_NODE" ] && diskutil unmountDisk force "$DEV_NODE" 2>/dev/null; then
        DETACHED=true
        echo "[+] Volume detached successfully via diskutil unmountDisk."
        break
    elif [ -d "$MOUNT_DIR" ] && umount -f "$MOUNT_DIR" 2>/dev/null; then
        [ -n "$DEV_NODE" ] && hdiutil detach "$DEV_NODE" -force 2>/dev/null || true
        DETACHED=true
        echo "[+] Volume detached successfully via umount -f."
        break
    fi
    sleep 2
done

if [ "$DETACHED" != "true" ]; then
    echo "[-] Error: Failed to detach temporary DMG volume."
    hdiutil info | grep -A 5 -B 2 temp.dmg || true
    exit 1
fi

# Compress writable image into final read-only DMG
echo "[*] Compressing final DMG installer..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_FILE"
rm -rf "$TEMP_DMG" "$DMG_ROOT"

# Sign + notarize + staple the DMG (release path only).
# Credentials: either NOTARY_KEYCHAIN_PROFILE (from `xcrun notarytool store-credentials`)
# or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (app-specific password).
if [ "${DICTY_SIGNED_WITH_DEVELOPER_ID:-0}" = "1" ]; then
    DMG_SIGN_ARGS=("--force" "--timestamp")
    if [ -n "${KEYCHAIN_PATH}" ] && [ -f "${KEYCHAIN_PATH}" ]; then
        DMG_SIGN_ARGS+=("--keychain" "${KEYCHAIN_PATH}")
    fi
    codesign "${DMG_SIGN_ARGS[@]}" --sign "${DEVELOPER_ID_APPLICATION}" "$DMG_FILE"
    NOTARY_ARGS=""
    if [ -n "${NOTARY_KEYCHAIN_PROFILE}" ]; then
        NOTARY_ARGS="--keychain-profile ${NOTARY_KEYCHAIN_PROFILE}"
    elif [ -n "${APPLE_ID}" ] && [ -n "${APPLE_TEAM_ID}" ] && [ -n "${APPLE_APP_PASSWORD}" ]; then
        NOTARY_ARGS="--apple-id ${APPLE_ID} --team-id ${APPLE_TEAM_ID} --password ${APPLE_APP_PASSWORD}"
    fi
    if [ -n "$NOTARY_ARGS" ]; then
        echo "[*] Submitting DMG for Apple notarization (this can take a few minutes)..."
        xcrun notarytool submit "$DMG_FILE" ${NOTARY_ARGS} --wait
        xcrun stapler staple "$DMG_FILE"
        spctl --assess --type open --context context:primary-signature -v "$DMG_FILE" || true
        echo "[+] DMG notarized and stapled."
    else
        echo "[!] Notarization credentials not set; DMG is signed but NOT notarized."
    fi
fi

echo "=================================================================="
echo " 🎉 BUILD SUCCESSFUL!"
echo " 📦 Premium DMG Installer Created: ${DMG_FILE}"
echo "=================================================================="
