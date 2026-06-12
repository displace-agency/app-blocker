import SwiftUI
import AppKit
import FocusGuardShared

struct RootView: View {
    @ObservedObject var daemon: DaemonClient
    @State private var tab: Tab = .sites
    @FocusState private var addFieldFocused: Bool

    enum Tab: Int, CaseIterable { case sites, apps, schedule, stats
        var title: String {
            switch self {
            case .sites: return L10n.Tab.sites
            case .apps: return L10n.Tab.apps
            case .schedule: return L10n.Tab.schedule
            case .stats: return L10n.Tab.stats
            }
        }
        var symbol: String {
            switch self {
            case .sites: return "globe"
            case .apps: return "app.badge"
            case .schedule: return "calendar"
            case .stats: return "chart.bar.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if daemon.isOffline || daemon.isDaemonOutdated {
                OfflineBanner(outdated: daemon.isDaemonOutdated && !daemon.isOffline)
            }
            Divider().overlay(FG.Palette.hairline)
            tabPicker
            Divider().overlay(FG.Palette.hairline)
            ScrollView { content.padding(FG.Spacing.m) }
                .frame(height: 286)
            Divider().overlay(FG.Palette.hairline)
            actionZone
            Divider().overlay(FG.Palette.hairline)
            footer
        }
        .frame(width: FG.Layout.popover.width)
        .background(FG.Palette.bgDark)
        .overlay(ToastOverlay(toasts: daemon.toasts))
        .background(
            Button("") { tab = .sites; addFieldFocused = true }
                .keyboardShortcut("n", modifiers: .command).opacity(0)
        )
        .onAppear { daemon.refresh() }
    }

    // MARK: - Header

    private var style: FG.StatusStyle { daemon.isOffline ? .offline : FG.StatusStyle(daemon.status) }

