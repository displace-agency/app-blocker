import Foundation

/// Pure logic for the "honest browser layer" signal.
///
/// FocusGuard blocks on two independent planes: `/etc/hosts` (managed live by the
/// daemon, freed by an unlock) and a browser configuration profile whose
/// `URLBlocklist` is generated from the list but only refreshed when the user
/// regenerates+reinstalls it. The profile keeps blocking pre-network regardless of
/// lock state, so a site removed from the list (or any site during an unlock window)
/// can still show "This page is blocked" in the browser. We surface that truthfully
/// instead of claiming the site was unblocked.
public enum BrowserPolicyDiff {
    /// Domains the installed browser profile enforces that are NOT currently enforced in
    /// `/etc/hosts`. `extra` (the always-on `ExtraBlocklist`) is removed so the private
    /// list never surfaces in status/UI even if always-on hardening is somehow off.
    ///
    /// - Parameters:
    ///   - installed: domain set materialised from the installed browser policy profile.
    ///   - liveBlocked: domain set the daemon is currently writing to `/etc/hosts`.
    ///   - extra: the always-on `ExtraBlocklist` domain set (never surfaced).
    /// - Returns: the user-facing "still blocked in your browser" domains, sorted.
    public static func browserOnlyBlocked(
        installed: Set<String>,
        liveBlocked: Set<String>,
        extra: Set<String>
    ) -> [String] {
        installed.subtracting(liveBlocked).subtracting(extra).sorted()
    }
}
