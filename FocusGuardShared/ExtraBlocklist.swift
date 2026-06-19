import Foundation

/// Optional always-on, compiled-in extra blocklist. Empty by default.
///
/// Populate `domains` (apex domains only — `HostsWriter` expands `www.` and IPv6)
/// with any sites you want permanently blocked. Unlike the user blocklist, these are:
/// - enforced even during an unlock window (the unlock valve frees the user blocklist
///   only, never these), and
/// - kept OUT of `/etc/focusguard/blocked.txt`, `StatusInfo.blockedDomains`, and the
///   cloud sync, so they never surface in the menu-bar UI.
///
/// Edit this array and rebuild; it is intentionally not user-editable at runtime.
/// Gated by `DaemonConfig.extraBlocking` (default on).
public enum ExtraBlocklist {
    public static let domains: [String] = [
        // Empty by default. Add apex domains here to enforce an always-on blocklist.
    ]
}
