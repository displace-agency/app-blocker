import XCTest
@testable import FocusGuardCore
import FocusGuardShared

final class ConfigSchemaTests: XCTestCase {
    func testDefaultsOnGarbage() {
        let cfg = ConfigSchema.parse(data: Data("not json".utf8))
        XCTAssertEqual(cfg.unlockDelay, FocusGuardConfig.defaultUnlockDelay)
        XCTAssertEqual(cfg.maxUnlocksPerDay, FocusGuardConfig.defaultMaxUnlocksPerDay)
        XCTAssertTrue(cfg.schedules.isEmpty)
    }

    func testDefaultsOnNil() {
        let cfg = ConfigSchema.parse(data: nil)
        XCTAssertEqual(cfg.cooldownDuration, FocusGuardConfig.defaultCooldownDuration)
        XCTAssertEqual(cfg.appCheckInterval, FocusGuardConfig.defaultAppCheckInterval)
    }

    func testClamping() {
        let json: [String: Any] = [
            "unlockDelay": 5,          // below min 60
            "maxUnlocksPerDay": 999,   // above max 20
            "cooldownDuration": 1,     // below min 60
            "appCheckInterval": 1,     // below min 5
        ]
        let cfg = ConfigSchema.parse(json)
        XCTAssertEqual(cfg.unlockDelay, 60)
        XCTAssertEqual(cfg.maxUnlocksPerDay, 20)
        XCTAssertEqual(cfg.cooldownDuration, 60)
        XCTAssertEqual(cfg.appCheckInterval, 5)
    }

    func testV1ConfigParsesWithoutNewFields() {
        let json: [String: Any] = ["unlockDelay": 1200, "maxUnlocksPerDay": 2, "cooldownDuration": 900]
        let cfg = ConfigSchema.parse(json)
        XCTAssertEqual(cfg.version, 1)
        XCTAssertEqual(cfg.appCheckInterval, FocusGuardConfig.defaultAppCheckInterval)
    }

    func testInvalidSchedulesDropped() {
        let json: [String: Any] = [
            "schedules": [
                ["id": "ok", "days": [1, 2, 3, 4, 5], "start": "09:00", "end": "17:00"],
                ["id": "bad-time", "days": [1], "start": "09:00", "end": "09:00"],
                ["id": "bad-day", "days": [9], "start": "09:00", "end": "17:00"],
            ],
        ]
        let cfg = ConfigSchema.parse(json)
        XCTAssertEqual(cfg.schedules.count, 1)
        XCTAssertEqual(cfg.schedules.first?.id, "ok")
    }

    func testRoundTripSerialize() {
        let cfg = DaemonConfig(
            version: 2,
            schedules: [Schedule(id: "w", days: [1, 2, 3, 4, 5], start: "09:00", end: "17:30")]
        )
        let data = ConfigSchema.serialize(cfg)
        XCTAssertNotNil(data)
        let reparsed = ConfigSchema.parse(data: data)
        XCTAssertEqual(reparsed.version, 2)
        XCTAssertEqual(reparsed.schedules.count, 1)
        XCTAssertEqual(reparsed.schedules.first?.days, [1, 2, 3, 4, 5])
    }
}
