#!/usr/bin/env python3
"""Generate an iOS Configuration Profile for FocusGuard DNS blocking.

Creates a .mobileconfig file that routes all DNS queries through the
FocusGuard Cloudflare Worker, with a random removal password.

Usage:
    sudo python3 generate-profile.py --worker-url https://focusguard-dns.xxx.workers.dev
"""

import argparse
import os
import secrets
import uuid
import plistlib
import sys


def generate_password(length=32):
    """Generate a cryptographically secure random password."""
    return secrets.token_urlsafe(length)[:length]


def build_profile(worker_url: str, removal_password: str) -> dict:
    """Build the configuration profile dict."""
    profile_uuid = str(uuid.uuid4()).upper()
    dns_uuid = str(uuid.uuid4()).upper()

    dns_url = f"{worker_url.rstrip('/')}/dns-query"

    return {
        "PayloadContent": [
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
                "OnDemandRules": [
                    {
                        "Action": "EvaluateConnection",
                        "ActionParameters": [
                            {
                                "DomainAction": "NeverConnect",
                                "Domains": ["*"],
                            }
                        ],
                    },
                    {
                        "Action": "Connect",
                    },
                ],
            },
        ],
        "PayloadDisplayName": "FocusGuard",
        "PayloadDescription": "FocusGuard DNS blocking profile. Removal requires a password stored in the FocusGuard Mac app.",
        "PayloadIdentifier": f"com.focusguard.profile.{profile_uuid}",
        "PayloadOrganization": "FocusGuard",
        "PayloadRemovalDisallowed": False,
        "PayloadType": "Configuration",
        "PayloadUUID": profile_uuid,
        "PayloadVersion": 1,
        "HasRemovalPasscode": True,
        "RemovalPassword": removal_password,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate FocusGuard iOS profile")
    parser.add_argument(
        "--worker-url",
        required=True,
        help="URL of the FocusGuard Cloudflare Worker (e.g. https://focusguard-dns.xxx.workers.dev)",
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

    # Generate removal password
    removal_password = generate_password()

    # Build profile
    profile = build_profile(args.worker_url, removal_password)

    # Write .mobileconfig (plist XML format)
    with open(args.output, "wb") as f:
        plistlib.dump(profile, f)

    print(f"Profile saved to: {args.output}")

    # Save removal password
    password_dir = os.path.dirname(args.password_file)
    if password_dir and not os.path.exists(password_dir):
        os.makedirs(password_dir, exist_ok=True)

    with open(args.password_file, "w") as f:
        f.write(removal_password)
    os.chmod(args.password_file, 0o600)

    print(f"Removal password saved to: {args.password_file}")
    print()
    print("Next steps:")
    print("  1. AirDrop the .mobileconfig file to your iPhone")
    print("  2. On iPhone: Settings > General > VPN & Device Management > Install")
    print("  3. The profile removal password is stored in FocusGuard on Mac")
    print("     (only visible when unlocked)")


if __name__ == "__main__":
    main()