    private var header: some View {
        HStack(spacing: FG.Spacing.m) {
            Image(systemName: style.symbol).font(.title2).foregroundColor(style.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.appName).font(.headline)
                UnlockDots(total: daemon.maxUnlocksPerDay, used: daemon.unlocksToday)
            }
            Spacer()
            StatusPill(style: style, subtitle: countdownSubtitle)
        }
        .padding(FG.Spacing.m)
        .accessibilityElement(children: .contain)
    }

    private var countdownSubtitle: String? {
        switch daemon.status {
        case .unlockPending: return nil // shown live in action zone
        case .unlocked: return daemon.outsideScheduledHours ? "free" : nil
        default: return nil
        }
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { t in
                Button { withAnimation(FG.Motion.quick) { tab = t } } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol).font(.system(size: 12))
                        Text(t.title).font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FG.Spacing.s)
                    .foregroundColor(tab == t ? FG.Palette.emerald : .secondary)
                    .background(tab == t ? FG.Palette.emerald.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(t.rawValue + 1)")), modifiers: .command)
                .accessibilityLabel(t.title)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .sites: SitesTab(daemon: daemon, addFieldFocused: $addFieldFocused)
        case .apps: AppsTab(daemon: daemon)
        case .schedule: ScheduleTab(daemon: daemon)
        case .stats: StatsTab(daemon: daemon)
        }
    }

    // MARK: - Action zone

    private var actionZone: some View {
        VStack(spacing: FG.Spacing.s) {
            if daemon.sessionActive {
                sessionCard
            } else {
                Menu {
                    ForEach([25, 50, 90], id: \.self) { mins in
                        Button("\(mins) minutes") { daemon.startSession(minutes: mins) }
                    }
                } label: {
                    Label(L10n.Action.startSession, systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .padding(.vertical, 6)
                .background(FG.Palette.bgCard, in: RoundedRectangle(cornerRadius: FG.Radius.m))

                primaryAction
            }
        }
        .padding(FG.Spacing.m)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch daemon.status {
        case .locked:
            if daemon.unlocksToday >= daemon.maxUnlocksPerDay {
                Button {} label: { Label(L10n.Action.budgetExhausted, systemImage: "lock.fill").frame(maxWidth: .infinity) }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(.gray).disabled(true)
            } else {
                VStack(spacing: 2) {
                    Button { NotificationCenter.default.post(name: .focusGuardShowUnlock, object: nil) } label: {
                        Label(L10n.Action.requestUnlock, systemImage: "lock.open").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(.orange)
                    if daemon.isEscalated {
                        Text("Wait escalated to \(daemon.unlockDelayMinutes) min").font(.caption2).foregroundColor(.orange)
                    }
                }
            }
        case .unlockPending:
            VStack(spacing: 4) {
                if let deadline = daemon.unlockDeadline {
                    CountdownText(deadline: deadline, prefix: "Unlocks in ", color: .orange).font(.callout).fontWeight(.semibold)
                }
                Button { daemon.cancelUnlock() } label: { Label(L10n.Action.cancelUnlock, systemImage: "xmark").frame(maxWidth: .infinity) }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(.gray)
            }
        case .unlocked:
            VStack(spacing: 4) {
                if let deadline = daemon.cooldownDeadline {
                    CountdownText(deadline: deadline, prefix: "Auto-lock in ", color: .red).font(.caption).fontWeight(.medium)
                }
                Button { daemon.requestLock() } label: { Label(L10n.Action.lockNow, systemImage: "lock").frame(maxWidth: .infinity) }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(FG.Palette.emerald)
            }
        case .focusSession:
            EmptyView()
        }
    }

    private var sessionCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass").foregroundColor(style.color)
                Text(L10n.Session.active).font(.callout).fontWeight(.semibold)
            }
            if let deadline = daemon.sessionDeadline {
                CountdownText(deadline: deadline, prefix: "", color: style.color).font(.title3).fontWeight(.bold)
            }
            Text(L10n.Session.subtitle).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(FG.Spacing.m)
        .background(style.color.opacity(0.12), in: RoundedRectangle(cornerRadius: FG.Radius.l))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: FG.Spacing.s) {
            Image(systemName: "iphone").font(.caption2).foregroundColor(hasPasscode ? FG.Palette.emerald : .secondary)
            if hasPasscode, daemon.status == .unlocked, let code = screenTimePasscode {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: { Label(code, systemImage: "key").font(.caption2) }
                .buttonStyle(.plain).foregroundColor(.orange)
            } else {
                Text(hasPasscode ? "iPhone protected" : "iPhone")
                    .font(.caption2).foregroundColor(hasPasscode ? FG.Palette.emerald : .secondary)
                if !hasPasscode {
                    Button("Set Up") { NotificationCenter.default.post(name: .focusGuardShowiPhoneSetup, object: nil) }
                        .font(.caption2).buttonStyle(.borderedProminent).tint(FG.Palette.emerald).controlSize(.mini)
                }
            }
            Spacer()
            Circle().fill(daemon.isOffline ? Color.red : FG.Palette.emerald).frame(width: 6, height: 6)
            Text(daemon.isOffline ? "Offline" : "Active").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, FG.Spacing.m).padding(.vertical, FG.Spacing.s)
    }

    private var hasPasscode: Bool { screenTimePasscode != nil }
    private var screenTimePasscode: String? {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusGuard/screentime_passcode")
        if let code = try? String(contentsOf: appSupport, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            return code
        }
        return try? String(contentsOfFile: "/etc/focusguard/.screentime_passcode", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Drift-free countdown driven by the daemon's deadline timestamp.
struct CountdownText: View {
    let deadline: Date
    var prefix: String = ""
    var color: Color = .primary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date)))
            Text("\(prefix)\(FG.formatTime(remaining))")
                .monospacedDigit().foregroundColor(color)
                .accessibilityLabel("\(prefix.isEmpty ? "Remaining" : prefix) \(remaining / 60) minutes \(remaining % 60) seconds")
        }
    }
}
