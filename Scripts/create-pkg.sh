#!/bin/bash
# Builds build/FocusGuard-Installer.pkg (v1.1.0) from the output of Scripts/build.sh.
# Mirrors what Scripts/install.sh installs: daemon + LaunchDaemon, menu-bar app, the
# login agent, and /etc/focusguard defaults (never overwriting an existing list/config).
# RELEASE NOTE: the public pkg must be built with FOCUSGUARD_PUBLIC=1 (PUBLIC_BUILD flag),
# or the app ships the owner-only iPhone setup and profiles banner. Use Scripts/build-release.sh.
# No configuration profile is bundled or installed; those stay optional, user-installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
PKG_DIR="$BUILD_DIR/pkg-root"
SCRIPTS_PKG="$BUILD_DIR/pkg-scripts"
OUTPUT="$BUILD_DIR/FocusGuard-Installer.pkg"
VERSION="1.1.0"

echo "=== Creating FocusGuard $VERSION .pkg Installer ==="

# Check build exists
if [ ! -f "$BUILD_DIR/daemon/focusguard-daemon" ] || [ ! -d "$BUILD_DIR/FocusGuard.app" ] \
   || [ ! -f "$BUILD_DIR/daemon/com.focusguard.app.plist" ]; then
    echo "Build not found. Run Scripts/build.sh first."
    exit 1
fi

# Clean
rm -rf "$PKG_DIR" "$SCRIPTS_PKG" "$OUTPUT"

# Package root (mirrors the filesystem)
mkdir -p "$PKG_DIR/usr/local/bin"
mkdir -p "$PKG_DIR/Library/LaunchDaemons"
mkdir -p "$PKG_DIR/Library/LaunchAgents"
mkdir -p "$PKG_DIR/Applications"
# Defaults are staged here and copied into /etc/focusguard by postinstall only when
# absent, so reinstalling never overwrites a user's blocklist or config.
mkdir -p "$PKG_DIR/usr/local/share/focusguard"

cp "$BUILD_DIR/daemon/focusguard-daemon" "$PKG_DIR/usr/local/bin/"
chmod 755 "$PKG_DIR/usr/local/bin/focusguard-daemon"

cp "$BUILD_DIR/daemon/com.focusguard.blocker.plist" "$PKG_DIR/Library/LaunchDaemons/"
cp "$BUILD_DIR/daemon/com.focusguard.app.plist" "$PKG_DIR/Library/LaunchAgents/"
chmod 644 "$PKG_DIR/Library/LaunchDaemons/com.focusguard.blocker.plist" \
          "$PKG_DIR/Library/LaunchAgents/com.focusguard.app.plist"

cp -R "$BUILD_DIR/FocusGuard.app" "$PKG_DIR/Applications/"

cp "$BUILD_DIR/daemon/default-blocked.txt" "$PKG_DIR/usr/local/share/focusguard/default-blocked.txt"
# Same default config as install.sh (20-minute unlock delay, 2 unlocks/day, 15-minute window).
echo '{"version":2,"unlockDelay":1200,"maxUnlocksPerDay":2,"cooldownDuration":900,"appCheckInterval":10,"schedules":[]}' \
    > "$PKG_DIR/usr/local/share/focusguard/default-config.json"

# Postinstall (runs as root; $USER is root, so the console user is looked up)
mkdir -p "$SCRIPTS_PKG"
cat > "$SCRIPTS_PKG/postinstall" << 'POSTINSTALL'
#!/bin/bash
# FocusGuard postinstall. Runs as root.

DEFAULTS=/usr/local/share/focusguard

# /etc/focusguard: defaults only when absent (preserve existing)
mkdir -p /etc/focusguard
[ -f /etc/focusguard/blocked.txt ] || cp "$DEFAULTS/default-blocked.txt" /etc/focusguard/blocked.txt
[ -f /etc/focusguard/appBlocked.txt ] || : > /etc/focusguard/appBlocked.txt
[ -f /etc/focusguard/config.json ] || cp "$DEFAULTS/default-config.json" /etc/focusguard/config.json

# Ownership and modes
chown root:wheel /usr/local/bin/focusguard-daemon /Library/LaunchDaemons/com.focusguard.blocker.plist \
    /Library/LaunchAgents/com.focusguard.app.plist
chmod 755 /usr/local/bin/focusguard-daemon
chmod 644 /Library/LaunchDaemons/com.focusguard.blocker.plist /Library/LaunchAgents/com.focusguard.app.plist
chown -R root:wheel /Applications/FocusGuard.app

# Load the daemon (reload if an older one is running)
launchctl bootout system/com.focusguard.blocker 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.focusguard.blocker.plist 2>&1 || true

# Menu-bar app: start the login agent for the logged-in user (none at the login window)
CONSOLE_USER="$(stat -f%Su /dev/console)"
if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ] && [ "$CONSOLE_USER" != "loginwindow" ]; then
    CONSOLE_UID="$(id -u "$CONSOLE_USER")"
    launchctl bootout "gui/$CONSOLE_UID/com.focusguard.app" 2>/dev/null || true
    launchctl bootstrap "gui/$CONSOLE_UID" /Library/LaunchAgents/com.focusguard.app.plist 2>/dev/null || true
    # The agent normally starts the app; open it only if it is not running.
    pgrep -x FocusGuard >/dev/null || launchctl asuser "$CONSOLE_UID" /usr/bin/open /Applications/FocusGuard.app 2>/dev/null || true
fi

exit 0
POSTINSTALL
chmod 755 "$SCRIPTS_PKG/postinstall"

# Build the package (files owned by root:wheel)
pkgbuild \
    --root "$PKG_DIR" \
    --scripts "$SCRIPTS_PKG" \
    --identifier "com.focusguard.installer" \
    --version "$VERSION" \
    --ownership recommended \
    --install-location "/" \
    "$OUTPUT"

echo ""
echo "Package created: $OUTPUT"
echo ""
echo "It installs:"
echo "  - /Applications/FocusGuard.app (menu bar control)"
echo "  - /usr/local/bin/focusguard-daemon (blocking engine)"
echo "  - /Library/LaunchDaemons/com.focusguard.blocker.plist"
echo "  - /Library/LaunchAgents/com.focusguard.app.plist (menu bar app at login)"
echo "  - /etc/focusguard/ (default blocklist + config, created only if missing)"
echo "No configuration profile is installed; see README for the optional profiles."
