#!/bin/bash
# Build Resources/AppIcon.icns from a 1024x1024 master PNG.
# Usage: bash Scripts/make-icon.sh [path-to-master.png]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MASTER="${1:-$PROJECT_DIR/Resources/icon-master-1024.png}"

if [ ! -f "$MASTER" ]; then
    echo "Master icon not found: $MASTER"
    echo "Provide a 1024x1024 PNG as the first argument."
    exit 1
fi

SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"

sips -z 16 16     "$MASTER" --out "$SET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$MASTER" --out "$SET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$MASTER" --out "$SET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$MASTER" --out "$SET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$MASTER" --out "$SET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$MASTER" --out "$SET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$MASTER" --out "$SET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$MASTER" --out "$SET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$MASTER" --out "$SET/icon_512x512.png"    >/dev/null
cp "$MASTER" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o "$PROJECT_DIR/Resources/AppIcon.icns"
echo "Wrote $PROJECT_DIR/Resources/AppIcon.icns ($(du -h "$PROJECT_DIR/Resources/AppIcon.icns" | cut -f1))"