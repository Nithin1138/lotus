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

# 4. Create 1-Click Launcher: Open DropDial (First Time).command
LAUNCHER_NAME="Open DropDial (First Time).command"
cat << 'EOF' > "$DMG_STAGE/$LAUNCHER_NAME"
#!/usr/bin/env bash
clear
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                   Welcome to DropDial                        ║"
echo "  ║        Universal Drag & Drop Offline Media Converter         ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  🚀 Starting DropDial First-Time Setup..."
echo ""

APP_PATH="/Applications/DropDial.app"
DMG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMG_APP="$DMG_DIR/DropDial.app"

# 1. If not yet copied to /Applications, copy it automatically
if [ ! -d "$APP_PATH" ]; then
    if [ -d "$DMG_APP" ]; then
        echo "  [1/3] Copying DropDial into /Applications..."
        cp -R "$DMG_APP" /Applications/
    else
        echo "  ❌ DropDial.app was not found in /Applications or disk image."
        exit 1
    fi
else
    echo "  [1/3] Verified DropDial in /Applications."
fi

# 2. Clear Apple Gatekeeper quarantine restriction
echo "  [2/3] Clearing macOS Gatekeeper security restriction..."
xattr -cr "$APP_PATH" 2>/dev/null || true

# 3. Launch application
echo "  [3/3] Launching DropDial..."
open "$APP_PATH"

echo ""
echo "  ✨ DropDial is now open and running!"
echo "  (You can close this terminal window at any time)"
echo ""
sleep 2
exit 0
EOF
chmod +x "$DMG_STAGE/$LAUNCHER_NAME"

# Attach DropDial icon to launcher for clean visual appearance
python3 -c "
from AppKit import NSWorkspace, NSImage
ws = NSWorkspace.sharedWorkspace()
img = NSImage.alloc().initWithContentsOfFile_('$ROOT_DIR/work/DropDial/assets/AppIcon.icns')
if img:
    ws.setIcon_forFile_options_(img, '$DMG_STAGE/$LAUNCHER_NAME', 0)
" 2>/dev/null || true

# 5. Create Read-Write DMG to configure layout with AppleScript
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
        set position of item "Applications" of container window to {500, 105}
        set position of item "$LAUNCHER_NAME" of container window to {120, 315}
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
