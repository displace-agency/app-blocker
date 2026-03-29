#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
PKG_DIR="$BUILD_DIR/pkg-root"
SCRIPTS_PKG="$BUILD_DIR/pkg-scripts"
OUTPUT="$BUILD_DIR/FocusGuard-Installer.pkg"

echo "=== Creating FocusGuard .pkg Installer ==="

# Check build exists
if [ ! -f "$BUILD_DIR/daemon/focusguard-daemon" ] || [ ! -d "$BUILD_DIR/FocusGuard.app" ]; then
    echo "Build not found. Run Scripts/build.sh first."
    exit 1
fi

# Clean
rm -rf "$PKG_DIR" "$SCRIPTS_PKG"

# Create package root (mirrors the filesystem)
mkdir -p "$PKG_DIR/usr/local/bin"
mkdir -p "$PKG_DIR/Library/LaunchDaemons"
mkdir -p "$PKG_DIR/Applications"
mkdir -p "$PKG_DIR/etc/focusguard"
mkdir -p "$PKG_DIR/Library/Managed Preferences"

# Copy files
cp "$BUILD_DIR/daemon/focusguard-daemon" "$PKG_DIR/usr/local/bin/"
chmod 755 "$PKG_DIR/usr/local/bin/focusguard-daemon"

cp "$BUILD_DIR/daemon/com.focusguard.blocker.plist" "$PKG_DIR/Library/LaunchDaemons/"

cp -R "$BUILD_DIR/FocusGuard.app" "$PKG_DIR/Applications/"

cp "$BUILD_DIR/daemon/default-blocked.txt" "$PKG_DIR/etc/focusguard/blocked.txt"
echo '{"unlockDelay": 1200}' > "$PKG_DIR/etc/focusguard/config.json"

# Create postinstall script
mkdir -p "$SCRIPTS_PKG"
cat > "$SCRIPTS_PKG/postinstall" << 'POSTINSTALL'
#!/bin/bash

# Set permissions
chown root:wheel /Library/LaunchDaemons/com.focusguard.blocker.plist
chmod 644 /Library/LaunchDaemons/com.focusguard.blocker.plist
chmod 755 /usr/local/bin/focusguard-daemon

# Disable Chrome Secure DNS
mkdir -p "/Library/Managed Preferences"
defaults write "/Library/Managed Preferences/com.google.Chrome" DnsOverHttpsMode -string "off"

# Load daemon
launchctl bootout system/com.focusguard.blocker 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.focusguard.blocker.plist

# Open the menu bar app
sudo -u "$USER" open /Applications/FocusGuard.app 2>/dev/null || true

exit 0
POSTINSTALL
chmod 755 "$SCRIPTS_PKG/postinstall"

# Build the package
pkgbuild \
    --root "$PKG_DIR" \
    --scripts "$SCRIPTS_PKG" \
    --identifier "com.focusguard.installer" \
    --version "1.0.0" \
    --install-location "/" \
    "$OUTPUT"

echo ""
echo "Package created: $OUTPUT"
echo ""
echo "Distribute this .pkg file. Users double-click to install."
echo "It installs:"
echo "  - /Applications/FocusGuard.app (menu bar control)"
echo "  - /usr/local/bin/focusguard-daemon (blocking engine)"
echo "  - /Library/LaunchDaemons/com.focusguard.blocker.plist"
echo "  - /etc/focusguard/ (config + blocklist)"
echo "  - Chrome Secure DNS disabled"
