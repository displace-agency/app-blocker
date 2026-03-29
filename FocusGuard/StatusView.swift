import SwiftUI
import FocusGuardShared

struct StatusView: View {
    @ObservedObject var daemon: DaemonClient
    @State private var newDomain = ""
    @State private var showUnlockConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            blockedSitesList
            Divider()
            actionButtons
            Divider()
            footerSection
        }
        .frame(width: 300)
        .sheet(isPresented: $showUnlockConfirmation) {
            UnlockConfirmationView(
                isPresented: $showUnlockConfirmation,
                delayMinutes: daemon.unlockDelay / 60,
                onConfirm: { daemon.requestUnlock() }
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("FocusGuard")
                .font(.headline)
                .fontWeight(.bold)

            statusBadge

            // Daily budget indicator
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

    // MARK: - Blocked Sites

    private var blockedSitesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Blocked Sites")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if daemon.blockedDomains.isEmpty {
                Text("No sites blocked")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(daemon.blockedDomains, id: \.self) { domain in
                            domainRow(domain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            addSiteRow
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    private func domainRow(_ domain: String) -> some View {
        HStack {
            Text(domain)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            Spacer()

            if daemon.status == .unlocked {
                Button {
                    daemon.removeDomain(domain)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(domain)")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var addSiteRow: some View {
        HStack(spacing: 6) {
            TextField("Add site...", text: $newDomain)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { addDomain() }

            Button {
                addDomain()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }
        daemon.addDomain(domain)
        newDomain = ""
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 8) {
            switch daemon.status {
            case .locked:
                if daemon.unlocksToday >= daemon.maxUnlocksPerDay {
                    // Budget exhausted
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
                    // Show escalated delay info
                    if daemon.unlockDelay > FocusGuardConfig.defaultUnlockDelay {
                        Text("Wait time: \(daemon.unlockDelay / 60) min (escalated)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Button {
                        showUnlockConfirmation = true
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
                    // Show cooldown progress bar
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
        HStack {
            if !daemon.isConnected {
                Label("Daemon not running", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text("Daemon active")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
