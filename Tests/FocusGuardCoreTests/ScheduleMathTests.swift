import XCTest
@testable import FocusGuardCore
import FocusGuardShared

final class ScheduleMathTests: XCTestCase {
    // A fixed calendar so tests are timezone-stable.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    // 2026-06-12 is a Friday (ISO weekday 5).
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testMinutesParsing() {
        XCTAssertEqual(ScheduleMath.minutes(from: "09:30"), 570)
        XCTAssertEqual(ScheduleMath.minutes(from: "00:00"), 0)
        XCTAssertNil(ScheduleMath.minutes(from: "24:00"))
        XCTAssertNil(ScheduleMath.minutes(from: "9:5:5"))
        XCTAssertNil(ScheduleMath.minutes(from: "ab:cd"))
    }

    func testIsoWeekday() {
        XCTAssertEqual(ScheduleMath.isoWeekday(date(2026, 6, 12, 12, 0), calendar: cal), 5) // Friday
        XCTAssertEqual(ScheduleMath.isoWeekday(date(2026, 6, 14, 12, 0), calendar: cal), 7) // Sunday
    }

    func testValidation() {
        XCTAssertTrue(ScheduleMath.isValid(Schedule(id: "a", days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00")))
        XCTAssertFalse(ScheduleMath.isValid(Schedule(id: "b", days: [], start: "09:00", end: "17:00")))
        XCTAssertFalse(ScheduleMath.isValid(Schedule(id: "c", days: [1], start: "09:00", end: "09:00")))
        XCTAssertFalse(ScheduleMath.isValid(Schedule(id: "d", days: [8], start: "09:00", end: "17:00")))
    }

    func testSameDayWindow() {
        let work = Schedule(id: "w", days: [1, 2, 3, 4, 5], start: "09:00", end: "17:30")
        XCTAssertTrue(ScheduleMath.isActive([work], at: date(2026, 6, 12, 10, 0), calendar: cal))  // Fri 10:00
        XCTAssertFalse(ScheduleMath.isActive([work], at: date(2026, 6, 12, 18, 0), calendar: cal)) // Fri 18:00
        XCTAssertFalse(ScheduleMath.isActive([work], at: date(2026, 6, 13, 10, 0), calendar: cal)) // Sat
        XCTAssertFalse(ScheduleMath.isActive([work], at: date(2026, 6, 12, 17, 30), calendar: cal)) // exclusive end
    }

    func testOvernightWindow() {
        // Block 22:00–06:00 on Fridays (carries into Saturday morning).
        let night = Schedule(id: "n", days: [5], start: "22:00", end: "06:00")
        XCTAssertTrue(ScheduleMath.isActive([night], at: date(2026, 6, 12, 23, 0), calendar: cal))  // Fri 23:00
        XCTAssertTrue(ScheduleMath.isActive([night], at: date(2026, 6, 13, 5, 0), calendar: cal))    // Sat 05:00 (carry)
        XCTAssertFalse(ScheduleMath.isActive([night], at: date(2026, 6, 13, 7, 0), calendar: cal))   // Sat 07:00
        XCTAssertFalse(ScheduleMath.isActive([night], at: date(2026, 6, 12, 21, 0), calendar: cal))  // Fri 21:00
    }

    func testNextTransition() {
        let work = Schedule(id: "w", days: [1, 2, 3, 4, 5], start: "09:00", end: "17:00")
        // From Friday 08:00, next boundary is Friday 09:00.
        let next = ScheduleMath.nextTransition([work], after: date(2026, 6, 12, 8, 0), calendar: cal)
        XCTAssertEqual(next, date(2026, 6, 12, 9, 0))
    }
}
