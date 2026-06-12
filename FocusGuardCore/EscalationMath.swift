import Foundation

/// One recorded unlock. `bootId` + `monotonic` make the daily budget resistant
/// to wall-clock tampering: a backward clock jump can no longer re-arm the budget.
public struct UnlockRecord: Codable, Equatable {
    public var date: String          // "yyyy-MM-dd" local at time of unlock
    public var timestamp: Double      // wall-clock epoch seconds
    public var bootId: String?        // identity of the boot session
    public var monotonic: UInt64?     // CLOCK_MONOTONIC_RAW nanoseconds at unlock

    public init(date: String, timestamp: Double, bootId: String? = nil, monotonic: UInt64? = nil) {
        self.date = date
        self.timestamp = timestamp
        self.bootId = bootId
        self.monotonic = monotonic
    }
}

public enum EscalationMath {
    private static let nanosPerDay: UInt64 = 24 * 3600 * 1_000_000_000

    /// Escalating unlock delay: base * 2^min(count, 6). Capped to avoid overflow.
    public static func currentDelay(base: Int, unlocksToday: Int) -> Int {
        let count = max(0, min(unlocksToday, 6))
        return base * (1 << count)
    }

    /// Count unlocks toward today's budget. An entry counts if its local date is
    /// `today` OR (same boot AND within the last 24h of monotonic time). The
    /// monotonic clause means rewinding the wall clock cannot reset the budget.
    public static func unlocksToday(
        records: [UnlockRecord],
        today: String,
        currentBootId: String?,
        nowMonotonic: UInt64?
    ) -> Int {
        records.filter { rec in
            if rec.date == today { return true }
            if let boot = currentBootId, let mono = nowMonotonic,
               rec.bootId == boot, let recMono = rec.monotonic {
                let elapsed = mono >= recMono ? mono - recMono : 0
                return elapsed < nanosPerDay
            }
            return false
        }.count
    }

    /// Drop records older than `days` by wall clock to keep the history file small.
    public static func prune(records: [UnlockRecord], now: Double, days: Double = 7) -> [UnlockRecord] {
        let cutoff = now - days * 86400
        return records.filter { $0.timestamp > cutoff }
    }
}
