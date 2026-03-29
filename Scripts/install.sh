#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

echo "=== FocusGuard Installer ==="
echo ""

# Must be root
if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo:"
    echo "  sudo bash Scripts/install.sh"
    exit 1
fi

# Check build exists
if [ ! -f "$BUILD_DIR/daemon/focusguard-daemon" ] || [ ! -d "$BUILD_DIR/FocusGuard.app" ]; then
    echo "Build not found. Run Scripts/build.sh first."
    exit 1
fi

echo "Installing daemon..."

# Create config directory
mkdir -p /etc/focusguard

# Install daemon binary
cp "$BUILD_DIR/daemon/focusguard-daemon" /usr/local/bin/focusguard-daemon
chmod 755 /usr/local/bin/focusguard-daemon

# Copy blocked list (preserve existing)
if [ ! -f /etc/focusguard/blocked.txt ]; then
    cp "$BUILD_DIR/daemon/default-blocked.txt" /etc/focusguard/blocked.txt
    echo "  Installed default blocklist (YouTube)"
else
    echo "  Keeping existing blocklist"
fi

# Create default config (preserve existing)
if [ ! -f /etc/focusguard/config.json ]; then
    echo '{"unlockDelay": 1200, "maxUnlocksPerDay": 2, "cooldownDuration": 900}' > /etc/focusguard/config.json
    echo "  Created default config (20-minute unlock delay)"
else
    echo "  Keeping existing config"
fi

# Unload existing daemon if present
launchctl bootout system/com.focusguard.blocker 2>/dev/null || true

# Install LaunchDaemon plist
cp "$BUILD_DIR/daemon/com.focusguard.blocker.plist" /Library/LaunchDaemons/
chown root:wheel /Library/LaunchDaemons/com.focusguard.blocker.plist
chmod 644 /Library/LaunchDaemons/com.focusguard.blocker.plist

# Load daemon
launchctl bootstrap system /Library/LaunchDaemons/com.focusguard.blocker.plist
echo "  Daemon installed and running"

echo ""
echo "Installing Chrome policy (disable Secure DNS)..."
mkdir -p "/Library/Managed Preferences"
defaults write "/Library/Managed Preferences/com.google.Chrome" DnsOverHttpsMode -string "off"
echo "  Chrome Secure DNS disabled"

echo ""
echo "Installing menu bar app..."
# Remove existing app if present
rm -rf /Applications/FocusGuard.app
cp -R "$BUILD_DIR/FocusGuard.app" /Applications/
chown -R root:wheel /Applications/FocusGuard.app
echo "  App installed to /Applications/FocusGuard.app"

echo ""
echo "================================================"
echo "  FocusGuard is installed and ACTIVE!"
echo "================================================"
echo ""
echo "  Menu bar app: Open from /Applications/FocusGuard.app"
echo "  Daemon: Running in background (survives reboots)"
echo ""
echo "  The menu bar icon (shield) appears in your menu bar."
echo "  Click it to manage blocked sites and unlock."
echo ""
echo "  To uninstall (the hard way):"
echo "    1. sudo launchctl bootout system/com.focusguard.blocker"
echo "    2. sudo rm /Library/LaunchDaemons/com.focusguard.blocker.plist"
echo "    3. sudo rm /usr/local/bin/focusguard-daemon"
echo "    4. sudo rm -rf /etc/focusguard"
echo "    5. sudo rm -rf /Applications/FocusGuard.app"
echo "    6. sudo sed -i '' '/FOCUSGUARD-START/,/FOCUSGUARD-END/d' /etc/hosts"
echo "    7. sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
echo "    8. sudo defaults delete '/Library/Managed Preferences/com.google.Chrome' DnsOverHttpsMode"
echo ""

# Open the app
open /Applications/FocusGuard.app
