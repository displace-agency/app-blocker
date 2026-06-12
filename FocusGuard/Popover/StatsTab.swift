import SwiftUI
import FocusGuardShared

struct StatsTab: View {
    @ObservedObject var daemon: DaemonClient

    var body: some View {
        let s = daemon.stats
        VStack(spacing: FG.Spacing.s) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FG.Spacing.s) {
                StatCard(value: "\(s.currentStreakDays)d", label: "Current streak", symbol: "flame.fill")
                StatCard(value: "\(s.bestStreakDays)d", label: "Best streak", symbol: "trophy.fill")
                StatCard(value: "\(s.sessionsCompleted)", label: "Focus sessions", symbol: "hourglass")
                StatCard(value: "\(s.focusMinutesToday)m", label: "Focus today", symbol: "timer")
                StatCard(value: "\(s.completedUnlocks)", label: "Total unlocks", symbol: "lock.open")
                StatCard(value: "\(s.deniedUnlocks)", label: "Blocked attempts", symbol: "hand.raised.fill")
            }
            Spacer(minLength: 0)
        }
    }
}
