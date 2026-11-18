import SwiftUI
import FocusGuardShared

// MARK: - Status pill

struct StatusPill: View {
    let style: FG.StatusStyle
    var subtitle: String?

    var body: some View {
        HStack(spacing: 4) {
            glyph
            Text(style.label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(FG.titleTracking)
        }
        .foregroundColor(style.pillText)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            ZStack {
                if style == .focusSession { Capsule().fill(FG.ink) }
                Capsule().fill(style.pillFill).padding(style == .focusSession ? 1 : 0)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle == nil ? style.label : "\(style.label), \(subtitle!)")
    }

    @ViewBuilder private var glyph: some View {
        switch style {
        case .unlockPending:
            Circle().fill(FG.accent).frame(width: 6, height: 6)
        case .offline:
            Circle().fill(FG.inkTertiary).frame(width: 6, height: 6)
        case .locked:
            Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
        case .unlocked:
            Image(systemName: "lock.open.fill").font(.system(size: 8, weight: .bold))
        case .focusSession:
            Image(systemName: "hourglass").font(.system(size: 9, weight: .semibold))
        }
    }
}

// MARK: - Daily unlock budget dots

struct UnlockDots: View {
    let total: Int
    let used: Int

    var body: some View {
        let remaining = max(0, total - used)
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Circle()
                    .fill(i < remaining ? FG.ink : FG.border)
                    .frame(width: 6, height: 6)
            }
            Text("\(remaining) left").font(FG.captionFont).foregroundColor(FG.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remaining) of \(total) unlocks remaining today")
    }
}

// MARK: - Banner (one style for every notice)

/// Surface row with a 2pt accent rule on the left, ink title, caption body and an
/// optional small Secondary button.
struct FGBanner: View {
    let title: String
    var message: String?
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: FG.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(FG.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message).font(FG.captionFont).foregroundColor(FG.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let action, let onAction {
                Button(action, action: onAction).buttonStyle(.fgSecondarySmall)
            }
        }
        .padding(.horizontal, FG.Spacing.m)
        .padding(.vertical, FG.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FG.surface)
        .overlay(alignment: .leading) { Rectangle().fill(FG.accent).frame(width: 2) }
        .overlay(alignment: .bottom) { Rectangle().fill(FG.hairline).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

private struct CopyCommand: View {
    let command: String
    var body: some View {
        HStack {
            Text(command)
                .font(.system(size: 11, design: .monospaced)).foregroundColor(FG.ink)
                .textSelection(.enabled)
                .padding(6)
                .background(FG.canvas, in: RoundedRectangle(cornerRadius: FG.Radius.control))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: { Image(systemName: "doc.on.doc").foregroundColor(FG.inkSecondary) }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Offline / outdated banner

struct OfflineBanner: View {
    let outdated: Bool
    @State private var showHelp = false

    var body: some View {
        FGBanner(title: outdated ? L10n.Offline.outdated : L10n.Offline.banner,
                 action: "Help") { showHelp.toggle() }
        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: FG.Spacing.s) {
                Text(L10n.Offline.help).font(FG.captionFont).foregroundColor(FG.inkSecondary)
                CopyCommand(command: L10n.Offline.command)
            }
            .padding(FG.Spacing.m)
            .frame(width: 320)
        }
    }
}

// MARK: - Browser-profile staleness banner

/// Honest surface for FocusGuard's second enforcement plane: the installed browser
/// policy profile (`URLBlocklist`) keeps blocking sites pre-network regardless of the
/// daemon's lock state, so a removed site (or any site during an unlock window) can
/// still show "blocked" in the browser. We say so plainly instead of implying access.
struct BrowserProfileBanner: View {
    let domains: [String]
    @State private var showHelp = false

    private let command = "bash Scripts/make-browser-profile.sh"

    var body: some View {
        FGBanner(title: "\(domains.count) site\(domains.count == 1 ? "" : "s") still blocked in your browser",
                 action: "Help") { showHelp.toggle() }
        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: FG.Spacing.s) {
                Text("Your browser enforces a separate installed profile. These sites stay blocked in the browser even when FocusGuard's live list or an active unlock would allow them — FocusGuard can't live-edit that profile.")
                    .font(FG.captionFont).foregroundColor(FG.inkSecondary)
                if !domains.isEmpty {
                    Text(domains.joined(separator: ", "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(FG.inkSecondary)
                        .textSelection(.enabled)
                }
                Text("To re-sync the browser profile to your current block list, regenerate and reinstall it:")
                    .font(FG.captionFont).foregroundColor(FG.inkSecondary)
                CopyCommand(command: command)
            }
            .padding(FG.Spacing.m)
            .frame(width: 320)
        }
    }
}

// MARK: - Stat card

struct StatCard: View {
    let value: String
    let label: String
    var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(FG.ink)
            Text(value).font(FG.bigNumber(22)).foregroundColor(FG.ink)
            Text(note).font(FG.captionFont).foregroundColor(FG.inkSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FG.Spacing.m).padding(.vertical, FG.Spacing.s)
        .fgCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label). \(note)")
    }
}

// MARK: - Toast overlay

struct ToastOverlay: View {
    @ObservedObject var toasts: ToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                HStack(spacing: FG.Spacing.s) {
                    Image(systemName: toast.style.symbol).foregroundColor(toast.style.color)
                    Text(toast.message).font(FG.captionFont).fontWeight(.medium).foregroundColor(FG.ink).lineLimit(2)
                    if let undo = toast.undo {
                        Spacer(minLength: 4)
                        Button("Undo") { undo(); toasts.dismiss() }
                            .font(FG.captionFont).fontWeight(.semibold).buttonStyle(.plain)
                            .foregroundColor(FG.ink).underline()
                    }
                }
                .padding(.horizontal, FG.Spacing.m)
                .padding(.vertical, FG.Spacing.s)
                .background(FG.surface, in: RoundedRectangle(cornerRadius: FG.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: FG.Radius.card).stroke(FG.border, lineWidth: 1))
                .padding(.horizontal, FG.Spacing.m)
                .padding(.bottom, FG.Spacing.s)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(toasts.current?.undo != nil)
    }
}

