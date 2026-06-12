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

TMPSCRIPT=$(mktemp /tmp/focusguard-update.XXXXXX.sh)
cat > "$TMPSCRIPT" << ENDSCRIPT
#!/bin/bash
set -e

# Step 1: Remove ALL immutable flags first
chflags -R noschg /Applications/FocusGuard.app 2>/dev/null || true
chflags -R noschg /usr/local/bin/focusguard-daemon 2>/dev/null || true
chflags -R noschg /Library/LaunchDaemons/com.focusguard.blocker.plist 2>/dev/null || true
chflags -R noschg /etc/focusguard 2>/dev/null || true
chflags noschg /etc/hosts 2>/dev/null || true

# Step 2: Stop running instances
killall FocusGuard 2>/dev/null || true
launchctl bootout system/com.focusguard.blocker 2>/dev/null || true
sleep 1

# Step 3: Update daemon binary
cp "$BUILD_DIR/daemon/focusguard-daemon" /usr/local/bin/focusguard-daemon
chmod 755 /usr/local/bin/focusguard-daemon

# Step 4: Update app
rm -rf /Applications/FocusGuard.app
cp -R "$BUILD_DIR/FocusGuard.app" /Applications/

# Step 5: Ensure config + data files exist (daemon migrates config fields itself)
mkdir -p /etc/focusguard
if [ ! -f /etc/focusguard/blocked.txt ]; then
    cp "$BUILD_DIR/daemon/default-blocked.txt" /etc/focusguard/blocked.txt
fi
if [ ! -f /etc/focusguard/appBlocked.txt ]; then
    : > /etc/focusguard/appBlocked.txt
fi
if [ ! -f /etc/focusguard/config.json ]; then
    echo '{"version":2,"unlockDelay":1200,"maxUnlocksPerDay":2,"cooldownDuration":900,"appCheckInterval":10,"schedules":[]}' > /etc/focusguard/config.json
fi

# Trim an oversized legacy log so it does not linger forever
if [ -f /var/log/focusguard.log ] && [ "\$(stat -f%z /var/log/focusguard.log 2>/dev/null || echo 0)" -gt 5242880 ]; then
    : > /var/log/focusguard.log
fi

# Step 6: Install plist
cp "$BUILD_DIR/daemon/com.focusguard.blocker.plist" /Library/LaunchDaemons/
chown root:wheel /Library/LaunchDaemons/com.focusguard.blocker.plist
chmod 644 /Library/LaunchDaemons/com.focusguard.blocker.plist

# Step 7: Chrome policy
mkdir -p "/Library/Managed Preferences"
defaults write "/Library/Managed Preferences/com.google.Chrome" DnsOverHttpsMode -string "off"

# Step 8: Start daemon via launchd (no unmanaged direct-launch fallback -- a
# detached process would fight launchd's KeepAlive).
launchctl bootout system/com.focusguard.blocker 2>/dev/null || true
BOOTSTRAP_OUT="\$(launchctl bootstrap system /Library/LaunchDaemons/com.focusguard.blocker.plist 2>&1)"
if [ -n "\$BOOTSTRAP_OUT" ]; then
    echo "launchctl bootstrap: \$BOOTSTRAP_OUT"
fi

# Verify the daemon is actually running under launchd (retry up to 10s)
RUNNING=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    if launchctl print system/com.focusguard.blocker 2>/dev/null | grep -q "state = running"; then
        RUNNING=1
        break
    fi
    sleep 1
done
if [ "\$RUNNING" -eq 1 ]; then
    echo "Daemon is running."
else
    echo "ERROR: Daemon failed to reach running state. Check /var/log/focusguard.launchd.log"
    exit 1
fi
ENDSCRIPT

chmod +x "$TMPSCRIPT"

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
