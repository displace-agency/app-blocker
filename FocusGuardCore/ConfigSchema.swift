import Foundation
import FocusGuardShared

/// Typed daemon configuration with clamped ranges and validated schedules.
public struct DaemonConfig: Equatable {
    public var version: Int
    public var unlockDelay: Int
    public var maxUnlocksPerDay: Int
    public var cooldownDuration: Int
    public var appCheckInterval: Int
    public var schedules: [Schedule]
    public var workerUrl: String?
    public var workerApiKey: String?

    public init(
        version: Int = FocusGuardConfig.currentConfigVersion,
        unlockDelay: Int = FocusGuardConfig.defaultUnlockDelay,
        maxUnlocksPerDay: Int = FocusGuardConfig.defaultMaxUnlocksPerDay,
        cooldownDuration: Int = FocusGuardConfig.defaultCooldownDuration,
        appCheckInterval: Int = FocusGuardConfig.defaultAppCheckInterval,
        schedules: [Schedule] = [],
        workerUrl: String? = nil,
        workerApiKey: String? = nil
    ) {
        self.version = version
        self.unlockDelay = unlockDelay
        self.maxUnlocksPerDay = maxUnlocksPerDay
        self.cooldownDuration = cooldownDuration
        self.appCheckInterval = appCheckInterval
        self.schedules = schedules
        self.workerUrl = workerUrl
        self.workerApiKey = workerApiKey
    }
}

public enum ConfigSchema {
    public static func clampUnlockDelay(_ v: Int) -> Int { min(86_400, max(60, v)) }
    public static func clampMaxUnlocks(_ v: Int) -> Int { min(20, max(0, v)) }
    public static func clampCooldown(_ v: Int) -> Int { min(14_400, max(60, v)) }
    public static func clampAppInterval(_ v: Int) -> Int { min(120, max(5, v)) }

    /// Parse an already-deserialized JSON object into a clamped, validated config.
    public static func parse(_ json: [String: Any]) -> DaemonConfig {
        var schedules: [Schedule] = []
        if let arr = json["schedules"] as? [[String: Any]] {
            for entry in arr {
                guard let id = entry["id"] as? String,
                      let start = entry["start"] as? String,
                      let end = entry["end"] as? String,
                      let daysArr = entry["days"] as? [Int] else { continue }
                let sched = Schedule(id: id, days: Set(daysArr), start: start, end: end)
                if ScheduleMath.isValid(sched) { schedules.append(sched) }
            }
        }
        return DaemonConfig(
            version: (json["version"] as? Int) ?? 1,
            unlockDelay: clampUnlockDelay((json["unlockDelay"] as? Int) ?? FocusGuardConfig.defaultUnlockDelay),
            maxUnlocksPerDay: clampMaxUnlocks((json["maxUnlocksPerDay"] as? Int) ?? FocusGuardConfig.defaultMaxUnlocksPerDay),
            cooldownDuration: clampCooldown((json["cooldownDuration"] as? Int) ?? FocusGuardConfig.defaultCooldownDuration),
            appCheckInterval: clampAppInterval((json["appCheckInterval"] as? Int) ?? FocusGuardConfig.defaultAppCheckInterval),
            schedules: schedules,
            workerUrl: json["workerUrl"] as? String,
            workerApiKey: json["workerApiKey"] as? String
        )
    }

    /// Parse raw file data; returns clamped defaults if missing/garbage.
    public static func parse(data: Data?) -> DaemonConfig {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DaemonConfig()
        }
        return parse(json)
    }

    /// Serialize to pretty, stable JSON for migration writes.
    public static func serialize(_ config: DaemonConfig) -> Data? {
        var dict: [String: Any] = [
            "version": config.version,
            "unlockDelay": config.unlockDelay,
            "maxUnlocksPerDay": config.maxUnlocksPerDay,
            "cooldownDuration": config.cooldownDuration,
            "appCheckInterval": config.appCheckInterval,
            "schedules": config.schedules.map { sched in
                [
                    "id": sched.id,
                    "days": sched.days.sorted(),
                    "start": sched.start,
                    "end": sched.end,
                ] as [String: Any]
            },
        ]
        if let url = config.workerUrl { dict["workerUrl"] = url }
        if let key = config.workerApiKey { dict["workerApiKey"] = key }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }
}
