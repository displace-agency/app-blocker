import SwiftUI
import FocusGuardShared

struct StatusView: View {
    @ObservedObject var daemon: DaemonClient
    @State private var showGroups = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            if showGroups {
                GroupsView(daemon: daemon, showGroups: $showGroups)
            } else {
                BlockedSitesView(daemon: daemon, showGroups: $showGroups)
            }

            Divider()
            actionButtons
            Divider()
            footerSection
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundColor(statusColor)
                Text("FocusGuard")
                    .font(.headline)
                    .fontWeight(.bold)
            }

            statusBadge

            // Daily budget
            HStack(spacing: 4) {
                ForEach(0..<daemon.maxUnlocksPerDay, id: \.self) { i in
                    Circle()
                        .fill(i < (daemon.maxUnlocksPerDay - daemon.unlocksToday) ? Color.green : Color.red.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                Text("\(max(0, daemon.maxUnlocksPerDay - daemon.unlocksToday)) unlocks left today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private var statusColor: Color {
        switch daemon.status {
        case .locked: return .green
        case .unlockPending: return .orange
        case .unlocked: return .red
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch daemon.status {
        case .locked:
            badge(text: "LOCKED", color: .green)
        case .unlockPending:
            VStack(spacing: 4) {
                badge(text: "UNLOCK PENDING", color: .orange)
                Text(countdownText)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .monospacedDigit()
            }
        case .unlocked:
            VStack(spacing: 4) {
                badge(text: "UNLOCKED", color: .red)
                if let cooldown = daemon.cooldownSecondsRemaining, cooldown > 0 {
                    Text("Auto-lock in \(formatTime(cooldown))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .monospacedDigit()
                }
            }
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    private var countdownText: String {
        guard let seconds = daemon.unlockSecondsRemaining, seconds > 0 else {
            return "0s"
        }
        return formatTime(seconds)
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return "\(m)m \(s)s"
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 8) {
            switch daemon.status {
            case .locked:
                if daemon.unlocksToday >= daemon.maxUnlocksPerDay {
                    Text("No unlocks remaining today")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)

                    Button {} label: {
                        Label("Budget Exhausted", systemImage: "lock.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .tint(.gray)
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                } else {
                    if daemon.unlockDelay > FocusGuardConfig.defaultUnlockDelay {
                        Text("Wait: \(daemon.unlockDelay / 60) min (escalated)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Button {
                        NotificationCenter.default.post(name: .focusGuardShowUnlock, object: nil)
                    } label: {
                        Label("Request Unlock", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .tint(.orange)
                    .buttonStyle(.borderedProminent)
                }

            case .unlockPending:
                Button {
                    daemon.requestLock()
                } label: {
                    Label("Cancel Unlock", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .tint(.gray)
                .buttonStyle(.borderedProminent)

            case .unlocked:
                if let cooldown = daemon.cooldownSecondsRemaining, cooldown > 0 {
                    ProgressView(value: Double(cooldown), total: Double(daemon.cooldownDuration))
                        .tint(.red)
                }

                Button {
                    daemon.requestLock()
                } label: {
                    Label("Lock Now", systemImage: "lock")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .tint(.green)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            devicesSection
            Divider()
            HStack {
                Circle()
                    .fill(daemon.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(daemon.isConnected ? "Synced" : "Offline")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "iphone")
                    .font(.caption)
                    .foregroundColor(hasScreenTimePasscode ? .green : .secondary)
                Text(hasScreenTimePasscode ? "iPhone protected" : "iPhone not set up")
                    .font(.caption2)
                    .foregroundColor(hasScreenTimePasscode ? .green : .secondary)

                Spacer()

                if hasScreenTimePasscode {
                    if daemon.status == .unlocked, let passcode = readScreenTimePasscode() {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(passcode, forType: .string)
                        } label: {
                            Label(passcode, systemImage: "key")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    Button {
                        NotificationCenter.default.post(name: .focusGuardShowiPhoneSetup, object: nil)
                    } label: {
                        Text("Set Up")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.204, green: 0.827, blue: 0.600))
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var hasScreenTimePasscode: Bool {
        readScreenTimePasscode() != nil
    }

    private func readScreenTimePasscode() -> String? {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusGuard/screentime_passcode")
        if let code = try? String(contentsOf: appSupport, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            return code
        }
        return try? String(contentsOfFile: "/etc/focusguard/.screentime_passcode", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
