#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs/Lotus-macOS"
APP_BUNDLE="$OUTPUT_DIR/Lotus.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_DIR="$CONTENTS_DIR/backend"

echo "=== Building Lotus for macOS ==="

# 1. Ensure outputs directory
mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BACKEND_DIR"

# 2. Build native macOS OCR and document converter binaries
echo "Compiling native macOS Vision OCR..."
swiftc -O "$ROOT_DIR/work/Lotus/backend/ocr-mac.swift" -o "$ROOT_DIR/work/Lotus/backend/ocr-mac"

echo "Compiling native macOS doc2pdf converter..."
swiftc -O "$ROOT_DIR/work/Lotus/backend/doc2pdf-mac.swift" -o "$ROOT_DIR/work/Lotus/backend/doc2pdf-mac"

# 3. Build Swift Application
echo "Compiling Lotus Swift binary..."
swiftc -O \
    "$ROOT_DIR/work/Lotus-macOS/Models.swift" \
    "$ROOT_DIR/work/Lotus-macOS/PreviewService.swift" \
    "$ROOT_DIR/work/Lotus-macOS/BackendBridge.swift" \
    "$ROOT_DIR/work/Lotus-macOS/TaskIndicatorWindow.swift" \
    "$ROOT_DIR/work/Lotus-macOS/FloatShelfWindow.swift" \
    "$ROOT_DIR/work/Lotus-macOS/ToolWindow.swift" \
    "$ROOT_DIR/work/Lotus-macOS/DropWheelWindow.swift" \
    "$ROOT_DIR/work/Lotus-macOS/main.swift" \
    -o "$MACOS_DIR/Lotus"

# 4. Copy Bundle Info & Icons
echo "Packaging application bundle..."
cp "$ROOT_DIR/work/Lotus-macOS/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$ROOT_DIR/work/Lotus/assets/AppIcon.icns" ]; then
    cp "$ROOT_DIR/work/Lotus/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$ROOT_DIR/work/Lotus/assets/lotus.png" ]; then
    cp "$ROOT_DIR/work/Lotus/assets/lotus.png" "$RESOURCES_DIR/lotus.png"
fi

# 5. Copy Backend scripts
cp -R "$ROOT_DIR/work/Lotus/backend/"* "$BACKEND_DIR/"
find "$BACKEND_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# 6. Make binaries executable
chmod +x "$MACOS_DIR/Lotus"
chmod +x "$BACKEND_DIR/ocr-mac"
chmod +x "$BACKEND_DIR/doc2pdf-mac"

echo "=== Build Complete! ==="
echo "Application created at: $APP_BUNDLE"
