import XCTest
@testable import FocusGuardCore

final class UnlockClockTests: XCTestCase {
    private let sec: UInt64 = 1_000_000_000

    func testDelayNeedsBothClocksWithinSameBoot() {
        let req = ClockStamp(wall: 1_000, bootId: "b1", monotonic: 50 * sec)
        // Wall jumped forward 2h, but only 60 s really passed: not elapsed.
        XCTAssertFalse(UnlockClock.delayElapsed(request: req, delaySeconds: 1200, nowWall: 1_000 + 7200, bootId: "b1", nowMonotonic: 110 * sec))
        // 20 real minutes on both clocks: elapsed.
        XCTAssertTrue(UnlockClock.delayElapsed(request: req, delaySeconds: 1200, nowWall: 1_000 + 1200, bootId: "b1", nowMonotonic: 1250 * sec))
    }

    func testDelayFallsBackToWallAfterReboot() {
        let req = ClockStamp(wall: 1_000, bootId: "b1", monotonic: 50 * sec)
        XCTAssertTrue(UnlockClock.delayElapsed(request: req, delaySeconds: 1200, nowWall: 2_300, bootId: "b2", nowMonotonic: 5 * sec))
        XCTAssertFalse(UnlockClock.delayElapsed(request: req, delaySeconds: 1200, nowWall: 1_100, bootId: "b2", nowMonotonic: 5 * sec))
    }

    func testLegacyStampDecodes() {
        let legacy = try! JSONEncoder().encode(1234.5)
        XCTAssertEqual(ClockStamp.decode(legacy), ClockStamp(wall: 1234.5))
        let modern = try! JSONEncoder().encode(ClockStamp(wall: 9, bootId: "b", monotonic: 3))
        XCTAssertEqual(ClockStamp.decode(modern), ClockStamp(wall: 9, bootId: "b", monotonic: 3))
        XCTAssertNil(ClockStamp.decode(Data("junk".utf8)))
    }

    func testWindowCannotBeStretchedByRewindingClock() {
        let opened = ClockStamp(wall: 10_000, bootId: "b1", monotonic: 100 * sec)
        let end = UnlockClock.windowEnd(opened: opened, durationSeconds: 900)
        // Clock set back an hour, 900 real seconds passed: expired anyway.
        XCTAssertTrue(UnlockClock.windowExpired(end: end, nowWall: 10_000 + 900 - 3600, bootId: "b1", nowMonotonic: 1000 * sec))
        // Clock set forward: ends early (stricter), fine.
        XCTAssertTrue(UnlockClock.windowExpired(end: end, nowWall: 10_000 + 5000, bootId: "b1", nowMonotonic: 200 * sec))
        // Normal: still open after 100 s.
        XCTAssertFalse(UnlockClock.windowExpired(end: end, nowWall: 10_100, bootId: "b1", nowMonotonic: 200 * sec))
    }

    func testDisplayEndUsesEarlierClock() {
        let end = ClockStamp(wall: 20_000, bootId: "b1", monotonic: 1000 * sec)
        // Wall rewound by 1h; monotonic says 100 s left.
        XCTAssertEqual(UnlockClock.displayEnd(end: end, nowWall: 16_000, bootId: "b1", nowMonotonic: 900 * sec), 16_100, accuracy: 0.001)
        XCTAssertEqual(UnlockClock.displayEnd(end: end, nowWall: 16_000, bootId: "other", nowMonotonic: 900 * sec), 20_000, accuracy: 0.001)
    }
}
