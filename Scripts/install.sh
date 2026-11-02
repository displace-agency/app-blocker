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

# Create empty app blocklist (preserve existing)
if [ ! -f /etc/focusguard/appBlocked.txt ]; then
    : > /etc/focusguard/appBlocked.txt
    echo "  Created empty app blocklist"
fi

# Create default config (preserve existing; daemon migrates fields on startup)
if [ ! -f /etc/focusguard/config.json ]; then
    echo '{"version":2,"unlockDelay":1200,"maxUnlocksPerDay":2,"cooldownDuration":900,"appCheckInterval":10,"schedules":[]}' > /etc/focusguard/config.json
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

# Load daemon and verify it reaches running state
BOOTSTRAP_OUT="$(launchctl bootstrap system /Library/LaunchDaemons/com.focusguard.blocker.plist 2>&1)"
if [ -n "$BOOTSTRAP_OUT" ]; then
    echo "  launchctl bootstrap: $BOOTSTRAP_OUT"
fi
RUNNING=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    if launchctl print system/com.focusguard.blocker 2>/dev/null | grep -q "state = running"; then
        RUNNING=1; break
    fi
    sleep 1
done
if [ "$RUNNING" -eq 1 ]; then
    echo "  Daemon installed and running"
else
    echo "  ERROR: Daemon failed to start. Check /var/log/focusguard.launchd.log"
    exit 1
fi

# Browser policy (Brave Tor off, Brave/Chrome DoH off, URLBlocklist) comes from the
# configuration profile built by Scripts/make-browser-profile.sh. A `defaults write`
# to /Library/Managed Preferences is a silent no-op on modern macOS, so none here.

echo ""
echo "Installing menu bar app..."
# Remove existing app if present
rm -rf /Applications/FocusGuard.app
cp -R "$BUILD_DIR/FocusGuard.app" /Applications/
chown -R root:wheel /Applications/FocusGuard.app
echo "  App installed to /Applications/FocusGuard.app"

# Login agent: the menu-bar app starts at every login and relaunches if it quits,
# so unlock notifications always have a sender.
cp "$BUILD_DIR/daemon/com.focusguard.app.plist" /Library/LaunchAgents/com.focusguard.app.plist
chown root:wheel /Library/LaunchAgents/com.focusguard.app.plist
chmod 644 /Library/LaunchAgents/com.focusguard.app.plist
CONSOLE_UID="$(stat -f%u /dev/console)"
launchctl bootout "gui/$CONSOLE_UID/com.focusguard.app" 2>/dev/null || true
launchctl bootstrap "gui/$CONSOLE_UID" /Library/LaunchAgents/com.focusguard.app.plist 2>/dev/null || true
echo "  Menu bar app set to start at login"

echo ""
echo "================================================"
echo "  FocusGuard is installed and ACTIVE!"
echo "================================================"
echo ""
echo "  Menu bar app: starts at login (login agent com.focusguard.app)"
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
echo "    5. sudo launchctl bootout gui/\$(id -u)/com.focusguard.app; sudo rm /Library/LaunchAgents/com.focusguard.app.plist"
echo "    6. sudo rm -rf /Applications/FocusGuard.app"
echo "    7. sudo sed -i '' '/FOCUSGUARD-START/,/FOCUSGUARD-END/d' /etc/hosts"
echo "    8. sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
echo ""

# The login agent already started the app; open it only if it is not running.
pgrep -x FocusGuard >/dev/null || open /Applications/FocusGuard.app