// MARK: - Section header

/// Mono eyebrow with an optional caption note underneath.
struct TabHeader: View {
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fgEyebrow()
            if let note { Text(note).fgCaption() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown when macOS notifications are off for FocusGuard: without them the
/// "sites unlocked" and "5 minutes left" alerts never appear.
struct NotificationsOffBanner: View {
    var body: some View {
        FGBanner(title: "Notifications are off",
                 message: "Turn them on to hear when sites unlock.",
                 action: "Open settings") { UnlockNotifier.openSystemSettings() }
    }
}

/// Shown when an always-on protection profile is missing (the daemon checks both).
/// Without the browser profile, Brave Tor windows skip the blocklist; without the
/// category-DNS profile, the system-wide adult filter is off.
struct ProtectionMissingBanner: View {
    let missing: [String]
    @State private var showHelp = false

    private var labels: [String] {
        missing.map { $0 == "browserPolicy" ? "Browser protection" : ($0 == "categoryDNS" ? "Adult-content filter" : $0) }
    }

    var body: some View {
        FGBanner(title: "\(labels.joined(separator: " and ")) \(labels.count == 1 ? "is" : "are") off",
                 action: "Help") { showHelp.toggle() }
        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: FG.Spacing.s) {
                if missing.contains("browserPolicy") {
                    Text("Browser protection: run `bash Scripts/make-browser-profile.sh`, open the generated .local.mobileconfig and approve it in System Settings → General → Device Management. Then quit and reopen Brave.")
                        .font(FG.captionFont).foregroundColor(FG.inkSecondary).textSelection(.enabled)
                }
                if missing.contains("categoryDNS") {
                    Text("Adult-content filter: open Resources/FocusGuard-Mac-DNS.mobileconfig and approve it in System Settings → General → Device Management.")
                        .font(FG.captionFont).foregroundColor(FG.inkSecondary).textSelection(.enabled)
                }
            }
            .padding(FG.Spacing.m)
            .frame(width: 300)
        }
    }
}
