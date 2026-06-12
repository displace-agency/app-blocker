import SwiftUI
import FocusGuardShared

// MARK: - Status pill

struct StatusPill: View {
    let style: FG.StatusStyle
    var subtitle: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: style.symbol).font(.system(size: 9, weight: .bold))
                Text(style.label.uppercased()).font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(style.color, in: Capsule())

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundColor(style.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle == nil ? style.label : "\(style.label), \(subtitle!)")
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
                    .fill(i < remaining ? FG.Palette.emerald : Color.red.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
            Text("\(remaining) left").font(.system(size: 10)).foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remaining) of \(total) unlocks remaining today")
    }
}

// MARK: - Offline / outdated banner

struct OfflineBanner: View {
    let outdated: Bool
    @State private var showHelp = false

    var body: some View {
        Button { showHelp.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                Text(outdated ? L10n.Offline.outdated : L10n.Offline.banner)
                    .font(.caption).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "questionmark.circle").font(.caption)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, FG.Spacing.m)
            .padding(.vertical, FG.Spacing.s)
            .background(Color.orange.opacity(0.12))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: FG.Spacing.s) {
                Text(L10n.Offline.help).font(.caption).foregroundColor(.secondary)
                HStack {
                    Text(L10n.Offline.command)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .background(FG.Palette.bgInset, in: RoundedRectangle(cornerRadius: 6))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(L10n.Offline.command, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                }
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
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: FG.Spacing.xs) {
            Image(systemName: symbol).font(.caption).foregroundColor(FG.Palette.emerald)
            Text(value).font(.title2).fontWeight(.bold).monospacedDigit()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FG.Spacing.m)
        .background(FG.Palette.bgCard, in: RoundedRectangle(cornerRadius: FG.Radius.l))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
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
                    Text(toast.message).font(.caption).fontWeight(.medium).lineLimit(2)
                    if let undo = toast.undo {
                        Spacer(minLength: 4)
                        Button("Undo") { undo(); toasts.dismiss() }
                            .font(.caption).fontWeight(.semibold).buttonStyle(.plain)
                            .foregroundColor(FG.Palette.emerald)
                    }
                }
                .padding(.horizontal, FG.Spacing.m)
                .padding(.vertical, FG.Spacing.s)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(FG.Palette.hairline))
                .padding(.horizontal, FG.Spacing.m)
                .padding(.bottom, FG.Spacing.s)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(toasts.current?.undo != nil)
    }
}

// MARK: - Section header

struct TabHeader: View {
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            if let note { Text(note).font(.caption2).foregroundColor(Color(white: 0.45)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
