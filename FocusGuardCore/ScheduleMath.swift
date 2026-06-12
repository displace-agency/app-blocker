import Foundation
import FocusGuardShared

public enum ScheduleMath {
    /// Parse "HH:mm" into minutes-since-midnight. Returns nil if malformed.
    public static func minutes(from hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func isValid(_ s: Schedule) -> Bool {
        guard !s.days.isEmpty, s.days.allSatisfy({ (1...7).contains($0) }) else { return false }
        guard let st = minutes(from: s.start), let en = minutes(from: s.end), st != en else { return false }
        return true
    }

    /// ISO weekday (1=Mon ... 7=Sun) for a date in the given calendar.
    public static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        // Calendar's .weekday is 1=Sunday ... 7=Saturday.
        let w = calendar.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    /// Is any schedule active at `date`?
    public static func isActive(_ schedules: [Schedule], at date: Date, calendar: Calendar) -> Bool {
        for s in schedules where isValid(s) {
            if windowContains(s, date: date, calendar: calendar) { return true }
        }
        return false
    }

    /// Does schedule `s` contain `date`? Handles overnight windows (end <= start).
    public static func windowContains(_ s: Schedule, date: Date, calendar: Calendar) -> Bool {
        guard let start = minutes(from: s.start), let end = minutes(from: s.end) else { return false }
        let weekday = isoWeekday(date, calendar: calendar)
        let nowMin = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if start < end {
            // Same-day window [start, end).
            return s.days.contains(weekday) && nowMin >= start && nowMin < end
        } else {
            // Overnight window: [start, 24:00) on the scheduled day, plus
            // [00:00, end) carried into the following day.
            if s.days.contains(weekday) && nowMin >= start { return true }
            let prevWeekday = weekday == 1 ? 7 : weekday - 1
            if s.days.contains(prevWeekday) && nowMin < end { return true }
            return false
        }
    }

    /// Earliest schedule boundary strictly after `date`, for a UI countdown hint.
    /// Collects start/end edges over the next 8 days; with overlapping schedules
    /// this is an upper bound on the next state change (acceptable for a hint).
    public static func nextTransition(_ schedules: [Schedule], after date: Date, calendar: Calendar) -> Date? {
        let valid = schedules.filter { isValid($0) }
        guard !valid.isEmpty else { return nil }
        var candidates: [Date] = []
        let base = calendar.startOfDay(for: date)
        for dayOffset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: base) else { continue }
            let weekday = isoWeekday(day, calendar: calendar)
            for s in valid {
                guard s.days.contains(weekday),
                      let st = minutes(from: s.start), let en = minutes(from: s.end) else { continue }
                if let startDate = calendar.date(byAdding: .minute, value: st, to: day), startDate > date {
                    candidates.append(startDate)
                }
                // Same-day window ends on `day`; overnight window ends on the next day.
                let endDayBase = st < en ? day : (calendar.date(byAdding: .day, value: 1, to: day) ?? day)
                if let endDate = calendar.date(byAdding: .minute, value: en, to: endDayBase), endDate > date {
                    candidates.append(endDate)
                }
            }
        }
        return candidates.min()
    }
}
