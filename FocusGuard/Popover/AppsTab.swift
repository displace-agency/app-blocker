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
                HStack { Image(systemName: "plus.app"); Text(L10n.Apps.choose); Spacer() }
                    .font(.caption).padding(FG.Spacing.s)
                    .background(FG.Palette.bgInset, in: RoundedRectangle(cornerRadius: FG.Radius.m))
            }
            .buttonStyle(.plain)

            quickAddRow

            if daemon.blockedApps.isEmpty {
                empty
            } else {
                list
            }

            Label(L10n.Apps.warning, systemImage: "exclamationmark.triangle")
                .font(.caption2).foregroundColor(.orange)
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
                                Text(name).font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(FG.Palette.bgCard, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(daemon.blockedApps, id: \.self) { app in
                    row(app)
                    if app != daemon.blockedApps.last { Divider().overlay(FG.Palette.hairline) }
                }
            }
        }
        .frame(maxHeight: 190)
    }

    private func row(_ app: String) -> some View {
        let pending = daemon.pendingAddApps.contains(app) || daemon.pendingRemoveApps.contains(app)
        return HStack(spacing: FG.Spacing.s) {
            if let icon = appIcon(for: app) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed").foregroundColor(.secondary)
            }
            Text(app).font(.caption)
            Spacer()
            if pending {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            } else if canRemove {
                Button { daemon.removeApp(app) } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Unblock \(app)")
            }
        }
        .opacity(pending ? 0.55 : 1)
        .padding(.vertical, 6)
    }

    private var empty: some View {
        VStack(spacing: FG.Spacing.s) {
            Image(systemName: "app.badge").font(.title2).foregroundColor(Color(white: 0.3))
            Text(L10n.Apps.empty).font(.caption).foregroundColor(.secondary)
            Text(L10n.Apps.onlyApplications).font(.caption2).foregroundColor(Color(white: 0.4))
        }
        .frame(maxWidth: .infinity).padding(.vertical, FG.Spacing.l)
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
