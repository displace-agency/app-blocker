#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

echo "=== Building FocusGuard ==="

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/FocusGuard.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/FocusGuard.app/Contents/Resources"
mkdir -p "$BUILD_DIR/daemon"

# Build release binaries
cd "$PROJECT_DIR"
swift build -c release 2>&1

# Copy menu bar app binary
cp .build/release/FocusGuard "$BUILD_DIR/FocusGuard.app/Contents/MacOS/FocusGuard"

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
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# Re-sign the bundle so the ad-hoc signature seals all bundled resources
# (icon, plist, etc). Without this step, spctl reports "code has no resources
# but signature indicates they must be present" and macOS can refuse to
# render the NSStatusItem for the app.
codesign --force --deep --sign - "$BUILD_DIR/FocusGuard.app"

# Copy daemon binary
cp .build/release/FocusGuardDaemon "$BUILD_DIR/daemon/focusguard-daemon"

# Copy resources
cp "$PROJECT_DIR/Resources/com.focusguard.blocker.plist" "$BUILD_DIR/daemon/"
cp "$PROJECT_DIR/Resources/default-blocked.txt" "$BUILD_DIR/daemon/"

echo ""
echo "Build complete!"
echo "  App:    $BUILD_DIR/FocusGuard.app"
echo "  Daemon: $BUILD_DIR/daemon/focusguard-daemon"
