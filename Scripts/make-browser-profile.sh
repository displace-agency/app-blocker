#!/bin/bash
#
# Generate the LOCAL browser policy profile with URLBlocklist populated from
# ExtraBlocklist.swift.
#
# URLBlocklist is enforced by the browser at the navigation layer (before the request
# leaves), so it blocks the listed domains in ALL Brave windows -- including "New
# private window with Tor", where /etc/hosts is bypassed. This keeps Brave's Tor
# feature usable while still blocking the always-on list inside it.
#
# The committed Resources/FocusGuard-Browser-Policy.mobileconfig keeps URLBlocklist
# EMPTY (public template). The file generated below is gitignored and never pushed.
#
# Usage:
#   bash Scripts/make-browser-profile.sh
#   open Resources/FocusGuard-Browser-Policy.local.mobileconfig   # then approve in System Settings
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$DIR/FocusGuardShared/ExtraBlocklist.swift"
OUT="$DIR/Resources/FocusGuard-Browser-Policy.local.mobileconfig"

domains="$(grep -oE '"[a-z0-9][a-z0-9.-]*\.[a-z]{2,}"' "$SRC" | tr -d '"' | sort -u || true)"
count="$(printf '%s\n' "$domains" | grep -c . || true)"
if [ "${count:-0}" -eq 0 ]; then
  echo "No domains found in $SRC." >&2
  echo "Expected on a fresh clone (the committed file is empty). Populate it locally first." >&2
  exit 1
fi

entries=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  entries="${entries}                <string>${d}</string>
"
done <<EOF
$domains
EOF

cat > "$OUT" <<PROFILE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadType</key><string>Configuration</string>
    <key>PayloadVersion</key><integer>1</integer>
    <key>PayloadIdentifier</key><string>agency.displace.focusguard.browserpolicy</string>
    <key>PayloadUUID</key><string>05D0DF25-3EAF-4EE2-B33D-FED547B4F4A2</string>
    <key>PayloadDisplayName</key><string>FocusGuard Browser Policy</string>
    <key>PayloadDescription</key><string>Blocks the always-on list in Brave and Chrome (including Brave Tor windows) and turns off DNS-over-HTTPS.</string>
    <key>PayloadOrganization</key><string>FocusGuard</string>
    <key>PayloadScope</key><string>System</string>
    <key>PayloadEnabled</key><true/>
    <key>PayloadRemovalDisallowed</key><false/>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key><string>com.brave.Browser</string>
            <key>PayloadVersion</key><integer>1</integer>
            <key>PayloadIdentifier</key><string>agency.displace.focusguard.browserpolicy.brave</string>
            <key>PayloadUUID</key><string>6C952F66-4FE4-4BBA-869A-3AC1019E168F</string>
            <key>PayloadDisplayName</key><string>Brave Policy</string>
            <key>PayloadEnabled</key><true/>
            <key>DnsOverHttpsMode</key><string>off</string>
            <key>URLBlocklist</key>
            <array>
${entries}            </array>
        </dict>
        <dict>
            <key>PayloadType</key><string>com.google.Chrome</string>
            <key>PayloadVersion</key><integer>1</integer>
            <key>PayloadIdentifier</key><string>agency.displace.focusguard.browserpolicy.chrome</string>
            <key>PayloadUUID</key><string>DB701A4E-C558-4FF6-92BA-71C5F1FD54BB</string>
            <key>PayloadDisplayName</key><string>Chrome Policy</string>
            <key>PayloadEnabled</key><true/>
            <key>DnsOverHttpsMode</key><string>off</string>
        </dict>
    </array>
</dict>
</plist>
PROFILE

plutil -lint "$OUT" >/dev/null && echo "Wrote $OUT ($count domains in URLBlocklist)."
echo "Next: open \"$OUT\" then approve in System Settings > General > Device Management, and restart Brave."
