# FocusGuard - Current Status & Next Steps

## Project Path
`~/websites/app-blocker/`

## What Works
- **Mac daemon**: Blocks websites via /etc/hosts, enforces every 30s, escalating delays, daily budget, auto-relock cooldown
- **Mac menu bar app**: SwiftUI popover with status, domain management, groups, unlock flow
- **Cloudflare Worker**: DNS proxy at `https://focusguard-dns.displace-agency-2-0.workers.dev` -- blocks domains from KV, sync API works
- **DNS profile**: QR code installs .mobileconfig on iPhone, blocks websites in browsers
- **Onboarding**: 4-step first-launch flow
- **Website**: Rebranded at `~/websites/app-blocker/website/` (Next.js, deployed on Vercel)
- **Logo**: Generated at `Resources/logo.png`

## Known Bugs to Fix

### UI Issues (Fixed)
1. ~~**Popover doesn't auto-dismiss**~~ -- Fixed: sheets moved to standalone NSWindows via NotificationCenter → AppDelegate
2. ~~**Group list alignment**~~ -- Fixed: action button area has `minWidth: 56`, chevron has `width: 20`
3. ~~**Groups expanded view**~~ -- Fixed: dots 6px, spacing `.padding(.vertical, 3)`, font size 11
4. ~~**iPhone setup sheet**~~ -- Fixed: opens as separate NSWindow, popover closes first
5. **Menu bar icon** sometimes doesn't show on first launch (isTemplate issue intermittent)
6. ~~**Blocked sites list**~~ -- Fixed: font size bumped to 12pt monospaced
7. ~~**"Wait time" text overlap**~~ -- Fixed: shortened label, added `.lineLimit(1).minimumScaleFactor(0.8)`

### Functional Issues
8. ~~**Batch domain removal**~~ -- Fixed: added `removeDomains` command (DaemonCommand + DaemonClient + daemon batch handler)
9. **Daemon not restarting after update** -- the update.command sometimes fails to restart the daemon.
10. ~~**Cloud sync config**~~ -- Fixed: workerUrl + workerApiKey added to config.json (requires sudo command from user)
11. **Profile generator reads from /etc/focusguard/blocked.txt** -- needs sudo. Should read from daemon status file instead.

### iOS Limitations (Accepted)
12. **Cannot block native iOS apps via DNS** -- Accepted limitation. Screen Time App Limits is the manual workaround. FamilyControls iOS app would need Apple Developer Program ($99/yr) + entitlement approval.
13. **Cannot prevent profile removal on non-supervised iPhone** -- Screen Time passcode workaround is built into the app.
14. **Profile install still requires manual taps** -- iOS limitation, cannot be fixed.

### Code Quality
15. ~~**StatusView.swift is 470+ lines**~~ -- Fixed: split into StatusView (230 lines), BlockedSitesView, GroupsView
16. **iPhoneSetupView.swift** has three sub-views in one file (functional, low priority)
17. **Daemon main.swift is 530+ lines** -- could benefit from splitting into modules
18. **No tests** -- zero test coverage
19. **Website not QA'd** -- rebranded content hasn't been reviewed on mobile/desktop

## Architecture Overview

```
~/websites/app-blocker/
├── Package.swift                    # Swift 5.9, macOS 13+
├── FocusGuard/                      # Menu bar app
│   ├── FocusGuardApp.swift          # NSStatusBar + onboarding + window management
│   ├── StatusView.swift             # Main popover (header, actions, footer)
│   ├── BlockedSitesView.swift       # Blocked sites list + add domain
│   ├── GroupsView.swift             # Quick-add groups with expand/collapse
│   ├── DaemonClient.swift           # IPC via /tmp/focusguard.command
│   ├── OnboardingView.swift         # First-launch 4-step flow
│   ├── UnlockConfirmationView.swift # Shame phrase dialog (standalone window)
│   └── iPhoneSetupView.swift        # QR code + Screen Time setup (standalone window)
├── FocusGuardDaemon/
│   └── main.swift                   # Daemon (enforce, sync, commands)
├── FocusGuardShared/
│   ├── FocusGuardConfig.swift       # Shared types, commands, status
│   └── DomainGroups.swift           # 6 preset groups (136 domains)
├── worker/                          # Cloudflare Worker (TypeScript)
│   ├── src/index.ts                 # DoH proxy + sync API + profile endpoint
│   └── src/dns.ts                   # DNS wire format parser
├── website/                         # Marketing site (Next.js)
├── Scripts/
│   ├── build.sh                     # Build release binaries
│   ├── install.sh                   # Full install with sudo
│   ├── update.command               # Double-click updater
│   ├── create-pkg.sh                # .pkg installer
│   └── generate-profile.py          # iOS .mobileconfig generator
└── Resources/
    ├── logo.png                     # App icon
    ├── com.focusguard.blocker.plist # LaunchDaemon config
    └── default-blocked.txt          # Default YouTube blocklist
```

## Key Credentials/Config
- **Worker URL**: `https://focusguard-dns.displace-agency-2-0.workers.dev`
- **Worker API Key**: stored as Cloudflare Worker secret (`wrangler secret put API_KEY`); not in source
- **KV Namespace ID**: `ee41cb9716bb4c47aa237e942ce0cf35`
- **GitHub**: `displace-agency/app-blocker` (main app) + `displace-agency/website-focusguard` (website)
- **Vercel**: `website-reclaimos` project (needs rename to `website-focusguard` in dashboard)

## Config Files on Mac
- `/etc/focusguard/config.json` -- daemon config (needs workerUrl + workerApiKey added)
- `/etc/focusguard/blocked.txt` -- domain blocklist
- `/etc/focusguard/.status` -- daemon status JSON
- `/tmp/focusguard.command` -- IPC command file
- `~/Library/Application Support/FocusGuard/screentime_passcode` -- Screen Time code

## Deprecated Scripts
All deprecated scripts have been deleted. Only active scripts remain in `Scripts/`.
