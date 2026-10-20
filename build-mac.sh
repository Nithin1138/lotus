#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs/DropDial-macOS"
APP_BUNDLE="$OUTPUT_DIR/DropDial.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_DIR="$CONTENTS_DIR/backend"

echo "=== Building DropDial for macOS ==="

# 1. Ensure outputs directory
mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BACKEND_DIR"

# 2. Build native macOS OCR and document converter binaries
echo "Compiling native macOS Vision OCR (Universal: arm64 + x86_64)..."
swiftc -target arm64-apple-macos12.0 -O "$ROOT_DIR/work/DropDial/backend/ocr-mac.swift" -o "$ROOT_DIR/work/DropDial/backend/ocr-mac-arm64" 2>/dev/null || true
swiftc -target x86_64-apple-macos12.0 -O "$ROOT_DIR/work/DropDial/backend/ocr-mac.swift" -o "$ROOT_DIR/work/DropDial/backend/ocr-mac-x86_64" 2>/dev/null || true
if [ -f "$ROOT_DIR/work/DropDial/backend/ocr-mac-arm64" ] && [ -f "$ROOT_DIR/work/DropDial/backend/ocr-mac-x86_64" ]; then
    lipo -create "$ROOT_DIR/work/DropDial/backend/ocr-mac-arm64" "$ROOT_DIR/work/DropDial/backend/ocr-mac-x86_64" -output "$ROOT_DIR/work/DropDial/backend/ocr-mac"
    rm -f "$ROOT_DIR/work/DropDial/backend/ocr-mac-arm64" "$ROOT_DIR/work/DropDial/backend/ocr-mac-x86_64"
else
    swiftc -O "$ROOT_DIR/work/DropDial/backend/ocr-mac.swift" -o "$ROOT_DIR/work/DropDial/backend/ocr-mac"
fi

echo "Compiling native macOS doc2pdf converter (Universal: arm64 + x86_64)..."
swiftc -target arm64-apple-macos12.0 -O "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac.swift" -o "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-arm64" 2>/dev/null || true
swiftc -target x86_64-apple-macos12.0 -O "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac.swift" -o "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-x86_64" 2>/dev/null || true
if [ -f "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-arm64" ] && [ -f "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-x86_64" ]; then
    lipo -create "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-arm64" "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-x86_64" -output "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac"
    rm -f "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-arm64" "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac-x86_64"
else
    swiftc -O "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac.swift" -o "$ROOT_DIR/work/DropDial/backend/doc2pdf-mac"
fi

# 3. Build Swift Application
echo "Compiling DropDial Swift binary (Universal: arm64 + x86_64)..."
SWIFT_SOURCES=(
    "$ROOT_DIR/work/DropDial-macOS/Models.swift"
    "$ROOT_DIR/work/DropDial-macOS/PreviewService.swift"
    "$ROOT_DIR/work/DropDial-macOS/BackendBridge.swift"
    "$ROOT_DIR/work/DropDial-macOS/TaskIndicatorWindow.swift"
    "$ROOT_DIR/work/DropDial-macOS/FloatShelfWindow.swift"
    "$ROOT_DIR/work/DropDial-macOS/ToolWindow.swift"
    "$ROOT_DIR/work/DropDial-macOS/DropWheelWindow.swift"
    "$ROOT_DIR/work/DropDial-macOS/PermissionWelcomeWindow.swift"
    "$ROOT_DIR/work/DropDial-macOS/UpdateService.swift"
    "$ROOT_DIR/work/DropDial-macOS/LicenseManager.swift"
    "$ROOT_DIR/work/DropDial-macOS/main.swift"
)
swiftc -target arm64-apple-macos12.0 -O "${SWIFT_SOURCES[@]}" -o "$MACOS_DIR/DropDial-arm64" 2>/dev/null || true
swiftc -target x86_64-apple-macos12.0 -O "${SWIFT_SOURCES[@]}" -o "$MACOS_DIR/DropDial-x86_64" 2>/dev/null || true
if [ -f "$MACOS_DIR/DropDial-arm64" ] && [ -f "$MACOS_DIR/DropDial-x86_64" ]; then
    lipo -create "$MACOS_DIR/DropDial-arm64" "$MACOS_DIR/DropDial-x86_64" -output "$MACOS_DIR/DropDial"
    rm -f "$MACOS_DIR/DropDial-arm64" "$MACOS_DIR/DropDial-x86_64"
