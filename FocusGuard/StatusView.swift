import SwiftUI
import FocusGuardShared

struct StatusView: View {
    @ObservedObject var daemon: DaemonClient
    @State private var newDomain = ""
    @State private var showUnlockConfirmation = false
    @State private var showGroups = false
    @State private var showiPhoneSetup = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            if showGroups {
                groupsSection
            } else {
                blockedSitesList
            }

            Divider()
            actionButtons
            Divider()
            footerSection
        }
        .frame(width: 320)
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

    // MARK: - Blocked Sites

    private var blockedSitesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Blocked Sites (\(daemon.blockedDomains.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showGroups = true
                    }
                } label: {
                    Label("Groups", systemImage: "square.grid.2x2")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
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
                .frame(maxHeight: 180)
            }

            addSiteRow
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    private func domainRow(_ domain: String) -> some View {
        HStack {
            Text(domain)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)

            Spacer()

            if daemon.status == .unlocked {
                Button {
                    daemon.removeDomain(domain)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Remove \(domain)")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
    }

    private var addSiteRow: some View {
        HStack(spacing: 6) {
            TextField("Add site...", text: $newDomain)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onSubmit { addDomain() }

            Button {
                addDomain()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
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

    // MARK: - Groups

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showGroups = false
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text("Quick Add Groups")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(DomainGroups.all) { group in
                        groupRow(group)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 260)
            .padding(.bottom, 8)
        }
    }

    private func groupRow(_ group: DomainGroup) -> some View {
        let blockedSet = Set(daemon.blockedDomains)
        let alreadyBlocked = group.domains.filter { blockedSet.contains($0) }.count
        let isFullyBlocked = alreadyBlocked == group.domains.count

        return HStack(spacing: 10) {
            Image(systemName: group.icon)
                .font(.title3)
                .foregroundColor(isFullyBlocked ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(group.domains.count) sites")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isFullyBlocked {
                if daemon.status == .unlocked {
                    Button("Remove") {
                        for domain in group.domains {
                            daemon.removeDomain(domain)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } else if alreadyBlocked > 0 {
                Button("\(group.domains.count - alreadyBlocked) more") {
                    for domain in group.domains {
                        if !blockedSet.contains(domain) {
                            daemon.addDomain(domain)
                        }
                    }
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Block All") {
                    for domain in group.domains {
                        daemon.addDomain(domain)
                    }
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFullyBlocked ? Color.green.opacity(0.05) : Color.clear)
        )
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
        VStack(spacing: 6) {
            // iPhone setup row
            HStack {
                Button {
                    showiPhoneSetup = true
                } label: {
                    Label("iPhone", systemImage: "iphone")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                if daemon.status == .unlocked, let password = readProfilePassword() {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(password, forType: .string)
                    } label: {
                        Label("Copy Profile Password", systemImage: "key")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)

            Divider()

            HStack {
                Circle()
                    .fill(daemon.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(daemon.isConnected ? "Daemon active" : "Daemon offline")
                    .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        } // end VStack
        .alert("Set Up iPhone", isPresented: $showiPhoneSetup) {
            Button("OK") {}
        } message: {
            Text("Run this in Terminal:\n\nsudo python3 ~/websites/app-blocker/Scripts/generate-profile.py --worker-url YOUR_WORKER_URL\n\nThen AirDrop the file to your iPhone.")
        }
    }

    private func readProfilePassword() -> String? {
        try? String(contentsOfFile: "/etc/focusguard/.ios_profile_password", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
