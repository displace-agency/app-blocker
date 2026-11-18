import SwiftUI
import AppKit
import FocusGuardShared

struct RootView: View {
    @ObservedObject var daemon: DaemonClient
    @ObservedObject var notifier: UnlockNotifier
    @State private var tab: Tab
    @FocusState private var addFieldFocused: Bool
    private let startWithGroups: Bool

    init(daemon: DaemonClient, notifier: UnlockNotifier, tab: Tab = .sites, showGroups: Bool = false) {
        _daemon = ObservedObject(wrappedValue: daemon)
        _notifier = ObservedObject(wrappedValue: notifier)
        _tab = State(initialValue: tab)
        startWithGroups = showGroups
    }

    enum Tab: Int, CaseIterable { case sites, apps, schedule, stats
        var title: String {
            switch self {
            case .sites: return L10n.Tab.sites
            case .apps: return L10n.Tab.apps
            case .schedule: return L10n.Tab.schedule
            case .stats: return L10n.Tab.stats
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if daemon.isOffline || daemon.isDaemonOutdated {
                OfflineBanner(outdated: daemon.isDaemonOutdated && !daemon.isOffline)
            }
            if notifier.permission == .denied {
                NotificationsOffBanner()
            }
            #if !PUBLIC_BUILD
            // Owner-only: the profiles are extras the public installer does not ship.
            if !daemon.missingProtections.isEmpty && !daemon.isOffline {
                ProtectionMissingBanner(missing: daemon.missingProtections)
            }
            #endif
            if daemon.browserProfileStale {
                BrowserProfileBanner(domains: daemon.browserOnlyBlocked.sorted())
            }
            tabPicker
            ScrollView { content.padding(FG.Spacing.m) }
                .frame(height: 286)
                .background(FG.canvas)
            Divider().overlay(FG.hairline)
            actionZone
            Divider().overlay(FG.hairline)
            footer
        }
        .frame(width: FG.Layout.popover.width)
        .background(FG.surface)
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
        HStack(alignment: .top, spacing: FG.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.appName).fgTitle()
                Text(stateSentence).font(FG.captionFont).foregroundColor(FG.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            StatusPill(style: style, subtitle: countdownSubtitle)
        }
        .padding(.horizontal, FG.Spacing.m)
        .padding(.top, FG.Spacing.m)
        .padding(.bottom, FG.Spacing.s)
        .background(FG.surface)
        .accessibilityElement(children: .contain)
    }

