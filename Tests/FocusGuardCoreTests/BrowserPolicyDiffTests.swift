import XCTest
@testable import FocusGuardCore

final class BrowserPolicyDiffTests: XCTestCase {
    private let extra: Set<String> = ["pornhub.com", "xvideos.com"]

    /// Locked and in sync: the profile matches what /etc/hosts enforces -> nothing stale.
    func testLockedInSyncIsEmpty() {
        let user: Set<String> = ["reddit.com", "9gag.com"]
        let installed = user.union(extra)            // profile baked from user + extra
        let live = user.union(extra)                 // locked: hosts blocks user + extra
        XCTAssertEqual(
            BrowserPolicyDiff.browserOnlyBlocked(installed: installed, liveBlocked: live, extra: extra),
            []
        )
    }

    /// A site removed from the live list but still baked into the installed profile is
    /// surfaced as still-blocked-in-browser (the exact "I removed it but it's blocked" bug).
    func testRemovedButStaleSurfacesTheRemovedDomain() {
        let installed: Set<String> = Set(["reddit.com", "9gag.com"]).union(extra)
        let live: Set<String> = Set(["9gag.com"]).union(extra) // reddit removed from hosts
        XCTAssertEqual(
            BrowserPolicyDiff.browserOnlyBlocked(installed: installed, liveBlocked: live, extra: extra),
            ["reddit.com"]
        )
    }

    /// During an unlock window /etc/hosts frees the user domains, but the profile has no
    /// unlock concept and still blocks them all -> every user domain is surfaced.
    func testUnlockedSurfacesAllUserDomains() {
        let user: Set<String> = ["reddit.com", "9gag.com", "odysee.com"]
        let installed = user.union(extra)
        let live = extra                              // unlocked: hosts keeps only extra
        XCTAssertEqual(
            BrowserPolicyDiff.browserOnlyBlocked(installed: installed, liveBlocked: live, extra: extra),
            ["9gag.com", "odysee.com", "reddit.com"]
        )
    }

    /// The always-on ExtraBlocklist must NEVER surface, even if it is absent from the live
    /// hosts set (e.g. always-on hardening disabled). Privacy invariant.
    func testExtraBlocklistNeverSurfaces() {
        let installed: Set<String> = Set(["reddit.com"]).union(extra)
        let live: Set<String> = []                    // nothing live at all
        XCTAssertEqual(
            BrowserPolicyDiff.browserOnlyBlocked(installed: installed, liveBlocked: live, extra: extra),
            ["reddit.com"]
        )
    }

    /// No installed profile -> nothing to be honest about.
    func testNoProfileIsEmpty() {
        XCTAssertEqual(
            BrowserPolicyDiff.browserOnlyBlocked(installed: [], liveBlocked: ["reddit.com"], extra: extra),
            []
        )
    }
}