else
    swiftc -O "${SWIFT_SOURCES[@]}" -o "$MACOS_DIR/DropDial"
fi

# 4. Copy Bundle Info & Icons
echo "Packaging application bundle..."
cp "$ROOT_DIR/work/DropDial-macOS/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$ROOT_DIR/work/DropDial/assets/AppIcon.icns" ]; then
    cp "$ROOT_DIR/work/DropDial/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$ROOT_DIR/work/DropDial/assets/dropdial.png" ]; then
    cp "$ROOT_DIR/work/DropDial/assets/dropdial.png" "$RESOURCES_DIR/dropdial.png"
fi
for icon in "$ROOT_DIR/work/DropDial/assets/StatusBarIcon"*.png "$ROOT_DIR/work/DropDial/assets/dropdial_mark"*.png; do
    if [ -f "$icon" ]; then
        cp "$icon" "$RESOURCES_DIR/"
    fi
done

# Copy License and Third-Party Notices into bundle resources
python3 "$ROOT_DIR/work/make-notices.py" "$ROOT_DIR/THIRD-PARTY-NOTICES.txt" 2>/dev/null || true
if [ -f "$ROOT_DIR/THIRD-PARTY-NOTICES.txt" ]; then
    cp "$ROOT_DIR/THIRD-PARTY-NOTICES.txt" "$RESOURCES_DIR/THIRD-PARTY-NOTICES.txt"
fi
if [ -f "$ROOT_DIR/LICENSE" ]; then
    cp "$ROOT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE"
fi

# 5. Copy Backend scripts
cp -R "$ROOT_DIR/work/DropDial/backend/"* "$BACKEND_DIR/"
find "$BACKEND_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# 5b. Bundle self-contained Python runtime environment (opt-in for self-contained packages)
if [ "${BUNDLE_VENV:-0}" = "1" ] && [ -d "$ROOT_DIR/.venv" ]; then
    echo "Bundling self-contained Python runtime environment..."
    mkdir -p "$CONTENTS_DIR/runtime"
    cp -R "$ROOT_DIR/.venv" "$CONTENTS_DIR/runtime/python"
    find "$CONTENTS_DIR/runtime/python" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
fi

# 6. Make binaries executable
chmod +x "$MACOS_DIR/DropDial"
chmod +x "$BACKEND_DIR/ocr-mac"
chmod +x "$BACKEND_DIR/doc2pdf-mac"
if [ -d "$CONTENTS_DIR/runtime/python/bin" ]; then
    chmod -R +x "$CONTENTS_DIR/runtime/python/bin" 2>/dev/null || true
fi

# 7. Strip quarantine attribute & ad-hoc sign bundle for smooth Gatekeeper launch
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
echo "Signing application bundle (ad-hoc)..."
codesign --force --deep --sign - --identifier com.dropdial.mac "$APP_BUNDLE" 2>/dev/null || true

# 8. Package Distribution Archives (ZIP and DMG)
echo "Packaging distribution archives..."
ZIP_FILE="$OUTPUT_DIR/DropDial-macOS.zip"
rm -f "$ZIP_FILE"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_FILE"

DMG_FILE="$OUTPUT_DIR/DropDial.dmg"
if [ -f "$ROOT_DIR/packaging/build-dmg.sh" ]; then
    bash "$ROOT_DIR/packaging/build-dmg.sh"
else
    DMG_STAGE="$OUTPUT_DIR/dmg_staging"
    rm -rf "$DMG_STAGE" "$DMG_FILE"
    mkdir -p "$DMG_STAGE"
    cp -R "$APP_BUNDLE" "$DMG_STAGE/"
    ln -s /Applications "$DMG_STAGE/Applications"
    echo "Creating DMG..."
    hdiutil create -volname "DropDial" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_FILE" >/dev/null 2>&1 || true
    rm -rf "$DMG_STAGE"
fi

echo "=== Build Complete! ==="
echo "Application created at: $APP_BUNDLE"
echo "ZIP archive: $ZIP_FILE"
if [ -f "$DMG_FILE" ]; then
    echo "DMG disk image: $DMG_FILE"
fi
