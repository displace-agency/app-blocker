# FocusGuard iOS Sync — Implementation Plan

## Context

FocusGuard currently blocks websites on macOS via `/etc/hosts`. Users want the same blocking on their iPhone, synced with the Mac. The approach: a Cloudflare Worker acts as a DNS proxy that the iPhone queries, and a Configuration Profile locks the iPhone to use this DNS with a removal password stored behind the Mac's unlock flow.

## Architecture

```
Mac (FocusGuard daemon)
  → Pushes blocklist + lock state to Cloudflare Worker API
  → Stores iOS profile removal password

Cloudflare Worker (DNS Proxy + Sync API)
  → Receives DNS queries from iPhone (DoH protocol)
  → Checks domain against KV blocklist
  → Blocked → returns 0.0.0.0
  → Allowed → forwards to 1.1.1.1
  → Receives sync updates from Mac daemon

iPhone (Configuration Profile)
  → DNS-over-HTTPS routed to Worker
  → Profile requires password to remove
  → Password only accessible via Mac unlock flow
```

## Phase 1: Cloudflare Worker

**New files:**
- `worker/wrangler.toml` — Worker config with KV binding
- `worker/package.json` — TypeScript dependencies
- `worker/tsconfig.json`
- `worker/src/index.ts` — Main handler: DoH endpoint + sync API
- `worker/src/dns.ts` — DNS wire format parser/builder (RFC 1035)

**Worker endpoints:**
| Route | Auth | Purpose |
|-------|------|---------|
| `POST /dns-query` | None (standard DoH) | iPhone DNS queries |
| `GET /dns-query?dns=...` | None | DoH GET variant |
| `POST /api/sync` | Bearer token | Daemon pushes blocklist + status |
| `GET /api/status` | Bearer token | Read current state |

**KV structure:**
```
FOCUSGUARD_BLOCKLIST namespace:
  "domains" → ["x.com", "youtube.com", ...]
  "status"  → {"locked": true, "cooldownEnd": null}
```

**DNS blocking logic:**
1. Parse DNS query wire format → extract domain name
2. Check domain against cached blocklist (60s in-memory TTL)
3. If blocked AND status is locked → return synthetic 0.0.0.0 A record
4. Otherwise → forward to `https://cloudflare-dns.com/dns-query`

**Deploy:**
```bash
cd worker
wrangler kv namespace create FOCUSGUARD_BLOCKLIST
wrangler secret put API_KEY
wrangler deploy
```

## Phase 2: Daemon Cloud Sync

**Modified file:** `FocusGuardDaemon/main.swift`

Add `syncToCloud()`:
- Called after `enforce()` only when state changes (track hash of domains + lock status)
- HTTP POST to `workerUrl/api/sync` with Bearer token
- Body: `{"domains": [...], "locked": true/false}`
- Fire-and-forget using `URLSession` — never blocks the enforce loop
- If `workerUrl` not in config, silently skip (backward compatible)

**Modified file:** `FocusGuardShared/FocusGuardConfig.swift`
- Add `workerUrl` and `workerApiKey` to config constants

**Config update** (`/etc/focusguard/config.json`):
```json
{
  "unlockDelay": 1200,
  "maxUnlocksPerDay": 2,
  "cooldownDuration": 900,
  "workerUrl": "https://focusguard-dns.<subdomain>.workers.dev",
  "workerApiKey": "<generated-api-key>"
}
```

## Phase 3: iOS Profile Generator

**New file:** `Scripts/generate-profile.py`

Generates `.mobileconfig` with:
- `com.apple.dnsSettings.managed` payload → DoH pointing to Worker
- Random 32-char removal password
- Profile display name: "FocusGuard DNS"

Saves:
- Profile to `~/Downloads/FocusGuard.mobileconfig`
- Removal password to `/etc/focusguard/.ios_profile_password`

**Usage:** `sudo python3 Scripts/generate-profile.py --worker-url https://focusguard-dns.xxx.workers.dev`

## Phase 4: Mac App UI

**Modified file:** `FocusGuard/StatusView.swift`

Add to footer area:
- "iPhone" button → shows setup sheet
- Setup flow: generates profile, shows instructions (AirDrop to iPhone, install in Settings)
- When unlocked: "Show Profile Password" button reveals the removal password

## Phase 5: Testing

1. Deploy Worker → verify `curl -H 'accept: application/dns-json' 'https://worker-url/dns-query?name=x.com'` returns 0.0.0.0
2. Restart daemon with cloud config → check Worker KV has blocklist
3. Generate profile → install on iPhone → verify x.com blocked
4. Unlock on Mac → verify iPhone unblocks within ~1 minute
5. Auto-relock → verify iPhone re-blocks

## File Summary

| Action | File | Description |
|--------|------|-------------|
| CREATE | `worker/wrangler.toml` | Worker config |
| CREATE | `worker/package.json` | Dependencies |
| CREATE | `worker/tsconfig.json` | TypeScript |
| CREATE | `worker/src/index.ts` | DoH proxy + sync API |
| CREATE | `worker/src/dns.ts` | DNS wire format |
| CREATE | `Scripts/generate-profile.py` | Profile generator |
| MODIFY | `FocusGuardDaemon/main.swift` | Add syncToCloud() |
| MODIFY | `FocusGuardShared/FocusGuardConfig.swift` | Cloud config fields |
| MODIFY | `FocusGuard/StatusView.swift` | Devices UI |
| MODIFY | `Scripts/update.command` | Include worker URL in config |

## Risks & Mitigations

- **Worker down → iPhone DNS fails**: iOS falls back to default DNS. Acceptable — FocusGuard is friction, not a firewall.
- **Free tier limits**: 100K Worker requests/day. iPhone makes ~1 DNS query per site load. Plenty of headroom.
- **KV eventual consistency**: Sync delay up to 60s. Acceptable for a blocker.
- **Profile removal**: Requires password OR factory reset. Strong enough deterrent.
