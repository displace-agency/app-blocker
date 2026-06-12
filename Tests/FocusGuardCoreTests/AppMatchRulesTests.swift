import XCTest
@testable import FocusGuardCore

final class AppMatchRulesTests: XCTestCase {
    func testValidNames() {
        XCTAssertTrue(AppMatchRules.isValidAppName("Steam"))
        XCTAssertTrue(AppMatchRules.isValidAppName("Discord"))
        XCTAssertTrue(AppMatchRules.isValidAppName("Microsoft Word"))
        XCTAssertTrue(AppMatchRules.isValidAppName("Steam.app"))
    }

    func testInvalidNames() {
        XCTAssertFalse(AppMatchRules.isValidAppName(""))
        XCTAssertFalse(AppMatchRules.isValidAppName("/Applications/Steam.app"))
        XCTAssertFalse(AppMatchRules.isValidAppName("FocusGuard"))      // never self-block
        XCTAssertFalse(AppMatchRules.isValidAppName("bad;rm -rf"))
    }

    func testKillsMatchingUserApp() {
        let list = ["Steam", "Discord"]
        XCTAssertTrue(AppMatchRules.shouldKill(path: "/Applications/Steam.app/Contents/MacOS/steam_osx", blocklist: list))
        XCTAssertTrue(AppMatchRules.shouldKill(path: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper", blocklist: list))
        XCTAssertTrue(AppMatchRules.shouldKill(path: "/Users/v0687/Applications/Steam.app/Contents/MacOS/steam_osx", blocklist: list))
    }

    func testDoesNotKillSystemProcesses() {
        let list = ["Steam", "Finder", "Dock"]
        XCTAssertFalse(AppMatchRules.shouldKill(path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", blocklist: list))
        XCTAssertFalse(AppMatchRules.shouldKill(path: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", blocklist: list))
        XCTAssertFalse(AppMatchRules.shouldKill(path: "/usr/libexec/some-daemon", blocklist: list))
        XCTAssertFalse(AppMatchRules.shouldKill(path: "/sbin/launchd", blocklist: list))
    }

    func testDoesNotKillUnlistedApp() {
        XCTAssertFalse(AppMatchRules.shouldKill(path: "/Applications/Safari.app/Contents/MacOS/Safari", blocklist: ["Steam"]))
    }

    func testNormalizeStripsDotApp() {
        XCTAssertEqual(AppMatchRules.normalize("Steam.app"), "Steam")
        XCTAssertEqual(AppMatchRules.normalize("  Discord  "), "Discord")
    }
}
