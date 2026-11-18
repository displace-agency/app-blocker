import SwiftUI
import FocusGuardShared

struct StatsTab: View {
    @ObservedObject var daemon: DaemonClient

    var body: some View {
        let s = daemon.stats
        VStack(spacing: FG.Spacing.s) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: FG.Spacing.s), GridItem(.flexible())], spacing: FG.Spacing.s) {
                StatCard(value: "\(s.currentStreakDays)d", label: "Current streak", note: "days in a row")
                StatCard(value: "\(s.bestStreakDays)d", label: "Best streak", note: "your record")
                StatCard(value: "\(s.sessionsCompleted)", label: "Focus sessions", note: "completed")
                StatCard(value: "\(s.focusMinutesToday)m", label: "Focus today", note: "minutes focused")
                StatCard(value: "\(s.completedUnlocks)", label: "Total unlocks", note: "all time")
                StatCard(value: "\(s.deniedUnlocks)", label: "Blocked attempts", note: "unlocks denied")
            }
            Spacer(minLength: 0)
        }
    }
}
