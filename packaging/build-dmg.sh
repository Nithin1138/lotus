#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs/DropDial-macOS"
APP_BUNDLE="$OUTPUT_DIR/DropDial.app"
DMG_FILE="$OUTPUT_DIR/DropDial.dmg"
DMG_STAGE="$OUTPUT_DIR/dmg_staging"
DMG_TEMP="$OUTPUT_DIR/DropDial-temp.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: Application bundle not found at $APP_BUNDLE"
    exit 1
fi

echo "=== Packaging DropDial DMG with HiDPI Retina Dark Theme & Zero Overlap ==="

# 1. Clean existing staging & unmount any old DropDial volumes
rm -rf "$DMG_STAGE" "$DMG_TEMP" "$DMG_FILE"
for dev in $(diskutil list | grep -B 2 "DropDial" | grep -oE "/dev/disk[0-9]+" || true); do
    diskutil eject "$dev" >/dev/null 2>&1 || true
done
for v in /Volumes/*DropDial*; do
    diskutil unmount force "$v" >/dev/null 2>&1 || true
done
mkdir -p "$DMG_STAGE/.background"

# 2. Generate HiDPI Retina DMG background artwork (1x + 2x combined into background.tiff)
python3 "$ROOT_DIR/packaging/generate-dmg-background.py" "$DMG_STAGE/.background"

# 3. Copy application bundle & create Applications symlink
echo "Copying application and creating Applications shortcut..."
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

# 4. Create Read-Write DMG to configure layout with AppleScript
echo "Creating temporary disk image for layout..."
hdiutil create -srcfolder "$DMG_STAGE" -volname "DropDial" -format UDRW -size 120M "$DMG_TEMP" >/dev/null

echo "Mounting disk image..."
ATTACH_OUT=$(hdiutil attach -readwrite -noautoopen "$DMG_TEMP")
DEV_NODE=$(echo "$ATTACH_OUT" | grep -E '^/dev/' | head -n 1 | awk '{print $1}')
echo "Mounted at device: $DEV_NODE"

# Ensure volume is ready
sleep 1

# Check which background file exists (prefer background.tiff, fallback to background.png)
BG_NAME="background.tiff"
if [ ! -f "/Volumes/DropDial/.background/background.tiff" ]; then
    BG_NAME="background.png"
fi

echo "Applying Finder layout, HiDPI background artwork ($BG_NAME), and icon positioning..."
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "DropDial"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {150, 100, 830, 540} -- 680 x 440 size
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set text size of viewOptions to 11
        set bgFile to POSIX file "/Volumes/DropDial/.background/$BG_NAME" as alias
        set background picture of viewOptions to bgFile
        set position of item "DropDial.app" of container window to {160, 105}
        set position of item "Applications" of container window to {520, 105}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

# Sync and unmount
echo "Detaching layout disk image..."
sync || true
sleep 1
diskutil eject "$DEV_NODE" >/dev/null 2>&1 || hdiutil detach "$DEV_NODE" -force >/dev/null 2>&1 || true

# 6. Convert to compressed UDZO DMG
echo "Compressing final production DMG..."
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FILE" >/dev/null
rm -f "$DMG_TEMP"
rm -rf "$DMG_STAGE"

# Also update website copy
if [ -d "$ROOT_DIR/website/downloads" ]; then
    cp "$DMG_FILE" "$ROOT_DIR/website/downloads/DropDial.dmg"
fi

echo "=== DMG Packaging Complete! ==="
echo "DMG File: $DMG_FILE"
ls -lh "$DMG_FILE"
