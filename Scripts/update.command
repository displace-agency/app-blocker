#!/bin/bash
# Double-click this file to update FocusGuard

clear
echo "================================"
echo "   FocusGuard Updater"
echo "================================"
echo ""

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

if [ ! -f "$BUILD_DIR/daemon/focusguard-daemon" ] || [ ! -d "$BUILD_DIR/FocusGuard.app" ]; then
    echo "ERROR: Build not found. Run build.sh first."
    echo "Press any key to close..."
    read -n 1
    exit 1
fi

echo "This will update FocusGuard (app + daemon)."
echo "You'll be asked for your Mac password."
echo ""

# Write a temp shell script to avoid AppleScript quoting hell
TMPSCRIPT=$(mktemp /tmp/focusguard-update.XXXXXX.sh)
cat > "$TMPSCRIPT" << ENDSCRIPT
#!/bin/bash
set -e

killall FocusGuard 2>/dev/null || true
launchctl bootout system/com.focusguard.blocker 2>/dev/null || true
sleep 1

cp "$BUILD_DIR/daemon/focusguard-daemon" /usr/local/bin/focusguard-daemon
chmod 755 /usr/local/bin/focusguard-daemon

rm -rf /Applications/FocusGuard.app
cp -R "$BUILD_DIR/FocusGuard.app" /Applications/

mkdir -p /etc/focusguard
if [ ! -f /etc/focusguard/blocked.txt ]; then
    cp "$BUILD_DIR/daemon/default-blocked.txt" /etc/focusguard/blocked.txt
fi

echo '{"unlockDelay":1200,"maxUnlocksPerDay":2,"cooldownDuration":900}' > /etc/focusguard/config.json

cp "$BUILD_DIR/daemon/com.focusguard.blocker.plist" /Library/LaunchDaemons/
chown root:wheel /Library/LaunchDaemons/com.focusguard.blocker.plist
chmod 644 /Library/LaunchDaemons/com.focusguard.blocker.plist

mkdir -p "/Library/Managed Preferences"
defaults write "/Library/Managed Preferences/com.google.Chrome" DnsOverHttpsMode -string "off"

launchctl load /Library/LaunchDaemons/com.focusguard.blocker.plist
ENDSCRIPT

chmod +x "$TMPSCRIPT"

# Run the temp script with admin privileges
osascript -e "do shell script \"bash '$TMPSCRIPT'\" with administrator privileges"
RESULT=$?

rm -f "$TMPSCRIPT"

if [ $RESULT -eq 0 ]; then
    echo ""
    echo "FocusGuard updated successfully!"
    echo "Starting app..."
    open /Applications/FocusGuard.app
    echo ""
    echo "Done! You can close this window."
else
    echo ""
    echo "Update cancelled or failed."
fi

echo ""
echo "Press any key to close..."
read -n 1
