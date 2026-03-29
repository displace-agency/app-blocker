import Foundation
import Combine
import FocusGuardShared

final class DaemonClient: ObservableObject {
    @Published var status: BlockerStatus = .locked
    @Published var blockedDomains: [String] = []
    @Published var unlockSecondsRemaining: Int?
    @Published var lastEnforced: Date?
    @Published var isConnected: Bool = false
    @Published var unlocksToday: Int = 0
    @Published var maxUnlocksPerDay: Int = FocusGuardConfig.defaultMaxUnlocksPerDay
    @Published var cooldownSecondsRemaining: Int?
    @Published var cooldownDuration: Int = FocusGuardConfig.defaultCooldownDuration
    @Published var unlockDelay: Int = FocusGuardConfig.defaultUnlockDelay

    /// Called when status changes (for updating the menu bar icon)
    var onStatusChange: ((BlockerStatus) -> Void)?

    private var pollTimer: Timer?
    private var countdownTimer: Timer?
    private var statusInfo: StatusInfo?

    init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    // MARK: - Polling

    private func startPolling() {
        readStatus()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.readStatus()
        }
    }

    private func readStatus() {
        let path = FocusGuardConfig.statusFile
        guard let data = FileManager.default.contents(atPath: path) else {
            DispatchQueue.main.async {
                self.isConnected = false
            }
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let info = try decoder.decode(StatusInfo.self, from: data)
            DispatchQueue.main.async {
                self.statusInfo = info
                let oldStatus = self.status
                self.status = info.status
                self.blockedDomains = info.blockedDomains
                if info.status != oldStatus {
                    self.onStatusChange?(info.status)
                }
                self.lastEnforced = info.lastEnforced
                self.isConnected = true
                self.unlocksToday = info.unlocksToday
                self.maxUnlocksPerDay = info.maxUnlocksPerDay
                self.unlockDelay = info.unlockDelay
                self.cooldownDuration = info.cooldownDuration
                self.cooldownSecondsRemaining = info.cooldownSecondsRemaining
                self.updateCountdown(from: info)
            }
        } catch {
            DispatchQueue.main.async {
                self.isConnected = false
            }
        }
    }

    // MARK: - Countdown

    private func updateCountdown(from info: StatusInfo) {
        if info.status == .unlockPending || info.status == .unlocked {
            unlockSecondsRemaining = info.unlockSecondsRemaining
            cooldownSecondsRemaining = info.cooldownSecondsRemaining
            startCountdownIfNeeded()
        } else {
            unlockSecondsRemaining = nil
            cooldownSecondsRemaining = nil
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    private func startCountdownIfNeeded() {
        guard countdownTimer == nil else { return }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let info = self.statusInfo else { return }
            DispatchQueue.main.async {
                self.unlockSecondsRemaining = info.unlockSecondsRemaining
                self.cooldownSecondsRemaining = info.cooldownSecondsRemaining

                // Stop timer when neither countdown is active
                let unlock = info.unlockSecondsRemaining ?? 0
                let cooldown = info.cooldownSecondsRemaining ?? 0
                if unlock <= 0 && cooldown <= 0 {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                }
            }
        }
    }

    // MARK: - Commands

    func requestLock() {
        sendCommand(CommandMessage(command: .lock))
    }

    func requestUnlock() {
        sendCommand(CommandMessage(command: .unlock))
    }

    func addDomain(_ domain: String) {
        let cleaned = cleanDomain(domain)
        guard !cleaned.isEmpty else { return }
        sendCommand(CommandMessage(command: .addDomain, argument: cleaned))
    }

    func removeDomain(_ domain: String) {
        sendCommand(CommandMessage(command: .removeDomain, argument: domain))
    }

    private func sendCommand(_ message: CommandMessage) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            // Write to /tmp which is world-writable -- no admin privileges needed
            try data.write(to: URL(fileURLWithPath: FocusGuardConfig.commandFile))

            // Re-read status after a short delay to pick up changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.readStatus()
            }
        } catch {
            // Command failed silently -- the user will see no status change
        }
    }

    // MARK: - Helpers

    private func cleanDomain(_ input: String) -> String {
        var domain = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip protocol
        for prefix in ["https://", "http://"] {
            if domain.hasPrefix(prefix) {
                domain = String(domain.dropFirst(prefix.count))
            }
        }
        // Strip www.
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }
        // Strip trailing path
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[domain.startIndex..<slashIndex])
        }
        return domain.lowercased()
    }
}
