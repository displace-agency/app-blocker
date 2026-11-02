#!/bin/bash
# Double-click this file to update FocusGuard (app + daemon + login agent).

clear
echo "================================"
echo "   FocusGuard Updater"
echo "================================"
echo ""

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

if [ ! -f "$BUILD_DIR/daemon/focusguard-daemon" ] || [ ! -d "$BUILD_DIR/FocusGuard.app" ] || [ ! -f "$BUILD_DIR/daemon/com.focusguard.app.plist" ]; then
    echo "ERROR: Build not found or outdated. Run Scripts/build.sh first."
    echo "Press any key to close..."
    read -n 1
    exit 1
fi

echo "This will update FocusGuard (app + daemon)."
echo "Blocking stays on: the old daemon keeps running until the new one is ready,"
echo "and any failure restarts it."
echo "You'll be asked for your Mac password."
echo ""

TMPSCRIPT=$(mktemp /tmp/focusguard-update.XXXXXX.sh)
cat > "$TMPSCRIPT" << ENDSCRIPT
#!/bin/bash
set -e
DAEMON_PLIST=/Library/LaunchDaemons/com.focusguard.blocker.plist
AGENT_PLIST=/Library/LaunchAgents/com.focusguard.app.plist
CONSOLE_UID="\$(stat -f%u /dev/console)"

# If anything fails from here on, bring the blocker (and the app) back up.
recover() {
    echo "Update step failed -- restarting FocusGuard with what is installed."
    launchctl bootstrap system "\$DAEMON_PLIST" 2>/dev/null || true
    [ -f "\$AGENT_PLIST" ] && launchctl bootstrap "gui/\$CONSOLE_UID" "\$AGENT_PLIST" 2>/dev/null || true
}
trap recover ERR

# Step 1: Stage the new build next to the old one (nothing is stopped yet)
chflags -R noschg /Applications/FocusGuard.app 2>/dev/null || true
chflags noschg /usr/local/bin/focusguard-daemon "\$DAEMON_PLIST" 2>/dev/null || true
rm -rf /Applications/FocusGuard.app.new /usr/local/bin/focusguard-daemon.new
cp "$BUILD_DIR/daemon/focusguard-daemon" /usr/local/bin/focusguard-daemon.new
chmod 755 /usr/local/bin/focusguard-daemon.new
cp -R "$BUILD_DIR/FocusGuard.app" /Applications/FocusGuard.app.new

# Step 2: Ensure config + data files exist (daemon migrates config fields itself)
mkdir -p /etc/focusguard
[ -f /etc/focusguard/blocked.txt ] || cp "$BUILD_DIR/daemon/default-blocked.txt" /etc/focusguard/blocked.txt
[ -f /etc/focusguard/appBlocked.txt ] || : > /etc/focusguard/appBlocked.txt
if [ ! -f /etc/focusguard/config.json ]; then
    echo '{"version":2,"unlockDelay":1200,"maxUnlocksPerDay":2,"cooldownDuration":900,"appCheckInterval":10,"schedules":[]}' > /etc/focusguard/config.json
fi
if [ -f /var/log/focusguard.log ] && [ "\$(stat -f%z /var/log/focusguard.log 2>/dev/null || echo 0)" -gt 5242880 ]; then
    : > /var/log/focusguard.log
fi

# Step 3: Stop the app agent and the daemon (one bootout each)
launchctl bootout "gui/\$CONSOLE_UID/com.focusguard.app" 2>/dev/null || true
killall FocusGuard 2>/dev/null || true
launchctl bootout system/com.focusguard.blocker 2>/dev/null || true
sleep 1

# Step 4: Swap in the staged files
mv -f /usr/local/bin/focusguard-daemon.new /usr/local/bin/focusguard-daemon
rm -rf /Applications/FocusGuard.app
mv /Applications/FocusGuard.app.new /Applications/FocusGuard.app

# Step 5: Install launchd plists (daemon + login agent for the menu-bar app)
cp "$BUILD_DIR/daemon/com.focusguard.blocker.plist" "\$DAEMON_PLIST"
chown root:wheel "\$DAEMON_PLIST"; chmod 644 "\$DAEMON_PLIST"
cp "$BUILD_DIR/daemon/com.focusguard.app.plist" "\$AGENT_PLIST"
chown root:wheel "\$AGENT_PLIST"; chmod 644 "\$AGENT_PLIST"

# Browser policy (Brave Tor + DoH off) is a configuration profile, not set here.

# Step 6: Start the daemon and verify it runs
BOOTSTRAP_OUT="\$(launchctl bootstrap system "\$DAEMON_PLIST" 2>&1)" || true
[ -n "\$BOOTSTRAP_OUT" ] && echo "launchctl bootstrap: \$BOOTSTRAP_OUT"
RUNNING=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    if launchctl print system/com.focusguard.blocker 2>/dev/null | grep -q "state = running"; then RUNNING=1; break; fi
    sleep 1
done
if [ "\$RUNNING" -ne 1 ]; then
    echo "ERROR: Daemon failed to reach running state. Check /var/log/focusguard.launchd.log"
    recover
    exit 1
fi
echo "Daemon is running."

# Step 7: Start the menu-bar app as a login agent (runs at every login, relaunches if it quits)
launchctl bootstrap "gui/\$CONSOLE_UID" "\$AGENT_PLIST" 2>/dev/null || launchctl kickstart -k "gui/\$CONSOLE_UID/com.focusguard.app" 2>/dev/null || true
for i in 1 2 3 4 5; do
    if launchctl print "gui/\$CONSOLE_UID/com.focusguard.app" 2>/dev/null | grep -q "state = running"; then echo "App is running (login agent)."; break; fi
    sleep 1
done
trap - ERR
ENDSCRIPT

chmod +x "$TMPSCRIPT"

osascript -e "do shell script \"bash '$TMPSCRIPT'\" with administrator privileges"
RESULT=$?

rm -f "$TMPSCRIPT"

if [ $RESULT -eq 0 ]; then
    echo ""
    echo "FocusGuard updated successfully!"
    pgrep -x FocusGuard >/dev/null || open /Applications/FocusGuard.app
    echo "If macOS asks whether FocusGuard may send notifications, click Allow."
    echo ""
    echo "Done! You can close this window."
else
    echo ""
    echo "Update cancelled or failed."
fi

echo ""
echo "Press any key to close..."
read -n 1
