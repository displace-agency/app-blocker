import Foundation
import FocusGuardShared
import FocusGuardCore

/// Persistent usage counters. DNS hit counting is not feasible with hosts-file
/// blocking (no signal), so we track lifecycle events the daemon can observe.
struct StatsData: Codable {
    var version: Int = 1
    var unlockRequests: Int = 0
    var completedUnlocks: Int = 0
    var deniedUnlocks: Int = 0
    var sessionsStarted: Int = 0
    var sessionsCompleted: Int = 0
    var hostsRewrites: Int = 0
    var appsKilled: Int = 0
    var lastUnlockDate: String? = nil
    var firstSeenDate: String? = nil
    var bestStreakDays: Int = 0
    var daily: [String: DailyStat] = [:]

    struct DailyStat: Codable {
        var unlocks: Int = 0
        var sessions: Int = 0
        var focusMinutes: Int = 0
    }
}

final class StatsStore {
    private let path: String
    private var data: StatsData
    private let log: (String) -> Void

    init(path: String, today: String, log: @escaping (String) -> Void) {
        self.path = path
        self.log = log
        if let raw = FileManager.default.contents(atPath: path),
           let decoded = try? JSONDecoder().decode(StatsData.self, from: raw) {
            data = decoded
        } else {
            data = StatsData()
        }
        if data.firstSeenDate == nil { data.firstSeenDate = today }
        save()
    }

    // MARK: - Mutations

    func recordUnlockRequest() { data.unlockRequests += 1; save() }
    func recordDeniedUnlock() { data.deniedUnlocks += 1; save() }
    func recordHostsRewrite() { data.hostsRewrites += 1; save() }
    func recordAppsKilled(_ n: Int) { guard n > 0 else { return }; data.appsKilled += n; save() }

    func recordCompletedUnlock(today: String) {
        data.completedUnlocks += 1
        data.lastUnlockDate = today
        var day = data.daily[today] ?? .init()
        day.unlocks += 1
        data.daily[today] = day
        pruneDaily()
        save()
    }

    func recordSessionStarted(today: String) {
        data.sessionsStarted += 1
        var day = data.daily[today] ?? .init()
        day.sessions += 1
        data.daily[today] = day
        pruneDaily()
        save()
    }

    func recordSessionCompleted(today: String, minutes: Int) {
        data.sessionsCompleted += 1
        var day = data.daily[today] ?? .init()
        day.focusMinutes += max(0, minutes)
        data.daily[today] = day
        pruneDaily()
        save()
    }

    // MARK: - Summary

    /// Current streak = whole days since the last unlock (or since first seen if
    /// never unlocked). Computed from date strings so wall-clock games can't
    /// inflate it past real elapsed days.
    func summary(today: String) -> StatsSummary {
        let anchor = data.lastUnlockDate ?? data.firstSeenDate ?? today
        let streak = max(0, daysBetween(anchor, today))
        if streak > data.bestStreakDays {
            data.bestStreakDays = streak
            save()
        }
        let todayStat = data.daily[today]
        return StatsSummary(
            completedUnlocks: data.completedUnlocks,
            sessionsCompleted: data.sessionsCompleted,
            currentStreakDays: streak,
            bestStreakDays: data.bestStreakDays,
            unlockRequests: data.unlockRequests,
            deniedUnlocks: data.deniedUnlocks,
            focusMinutesToday: todayStat?.focusMinutes ?? 0
        )
    }

    // MARK: - Helpers

    private func pruneDaily() {
        guard data.daily.count > 30 else { return }
        let keep = data.daily.keys.sorted().suffix(30)
        data.daily = data.daily.filter { keep.contains($0.key) }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            AtomicFile.write(encoded, to: path, mode: 0o644, owner: 0, group: 0)
        }
    }

    private func daysBetween(_ from: String, _ to: String) -> Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        guard let a = fmt.date(from: from), let b = fmt.date(from: to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