    /// One caption line that says the state in words.
    private var stateSentence: String {
        if daemon.isOffline { return "Can't reach the blocker." }
        let left = max(0, daemon.maxUnlocksPerDay - daemon.unlocksToday)
        let budget = "\(left) of \(daemon.maxUnlocksPerDay) unlocks left today."
        switch daemon.status {
        case .locked: return "Locked. \(budget)"
        case .unlockPending: return "Unlock requested. \(left) of \(daemon.maxUnlocksPerDay) left today."
        case .unlocked: return daemon.outsideScheduledHours ? "Open outside scheduled hours." : "Unlocked. Auto-lock is running."
        case .focusSession: return "Focus session in progress."
        }
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
        HStack(spacing: FG.Spacing.l) {
            ForEach(Tab.allCases, id: \.rawValue) { t in
                let on = tab == t
                Button { withAnimation(FG.Motion.quick) { tab = t } } label: {
                    Text(t.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(on ? FG.ink : FG.inkSecondary)
                        .padding(.vertical, FG.Spacing.s)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(on ? FG.ink : Color.clear).frame(height: 1.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(t.rawValue + 1)")), modifiers: .command)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FG.Spacing.m)
        .background(FG.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(FG.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .sites: SitesTab(daemon: daemon, addFieldFocused: $addFieldFocused, showGroups: startWithGroups)
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
                switch daemon.status {
                case .locked:
                    VStack(spacing: 6) {
                        HStack(spacing: FG.Spacing.s) {
                            startFocusMenu
                            if daemon.unlocksToday >= daemon.maxUnlocksPerDay {
                                Button {} label: { Text(L10n.Action.budgetExhausted).lineLimit(1).minimumScaleFactor(0.8) }
                                    .buttonStyle(.fgSecondary).disabled(true)
                            } else {
                                Button { NotificationCenter.default.post(name: .focusGuardShowUnlock, object: nil) } label: {
                                    Text(L10n.Action.requestUnlock)
                                }
                                .buttonStyle(.fgSecondary)
                            }
                        }
                        if daemon.isEscalated && daemon.unlocksToday < daemon.maxUnlocksPerDay {
                            Text("Wait escalated to \(daemon.unlockDelayMinutes) min")
                                .font(FG.captionFont).foregroundColor(FG.accent)
                        }
                    }
                case .unlockPending:
                    VStack(spacing: FG.Spacing.s) {
                        if let deadline = daemon.unlockDeadline {
                            CountdownText(deadline: deadline, prefix: "Unlocks in ", color: FG.accent)
                                .font(.system(size: 15, weight: .medium))
                        }
                        HStack(spacing: FG.Spacing.s) {
                            startFocusMenu
                            Button { daemon.cancelUnlock() } label: { Text(L10n.Action.cancelUnlock) }
                                .buttonStyle(.fgSecondary)
                        }
                    }
                case .unlocked:
                    VStack(spacing: FG.Spacing.s) {
                        if let deadline = daemon.cooldownDeadline {
                            CountdownText(deadline: deadline, prefix: "Auto-lock in ", color: FG.danger)
                                .font(.system(size: 12, weight: .medium))
                        }
                        HStack(spacing: FG.Spacing.s) {
                            startFocusMenu
                            Button { daemon.requestLock() } label: { Text(L10n.Action.lockNow) }
                                .buttonStyle(.fgSecondary)
                        }
                    }
                case .focusSession:
                    EmptyView()
                }
            }
        }
        .padding(FG.Spacing.m)
        .background(FG.surface)
    }

    /// Primary action, equal width with its neighbour; keeps the 25/50/90 minute menu.
    private var startFocusMenu: some View {
        Menu {
            ForEach([25, 50, 90], id: \.self) { mins in
                Button("\(mins) minutes") { daemon.startSession(minutes: mins) }
            }
        } label: {
            Text(L10n.Action.startSession)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.fgPrimary)
        .accessibilityLabel(L10n.Action.startSession)
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.Session.title).fgEyebrow()
            if let deadline = daemon.sessionDeadline {
                CountdownText(deadline: deadline, prefix: "", color: FG.ink).font(FG.bigNumber(28))
            }
            Text(L10n.Session.subtitle).fgCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(FG.Spacing.m)
        .fgCard()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: FG.Spacing.s) {
            Circle().fill(daemon.isOffline ? FG.inkTertiary : FG.ink).frame(width: 6, height: 6)
            Text(daemon.isOffline ? "Offline" : "Active").font(FG.captionFont).foregroundColor(FG.inkSecondary)
            #if !PUBLIC_BUILD
            Text("·").font(FG.captionFont).foregroundColor(FG.inkTertiary)
            Image(systemName: "iphone").font(.system(size: 10)).foregroundColor(hasPasscode ? FG.ink : FG.inkSecondary)
            if hasPasscode, daemon.status == .unlocked, let code = screenTimePasscode {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: { Label(code, systemImage: "key").font(FG.captionFont) }
                .buttonStyle(.plain).foregroundColor(FG.accent)
            } else {
                Text(hasPasscode ? "iPhone protected" : "iPhone")
                    .font(FG.captionFont).foregroundColor(FG.inkSecondary)
                if !hasPasscode {
                    Button("Set up") { NotificationCenter.default.post(name: .focusGuardShowiPhoneSetup, object: nil) }
                        .buttonStyle(.fgSecondarySmall)
                }
            }
            #endif
            Spacer()
            Text("By Displace").fgEyebrow()
        }
        .padding(.horizontal, FG.Spacing.m).padding(.vertical, FG.Spacing.s)
        .background(FG.surface)
    }

    private var hasPasscode: Bool { screenTimePasscode != nil }
    private var screenTimePasscode: String? {
        if daemon.isDemo { return nil }
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
    var color: Color = FG.ink

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date)))
            Text("\(prefix)\(FG.formatTime(remaining))")
                .monospacedDigit().foregroundColor(color)
                .accessibilityLabel("\(prefix.isEmpty ? "Remaining" : prefix) \(remaining / 60) minutes \(remaining % 60) seconds")
        }
    }
}
