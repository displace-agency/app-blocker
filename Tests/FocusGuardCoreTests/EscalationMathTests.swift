import XCTest
@testable import FocusGuardCore

final class EscalationMathTests: XCTestCase {
    func testEscalationDoubles() {
        XCTAssertEqual(EscalationMath.currentDelay(base: 1200, unlocksToday: 0), 1200)
        XCTAssertEqual(EscalationMath.currentDelay(base: 1200, unlocksToday: 1), 2400)
        XCTAssertEqual(EscalationMath.currentDelay(base: 1200, unlocksToday: 2), 4800)
    }

    func testEscalationCapsAtSix() {
        XCTAssertEqual(EscalationMath.currentDelay(base: 1000, unlocksToday: 6), 64_000)
        // Beyond 6 stays capped at 2^6.
        XCTAssertEqual(EscalationMath.currentDelay(base: 1000, unlocksToday: 99), 64_000)
    }

    func testCountByDate() {
        let recs = [
            UnlockRecord(date: "2026-06-12", timestamp: 1),
            UnlockRecord(date: "2026-06-12", timestamp: 2),
            UnlockRecord(date: "2026-06-11", timestamp: 3),
        ]
        XCTAssertEqual(EscalationMath.unlocksToday(records: recs, today: "2026-06-12", currentBootId: nil, nowMonotonic: nil), 2)
    }

    func testClockRewindStillCountsViaMonotonic() {
        // Two unlocks happened this boot. The user rewound the wall clock so the
        // date string now reads "yesterday" — but monotonic time still counts them.
        let boot = "boot-A"
        let recs = [
            UnlockRecord(date: "2026-06-12", timestamp: 100, bootId: boot, monotonic: 1_000_000_000),
            UnlockRecord(date: "2026-06-12", timestamp: 200, bootId: boot, monotonic: 2_000_000_000),
        ]
        let now: UInt64 = 3_000_000_000 // 1s after the second unlock
        let count = EscalationMath.unlocksToday(records: recs, today: "2026-06-11", currentBootId: boot, nowMonotonic: now)
        XCTAssertEqual(count, 2, "clock rewind must not reset the budget")
    }

    func testDifferentBootDoesNotCountByMonotonic() {
        let recs = [UnlockRecord(date: "2026-06-12", timestamp: 100, bootId: "old-boot", monotonic: 1_000_000_000)]
        let count = EscalationMath.unlocksToday(records: recs, today: "2026-06-11", currentBootId: "new-boot", nowMonotonic: 2_000_000_000)
        XCTAssertEqual(count, 0)
    }

    func testPrune() {
        let now: Double = 1_000_000
        let recs = [
            UnlockRecord(date: "x", timestamp: now - 1),         // keep
            UnlockRecord(date: "x", timestamp: now - 8 * 86400),  // drop (>7d)
        ]
        XCTAssertEqual(EscalationMath.prune(records: recs, now: now).count, 1)
    }
}
