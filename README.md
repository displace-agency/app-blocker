# FocusGuard

A macOS website blocker that can't be bypassed by CleanMyMac or similar uninstaller tools.

FocusGuard runs as a system-level LaunchDaemon (not a regular app), making it invisible to app cleaners. When locked, all critical files are protected with macOS immutable flags -- even `sudo rm` won't work.

## How It Works

- **Blocks websites** via `/etc/hosts` -- no browser extension needed, works across all browsers
- **Disables Chrome Secure DNS** automatically via managed preferences (otherwise Chrome bypasses `/etc/hosts`)
- **Re-enforces every 30 seconds** -- manually editing `/etc/hosts` is pointless, the daemon overwrites it
- **Immutable file protection** -- when locked, the app, daemon, and config files cannot be deleted
- **Menu bar control** -- clean SwiftUI popover to manage everything

## Anti-Bypass Features

| Layer | What It Does |
|-------|-------------|
| LaunchDaemon | No `.app` bundle for CleanMyMac to find |
| `chflags schg` | Files are immutable when locked, even with `sudo` |
| 30s re-enforcement | Manual `/etc/hosts` edits are overwritten |
| Chrome policy | Secure DNS disabled system-wide via managed preferences |
| Escalating delays | Each unlock doubles the wait: 20min, 40min, 80min... |
| Daily budget | Max 2 unlocks per day, then locked until midnight |
| Auto-relock | 15-minute cooldown window, then blocks re-engage |
| Confirmation phrase | Must type "I am choosing to procrastinate" to unlock |

## Unlock Flow

1. Click shield icon in menu bar
2. Click "Request Unlock"
3. Type "I am choosing to procrastinate"
4. Wait 20 minutes (doubles with each use that day)
5. Sites unblock for 15 minutes
6. Auto-relocks after cooldown expires

Domain deletion is only available during the unlocked window.

## Preset Groups

Click "Groups" in the menu bar popover to block entire categories with one click:

| Group | Sites | Examples |
|-------|-------|----------|
| Social Media | 15 | X, Facebook, Instagram, TikTok, Reddit, Discord |
| Video | 12 | YouTube, Twitch, Vimeo, Dailymotion |
| News | 50 | CNN, BBC, NYT, Guardian, Reuters, Bloomberg |
| Streaming | 19 | Netflix, Disney+, HBO Max, Hulu, Prime Video |
| Gaming | 20 | Steam, Epic Games, Riot, Blizzard, Roblox |
| Shopping | 20 | Amazon, eBay, AliExpress, Shein, Temu, Zara |

Groups show a checkmark when all domains are already blocked. You can add remaining domains from a partially blocked group with one click.

## Installation

### From Source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/displace-agency/app-blocker.git
cd app-blocker
bash Scripts/build.sh
sudo bash Scripts/install.sh
```

### Using the Installer Package

```bash
bash Scripts/build.sh
bash Scripts/create-pkg.sh
# Double-click build/FocusGuard-Installer.pkg
```

### Updating

Double-click `Scripts/update.command` in Finder. It handles everything with a single password prompt.

## Usage

The shield icon appears in your menu bar:
- **Shield checkered** -- locked (sites blocked)
- **Shield exclamation** -- unlock pending (waiting)
- **Shield slash** -- unlocked (cooldown active)

### Add sites to block

Click the shield icon, type a domain in "Add site..." and press Enter. Works with URLs too -- it auto-strips `https://`, `www.`, and paths.

### Remove sites

Only available during the 15-minute unlocked window. Go through the unlock flow first.

## Configuration

Edit `/etc/focusguard/config.json`:

```json
{
  "unlockDelay": 1200,
  "maxUnlocksPerDay": 2,
  "cooldownDuration": 900
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `unlockDelay` | `1200` | Base unlock delay in seconds (20 min) |
| `maxUnlocksPerDay` | `2` | Daily unlock budget |
| `cooldownDuration` | `900` | Unlocked window in seconds (15 min) |

The unlock delay escalates: `unlockDelay * 2^(unlocks_today)`.

## Uninstalling

By design, this is a manual multi-step process. You must be in the unlocked state first (files are immutable when locked).

```bash
# 1. Unlock first (wait for cooldown)
# 2. Then run:
sudo launchctl bootout system/com.focusguard.blocker
sudo rm /Library/LaunchDaemons/com.focusguard.blocker.plist
sudo rm /usr/local/bin/focusguard-daemon
sudo rm -rf /etc/focusguard
sudo rm -rf /Applications/FocusGuard.app
sudo sed -i '' '/FOCUSGUARD-START/,/FOCUSGUARD-END/d' /etc/hosts
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
sudo defaults delete '/Library/Managed Preferences/com.google.Chrome' DnsOverHttpsMode
```

## Project Structure

```
app-blocker/
├── Package.swift              # Swift Package Manager manifest
├── FocusGuard/                # Menu bar app (SwiftUI + AppKit)
│   ├── FocusGuardApp.swift    # App entry point, NSStatusBar setup
│   ├── StatusView.swift       # Main popover UI
│   ├── DaemonClient.swift     # IPC with daemon via /tmp command file
│   └── UnlockConfirmationView.swift
├── FocusGuardDaemon/          # LaunchDaemon (runs as root)
│   └── main.swift             # Blocking engine, file protection, commands
├── FocusGuardShared/          # Shared types between app and daemon
│   └── FocusGuardConfig.swift
├── Resources/
│   ├── com.focusguard.blocker.plist  # LaunchDaemon config
│   └── default-blocked.txt          # Default blocklist (YouTube)
└── Scripts/
    ├── build.sh               # Build release binaries
    ├── install.sh             # Install with sudo
    ├── update.command         # Double-click updater
    └── create-pkg.sh          # Create .pkg installer
```

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (for building from source)

## License

MIT
