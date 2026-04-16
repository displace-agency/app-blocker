#!/usr/bin/env python3
"""Generate an iOS Configuration Profile for FocusGuard DNS + content blocking.

Creates a .mobileconfig file with:
1. DNS-over-HTTPS routing through FocusGuard Cloudflare Worker
2. Web content filter that blocks domains in Safari and WebKit apps
3. Screen Time-style app restrictions (limits YouTube, Twitter, etc.)

Usage:
    sudo python3 generate-profile.py --worker-url https://focusguard-dns.xxx.workers.dev
"""

import argparse
import os
import secrets
import uuid
import plistlib

def read_blocked_domains():
    """Read the actual blocked domains from the Mac's blocklist."""
    blocked_file = "/etc/focusguard/blocked.txt"
    try:
        with open(blocked_file, "r") as f:
            domains = []
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    domains.append(line)
            return domains
    except FileNotFoundError:
        print(f"Warning: {blocked_file} not found. Using empty blocklist.")
        return []


def generate_password(length=32):
    return secrets.token_urlsafe(length)[:length]


def build_profile(worker_url: str, removal_password: str, blocked_domains: list) -> dict:
    profile_uuid = str(uuid.uuid4()).upper()
    dns_uuid = str(uuid.uuid4()).upper()
    filter_uuid = str(uuid.uuid4()).upper()
    screen_time_uuid = str(uuid.uuid4()).upper()

    dns_url = f"{worker_url.rstrip('/')}/dns-query"

    # Build blocked URLs for web content filter (with www variants)
    blocked_urls = []
    for domain in blocked_domains:
        blocked_urls.append(domain)
        if not domain.startswith("www."):
            blocked_urls.append(f"www.{domain}")

    payloads = [
        # 1. DNS-over-HTTPS payload
        {
            "PayloadType": "com.apple.dnsSettings.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": f"com.focusguard.dns.{dns_uuid}",
            "PayloadUUID": dns_uuid,
            "PayloadDisplayName": "FocusGuard DNS",
            "PayloadDescription": "Routes DNS through FocusGuard to block distracting websites.",
            "DNSSettings": {
                "DNSProtocol": "HTTPS",
                "ServerURL": dns_url,
            },
        },
        # 2. Web Content Filter payload (blocks Safari + WebKit apps)
        {
            "PayloadType": "com.apple.webcontent-filter",
            "PayloadVersion": 1,
            "PayloadIdentifier": f"com.focusguard.filter.{filter_uuid}",
            "PayloadUUID": filter_uuid,
            "PayloadDisplayName": "FocusGuard Web Filter",
            "PayloadDescription": "Blocks distracting websites in Safari and apps.",
            "AutoFilterEnabled": True,
            "FilterType": "BuiltIn",
            "PermittedURLs": [],
            "BlacklistedURLs": blocked_urls,
        },
        # 3. App restrictions payload (blocks specific app bundle IDs)
        {
            "PayloadType": "com.apple.applicationaccess",
            "PayloadVersion": 1,
            "PayloadIdentifier": f"com.focusguard.apprestrictions.{screen_time_uuid}",
            "PayloadUUID": screen_time_uuid,
            "PayloadDisplayName": "FocusGuard App Restrictions",
            "PayloadDescription": "Restricts access to distracting apps.",
            # Block specific apps by preventing their use
            "blockedAppBundleIDs": [
                "com.google.ios.youtube",          # YouTube
                "com.atebits.Tweetie2",            # Twitter/X
                "com.burbn.instagram",             # Instagram
                "com.zhiliaoapp.musically",        # TikTok
                "com.reddit.Reddit",               # Reddit
                "com.snapchat.snapchat",           # Snapchat
                "com.facebook.Facebook",           # Facebook
                "net.whatsapp.WhatsApp",           # WhatsApp (optional)
                "com.hammerandchisel.discord",     # Discord
                "com.pinterest",                   # Pinterest
                "com.netflix.Netflix",             # Netflix
                "com.disney.disneyplus",           # Disney+
                "com.amazon.aiv.AIVApp",           # Prime Video
                "com.hbo.hbonow",                  # HBO Max
                "tv.twitch",                       # Twitch
                "com.amazon.Amazon",               # Amazon Shopping
                "com.ebay.iphone",                 # eBay
            ],
        },
    ]

    return {
        "PayloadContent": payloads,
        "PayloadDisplayName": "FocusGuard",
        "PayloadDescription": "FocusGuard website and app blocker. Blocks distracting content across browsers and native apps.",
        "PayloadIdentifier": f"com.focusguard.profile.{profile_uuid}",
        "PayloadOrganization": "FocusGuard",
        "PayloadRemovalDisallowed": False,
        "PayloadType": "Configuration",
        "PayloadUUID": profile_uuid,
        "PayloadVersion": 1,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate FocusGuard iOS profile")
    parser.add_argument(
        "--worker-url",
        required=True,
        help="URL of the FocusGuard Cloudflare Worker",
    )
    parser.add_argument(
        "--output",
        default=os.path.expanduser("~/Downloads/FocusGuard.mobileconfig"),
        help="Output path for the .mobileconfig file",
    )
    parser.add_argument(
        "--password-file",
        default="/etc/focusguard/.ios_profile_password",
        help="Path to store the removal password",
    )
    args = parser.parse_args()

    removal_password = generate_password()
    blocked_domains = read_blocked_domains()
    if not blocked_domains:
        print("No domains blocked on Mac. Add domains first via the FocusGuard menu bar app.")
        sys.exit(1)
    profile = build_profile(args.worker_url, removal_password, blocked_domains)

    with open(args.output, "wb") as f:
        plistlib.dump(profile, f)

    print(f"Profile saved to: {args.output}")

    password_dir = os.path.dirname(args.password_file)
    if password_dir and not os.path.exists(password_dir):
        os.makedirs(password_dir, exist_ok=True)

    with open(args.password_file, "w") as f:
        f.write(removal_password)
    os.chmod(args.password_file, 0o600)

    print(f"Removal password saved to: {args.password_file}")
    print()
    print("What this profile blocks:")
    print(f"  - {len(blocked_domains)} domains via DNS (all browsers)")
    print(f"  - {len(blocked_domains) * 2} URLs via web content filter (Safari + WebKit apps)")
    print(f"  - Native iOS apps matching blocked domains")
    print()
    print("IMPORTANT: Profile removal password does NOT work on non-supervised iPhones.")
    print("To make profile non-removable, supervise the iPhone via Apple Configurator.")
    print()
    print("Next steps:")
    print("  1. Remove the old FocusGuard profile from iPhone first")
    print("  2. AirDrop this new .mobileconfig to iPhone")
    print("  3. Install via Settings > General > VPN & Device Management")
    print()
    print("Optional - Make profile non-removable:")
    print("  1. Open Apple Configurator 2 on Mac (free from App Store)")
    print("  2. Connect iPhone via USB")
    print("  3. Prepare > Supervise device (WARNING: erases iPhone)")
    print("  4. Then reinstall this profile - it cannot be removed")


if __name__ == "__main__":
    main()
