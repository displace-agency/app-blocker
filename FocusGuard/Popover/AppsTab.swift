import SwiftUI
import AppKit
import FocusGuardShared
import FocusGuardCore

struct AppsTab: View {
    @ObservedObject var daemon: DaemonClient

    private let quickAdd = ["Steam", "Discord", "Slack", "Telegram", "Spotify"]
    private var canRemove: Bool { daemon.status == .unlocked && !daemon.sessionActive }

    var body: some View {
        VStack(spacing: FG.Spacing.s) {
            Button(action: chooseApp) {
                HStack { Text(L10n.Apps.choose); Spacer(); Image(systemName: "plus").font(.system(size: 11, weight: .semibold)) }
                    .font(FG.bodyFont).foregroundColor(FG.ink)
                    .fgField()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            quickAddRow

            if daemon.blockedApps.isEmpty {
                empty
            } else {
                list
            }

            Text(L10n.Apps.warning).fgCaption()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickAddRow: some View {
        let blocked = Set(daemon.blockedApps.map { $0.lowercased() })
        let available = quickAdd.filter { !blocked.contains($0.lowercased()) }
        return Group {
            if !available.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(available, id: \.self) { name in
                            Button { daemon.addApp(name) } label: {
                                Text(name).font(.system(size: 11, weight: .medium)).foregroundColor(FG.ink)
                                    .padding(.horizontal, 10).frame(height: 24)
                                    .background(FG.surface, in: Capsule())
                                    .overlay(Capsule().stroke(FG.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: FG.Spacing.xs) {
            Text("Blocked apps · \(daemon.blockedApps.count)").fgEyebrow()
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVStack(spacing: 0) {
                ForEach(daemon.blockedApps, id: \.self) { app in
                    row(app)
                    if app != daemon.blockedApps.last { Divider().overlay(FG.hairline) }
                }
            }
            .padding(.horizontal, FG.Spacing.m)
            .fgCard()
        }
    }

    private func row(_ app: String) -> some View {
        let pending = daemon.pendingAddApps.contains(app) || daemon.pendingRemoveApps.contains(app)
        return HStack(spacing: FG.Spacing.s) {
            if let icon = appIcon(for: app) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(app).font(FG.bodyFont).foregroundColor(FG.ink)
            Spacer()
            if pending {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            } else if canRemove {
                Button { daemon.removeApp(app) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundColor(FG.inkSecondary) }
                    .buttonStyle(.plain).accessibilityLabel("Unblock \(app)")
            }
        }
        .opacity(pending ? 0.55 : 1)
        .frame(height: 32)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text(L10n.Apps.empty).font(FG.bodyFont).foregroundColor(FG.ink)
            Text(L10n.Apps.onlyApplications).fgCaption()
        }
        .frame(maxWidth: .infinity).padding(.vertical, FG.Spacing.l)
        .fgCard()
    }

    private func appIcon(for name: String) -> NSImage? {
        let path = "/Applications/\(name).app"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Block"
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.deletingPathExtension().lastPathComponent
            daemon.addApp(name)
        }
    }
}
