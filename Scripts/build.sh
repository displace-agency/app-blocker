#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
# SwiftPM cache outside the repo: the repo path contains a literal '*', and a cache
# made under an earlier path name breaks with "PCH was compiled with module cache path".
SCRATCH="${FG_SCRATCH:-$HOME/Library/Caches/FocusGuard-build}"

echo "=== Building FocusGuard ==="

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/FocusGuard.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/FocusGuard.app/Contents/Resources"
mkdir -p "$BUILD_DIR/daemon"

# Build release binaries
cd "$PROJECT_DIR"
swift build -c release --scratch-path "$SCRATCH" 2>&1

# Copy menu bar app binary
cp "$SCRATCH/release/FocusGuard" "$BUILD_DIR/FocusGuard.app/Contents/MacOS/FocusGuard"

# Copy app icon (Finder / About-window / Dock fallback)
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$BUILD_DIR/FocusGuard.app/Contents/Resources/AppIcon.icns"

# Create Info.plist for the app
cat > "$BUILD_DIR/FocusGuard.app/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FocusGuard</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusguard.app</string>
    <key>CFBundleName</key>
    <string>FocusGuard</string>
    <key>CFBundleDisplayName</key>
    <string>FocusGuard</string>
    <key>CFBundleVersion</key>
    <string>1.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# Sign with a STABLE identity. Ad-hoc signatures change every build, so macOS
# never keeps the notification permission (and other TCC grants) for the app:
# the unlock alerts silently went nowhere. Order: $CODESIGN_IDENTITY, an
# "Apple Development" cert, the catalog's self-signed cert, then ad-hoc + warning.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "CopyTranslate Self-Signed"; then
    IDENTITY="CopyTranslate Self-Signed"
fi
cp "$SCRATCH/release/FocusGuardDaemon" "$BUILD_DIR/daemon/focusguard-daemon"
if [ -n "$IDENTITY" ]; then
    echo "Signing with: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$BUILD_DIR/FocusGuard.app"
    codesign --force --sign "$IDENTITY" "$BUILD_DIR/daemon/focusguard-daemon"
else
    echo "WARNING: no stable signing identity; signing ad-hoc (notification permission will not persist)"
    codesign --force --deep --sign - "$BUILD_DIR/FocusGuard.app"
fi

# Copy resources
cp "$PROJECT_DIR/Resources/com.focusguard.blocker.plist" "$BUILD_DIR/daemon/"
cp "$PROJECT_DIR/Resources/com.focusguard.app.plist" "$BUILD_DIR/daemon/"
cp "$PROJECT_DIR/Resources/default-blocked.txt" "$BUILD_DIR/daemon/"

echo ""
echo "Build complete!"
echo "  App:    $BUILD_DIR/FocusGuard.app"
echo "  Daemon: $BUILD_DIR/daemon/focusguard-daemon"
