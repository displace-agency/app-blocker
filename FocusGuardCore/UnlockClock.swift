import Foundation

/// A moment recorded on both clocks. Wall time alone can be moved by the user
/// (System Settings > Date & Time); CLOCK_MONOTONIC_RAW cannot, but it resets on
/// reboot, so `bootId` says whether the monotonic value is still comparable.
public struct ClockStamp: Codable, Equatable, Sendable {
    public var wall: Double        // epoch seconds
    public var bootId: String?
    public var monotonic: UInt64?  // CLOCK_MONOTONIC_RAW nanoseconds (counts during sleep)

    public init(wall: Double, bootId: String? = nil, monotonic: UInt64? = nil) {
        self.wall = wall
        self.bootId = bootId
        self.monotonic = monotonic
    }

    /// Reads a stamp file. Accepts the legacy format (a bare JSON number of epoch
    /// seconds) so an update never loses a pending unlock or an open window.
    public static func decode(_ data: Data) -> ClockStamp? {
        if let s = try? JSONDecoder().decode(ClockStamp.self, from: data) { return s }
        if let wall = try? JSONDecoder().decode(Double.self, from: data) { return ClockStamp(wall: wall) }
        return nil
    }
}

/// Tamper-resistant timing for the unlock flow. Rules: moving the wall clock can
/// only make FocusGuard STRICTER, never looser.
public enum UnlockClock {
    private static let nanosPerSecond: Double = 1_000_000_000

    /// Seconds elapsed since `start`. Within the same boot it is the SMALLER of the
    /// wall and monotonic readings, so jumping the clock forward cannot skip the delay.
    public static func elapsed(since start: ClockStamp, nowWall: Double, bootId: String?, nowMonotonic: UInt64?) -> Double {
        let wallElapsed = nowWall - start.wall
        if let b = bootId, start.bootId == b, let m0 = start.monotonic, let m1 = nowMonotonic, m1 >= m0 {
            return min(wallElapsed, Double(m1 - m0) / nanosPerSecond)
        }
        return wallElapsed
    }

    /// True once the unlock delay has passed on every clock we can trust.
    public static func delayElapsed(request: ClockStamp, delaySeconds: Int, nowWall: Double, bootId: String?, nowMonotonic: UInt64?) -> Bool {
        elapsed(since: request, nowWall: nowWall, bootId: bootId, nowMonotonic: nowMonotonic) >= Double(delaySeconds)
    }

    /// End of an unlock window opened at `opened` for `durationSeconds`.
    public static func windowEnd(opened: ClockStamp, durationSeconds: Int) -> ClockStamp {
        ClockStamp(
            wall: opened.wall + Double(durationSeconds),
            bootId: opened.bootId,
            monotonic: opened.monotonic.map { $0 + UInt64(max(0, durationSeconds)) * 1_000_000_000 }
        )
    }

    /// The unlock window is over as soon as EITHER clock says so: setting the clock
    /// back cannot stretch it, setting it forward only ends it sooner.
    public static func windowExpired(end: ClockStamp, nowWall: Double, bootId: String?, nowMonotonic: UInt64?) -> Bool {
        if nowWall >= end.wall { return true }
        if let b = bootId, end.bootId == b, let e = end.monotonic, let m = nowMonotonic, m >= e { return true }
        return false
    }

    /// Wall-clock time the window will end, for display and notifications: the
    /// earlier of the stored wall end and the monotonic remainder projected onto now.
    public static func displayEnd(end: ClockStamp, nowWall: Double, bootId: String?, nowMonotonic: UInt64?) -> Double {
        if let b = bootId, end.bootId == b, let e = end.monotonic, let m = nowMonotonic {
            let remaining = e > m ? Double(e - m) / nanosPerSecond : 0
            return min(end.wall, nowWall + remaining)
        }
        return end.wall
    }
}
