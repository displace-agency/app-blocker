import SwiftUI
import FocusGuardShared

struct StatsTab: View {
    @ObservedObject var daemon: DaemonClient

    var body: some View {
        let s = daemon.stats
        VStack(spacing: FG.Spacing.s) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: FG.Spacing.s), GridItem(.flexible())], spacing: FG.Spacing.s) {
                StatCard(value: "\(s.currentStreakDays)", label: "Current streak", note: "days in a row")
                StatCard(value: "\(s.bestStreakDays)", label: "Best streak", note: "days, your record")
                StatCard(value: "\(s.sessionsCompleted)", label: "Focus sessions", note: "completed")
                StatCard(value: "\(s.focusMinutesToday)", label: "Focus today", note: "minutes")
                StatCard(value: "\(s.completedUnlocks)", label: "Unlocks", note: "all time")
                StatCard(value: "\(s.deniedUnlocks)", label: "Refused unlocks", note: "past the daily limit")
            }
            Spacer(minLength: 0)
        }
    }
}
