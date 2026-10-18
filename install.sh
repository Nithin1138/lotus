#!/usr/bin/env bash
set -eo pipefail

# ==============================================================================
#  DropDial Universal macOS Installer
#  One-line install:
#    curl -fsSL https://raw.githubusercontent.com/Nithin1138/lotus/advance-features/install.sh | bash
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[32m"
ORANGE="\033[33m"
CYAN="\033[36m"
GRAY="\033[90m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}"
echo "  ╔════════════════════════════════════════════════════════════════════╗"
echo "  ║                       DropDial for macOS                           ║"
echo "  ║            Drag. Drop. Convert. • Universal Desktop Actions        ║"
echo "  ╚════════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# 1. Verify macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${ORANGE}Error: DropDial macOS installer can only be run on macOS.${RESET}"
    exit 1
fi

ARCH="$(uname -m)"
echo -e "${GRAY}→ Detected macOS (${ARCH})${RESET}"

# 2. Determine target installation path
TARGET_APP="/Applications/DropDial.app"
if [ ! -w "/Applications" ]; then
    if [ -d "$HOME/Applications" ] || mkdir -p "$HOME/Applications" 2>/dev/null; then
        TARGET_APP="$HOME/Applications/DropDial.app"
    fi
fi
echo -e "${GRAY}→ Target destination: ${TARGET_APP}${RESET}"

# 3. Terminate running DropDial instance if any
if pgrep -x "DropDial" > /dev/null 2>&1; then
    echo -e "${GRAY}→ Stopping running DropDial process...${RESET}"
    killall "DropDial" 2>/dev/null || true
    sleep 0.5
fi

# 4. Locate or compile DropDial.app
SOURCE_APP=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/build-mac.sh" ]; then
    echo -e "${GRAY}→ Running from local repository: ${SCRIPT_DIR}${RESET}"
    if [ ! -d "$SCRIPT_DIR/outputs/DropDial-macOS/DropDial.app" ]; then
        echo -e "${CYAN}→ Building DropDial natively...${RESET}"
        (cd "$SCRIPT_DIR" && ./build-mac.sh)
    fi
    SOURCE_APP="$SCRIPT_DIR/outputs/DropDial-macOS/DropDial.app"
fi

if [ -z "$SOURCE_APP" ] || [ ! -d "$SOURCE_APP" ]; then
    TMP_DIR="$(mktemp -d /tmp/dropdial-install.XXXXXX)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    # Try downloading latest release asset if available
    DOWNLOAD_SUCCESS=0
    RELEASE_URL="https://github.com/Nithin1138/lotus/releases/latest/download/DropDial-macOS.zip"
    echo -e "${GRAY}→ Checking for prebuilt release asset...${RESET}"
    if curl -fsSL -I "$RELEASE_URL" >/dev/null 2>&1; then
        echo -e "${CYAN}→ Downloading prebuilt DropDial...${RESET}"
        if curl -fsSL "$RELEASE_URL" -o "$TMP_DIR/DropDial-macOS.zip" 2>/dev/null; then
            ditto -x -k "$TMP_DIR/DropDial-macOS.zip" "$TMP_DIR/"
            if [ -d "$TMP_DIR/DropDial.app" ]; then
                SOURCE_APP="$TMP_DIR/DropDial.app"
                DOWNLOAD_SUCCESS=1
            fi
        fi
    fi

    # Fallback: clone shallowly & compile natively with swiftc (takes ~5s)
    if [ "$DOWNLOAD_SUCCESS" -eq 0 ]; then
        echo -e "${CYAN}→ Building from source repository (zero dependencies, ~5 seconds)...${RESET}"
        git clone --depth 1 -b advance-features https://github.com/Nithin1138/lotus.git "$TMP_DIR/lotus" >/dev/null 2>&1
        (cd "$TMP_DIR/lotus" && ./build-mac.sh >/dev/null 2>&1)
        SOURCE_APP="$TMP_DIR/lotus/outputs/DropDial-macOS/DropDial.app"
    fi
fi

if [ ! -d "$SOURCE_APP" ]; then
    echo -e "${ORANGE}Failed to find or build DropDial.app. Please check your internet connection or install Xcode Command Line Tools: xcode-select --install${RESET}"
    exit 1
fi

# 5. Install to /Applications
echo -e "${CYAN}→ Installing to ${TARGET_APP}...${RESET}"
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

# 6. Smooth Gatekeeper & Security Setup
echo -e "${GRAY}→ Stripping quarantine & signing ad-hoc for Gatekeeper...${RESET}"
xattr -cr "$TARGET_APP" 2>/dev/null || true
codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true

# 7. Check Accessibility status
IS_TRUSTED=0
if swift -e 'import ApplicationServices; exit(AXIsProcessTrusted() ? 0 : 1)' >/dev/null 2>&1; then
    IS_TRUSTED=1
fi

echo ""
echo -e "${GREEN}${BOLD}✓ DropDial installed successfully!${RESET}"
echo ""

if [ "$IS_TRUSTED" -eq 1 ]; then
    echo -e "${GREEN}✓ Accessibility permission is already active.${RESET}"
else
    echo -e "${ORANGE}${BOLD}Accessibility Permission Recommended:${RESET}"
    echo -e "  To detect modifier keys (${BOLD}⇧ Shift${RESET}, ${BOLD}⌘ Cmd${RESET}, ${BOLD}⌃ Ctrl${RESET}) while dragging files"
    echo -e "  from Finder, macOS requires Accessibility permission."
    echo -e "  ${CYAN}Opening System Settings > Privacy & Security > Accessibility...${RESET}"
    echo -e "  Simply toggle ${BOLD}DropDial${RESET} to ${BOLD}ON${RESET}."
    echo ""
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
fi

# 8. Launch DropDial
echo -e "${CYAN}→ Launching DropDial...${RESET}"
open "$TARGET_APP"

echo ""
echo -e "${BOLD}Keyboard Shortcuts & Controls:${RESET}"
echo -e "  • ${BOLD}⇧ Shift + Drag File${RESET}  : Open Formats Wheel (Conversions)"
echo -e "  • ${BOLD}⌘ Cmd + Drag File${RESET}    : Open Tools Wheel (Media & PDF Tools)"
echo -e "  • ${BOLD}⌃ Ctrl + Drag File${RESET}   : Open Actions Wheel (AirDrop, Shelf, Paths)"
echo -e "  • ${BOLD}F8 / F9 / F10 / ⌥Space${RESET} : HotKey shortcuts (work without permissions!)"
echo -e "  • ${BOLD}Menu Bar Icon${RESET}        : Drag any file directly onto the menu bar icon"
echo ""
echo -e "${GREEN}Enjoy DropDial!${RESET}"
