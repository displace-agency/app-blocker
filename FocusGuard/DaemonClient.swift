import Foundation
import SwiftUI
import FocusGuardShared
import FocusGuardCore

/// Talks to the daemon: passive status polling (survives daemon restarts) plus
/// socket commands that return an acknowledgement. Commands apply the returned
/// status immediately and surface success/failure as toasts.
@MainActor
final class DaemonClient: ObservableObject {
    @Published private(set) var info = StatusInfo()
    @Published private(set) var statusFileReadable = false
    /// Optimistic overlays: items the user just added/removed, shown before the
    /// next poll confirms them.
    @Published private(set) var pendingAddDomains: Set<String> = []
    @Published private(set) var pendingRemoveDomains: Set<String> = []
    @Published private(set) var pendingAddApps: Set<String> = []
    @Published private(set) var pendingRemoveApps: Set<String> = []

    let toasts = ToastCenter()
    var onStatusChange: ((BlockerStatus) -> Void)?

    private var pollTimer: Timer?
    private var lastStatus: BlockerStatus?

    init() {
        readStatusFile()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readStatusFile() }
        }
    }

    deinit { pollTimer?.invalidate() }

    // MARK: - Derived state

    var status: BlockerStatus { info.status }
    var blockedDomains: [String] {
        var set = Set(info.blockedDomains)
        set.formUnion(pendingAddDomains)
        set.subtract(pendingRemoveDomains)
        return set.sorted()
    }
    var blockedApps: [String] {
        var set = Set(info.blockedApps ?? [])
        set.formUnion(pendingAddApps)
        set.subtract(pendingRemoveApps)
        return set.sorted()
    }
    var schedules: [Schedule] { info.schedules ?? [] }
    var stats: StatsSummary { info.stats ?? StatsSummary() }
    var unlocksToday: Int { info.unlocksToday }
    var maxUnlocksPerDay: Int { info.maxUnlocksPerDay }
    var unlockDelayMinutes: Int { max(1, info.unlockDelay / 60) }
    var isEscalated: Bool { info.unlockDelay > FocusGuardConfig.defaultUnlockDelay }

    var sessionActive: Bool { info.status == .focusSession }
    var scheduleActive: Bool { info.scheduleActive ?? false }
    var hasSchedules: Bool { !(info.schedules ?? []).isEmpty }
    var outsideScheduledHours: Bool { hasSchedules && !scheduleActive && info.status == .unlocked && info.cooldownEndTime == nil }

    /// Deadlines for TimelineView-driven countdowns (no local timer drift).
    var unlockDeadline: Date? {
        guard info.status == .unlockPending, let t = info.unlockRequestTime else { return nil }
        return t.addingTimeInterval(Double(info.unlockDelay))
    }
    var cooldownDeadline: Date? { info.cooldownEndTime }
    var sessionDeadline: Date? { info.sessionEndTime }

    var isOffline: Bool {
        guard statusFileReadable, let last = info.lastEnforced else { return true }
        return Date().timeIntervalSince(last) > 90
    }
    var isDaemonOutdated: Bool {
        (info.daemonVersion ?? 0) < FocusGuardConfig.daemonProtocolVersion
    }

    // MARK: - Status polling

    private func readStatusFile() {
        guard let data = FileManager.default.contents(atPath: FocusGuardConfig.statusFile) else {
            statusFileReadable = false
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(StatusInfo.self, from: data) else {
            statusFileReadable = false
            return
        }
        statusFileReadable = true
        apply(decoded)
    }

    private func apply(_ new: StatusInfo) {
        let old = lastStatus
        info = new
        lastStatus = new.status
        // Clear optimistic overlays the daemon has now confirmed.
        pendingAddDomains.subtract(new.blockedDomains)
        pendingRemoveDomains = pendingRemoveDomains.intersection(new.blockedDomains)
        let apps = Set(new.blockedApps ?? [])
        pendingAddApps.subtract(apps)
        pendingRemoveApps = pendingRemoveApps.intersection(apps)
        if new.status != old { onStatusChange?(new.status) }
    }

    // MARK: - Commands

    @discardableResult
    private func send(_ command: DaemonCommand, argument: String? = nil, success: String? = nil) async -> CommandResponse? {
        let response = await SocketClient.send(CommandMessage(command: command, argument: argument))
        guard let response else {
            statusFileReadable = false
            toasts.show(L10n.Offline.banner, style: .error)
            return nil
        }
        if let status = response.status { apply(status) }
        if response.ok {
            if let success { toasts.show(success, style: .success) }
        } else if let error = response.error {
            toasts.show(error.message, style: .error)
        }
        return response
    }

    func requestUnlock() { Task { await send(.unlock) } }
    func cancelUnlock() { Task { await send(.cancelUnlock, success: "Unlock cancelled") } }
    func requestLock() { Task { await send(.lock, success: "Locked") } }
    func refresh() { Task { await send(.getStatus) } }

    func startSession(minutes: Int) {
        Task { await send(.startSession, argument: String(minutes), success: "\(minutes)-minute focus session started") }
    }

    func addDomain(_ raw: String) {
        switch DomainValidation.clean(raw) {
        case .success(let domain):
            pendingAddDomains.insert(domain)
            Task {
                let resp = await send(.addDomain, argument: domain, success: "Blocked \(domain)")
                if resp?.ok != true { pendingAddDomains.remove(domain) }
            }
        case .failure(let error):
            toasts.show(error.commandError.message, style: .error)
        }
    }

    func addDomains(_ raws: [String]) {
        let cleaned = raws.compactMap { try? DomainValidation.clean($0).get() }
        guard !cleaned.isEmpty else { return }
        pendingAddDomains.formUnion(cleaned)
        Task {
            let resp = await send(.addDomains, argument: cleaned.joined(separator: "\n"), success: "Blocked \(cleaned.count) sites")
            if resp?.ok != true { pendingAddDomains.subtract(cleaned) }
        }
    }

    func removeDomain(_ domain: String) {
        pendingRemoveDomains.insert(domain)
        Task {
            let resp = await send(.removeDomain, argument: domain)
            if resp?.ok == true {
                toasts.show("Unblocked \(domain)", style: .success) { [weak self] in self?.addDomain(domain) }
            } else {
                pendingRemoveDomains.remove(domain)
            }
        }
    }

    func addApp(_ name: String) {
        let clean = AppMatchRules.normalize(name)
        guard AppMatchRules.isValidAppName(clean) else {
            toasts.show(CommandError.invalidApp.message, style: .error); return
        }
        pendingAddApps.insert(clean)
        Task {
            let resp = await send(.addApp, argument: clean, success: "Blocked \(clean)")
            if resp?.ok != true { pendingAddApps.remove(clean) }
        }
    }

    func removeApp(_ name: String) {
        pendingRemoveApps.insert(name)
        Task {
            let resp = await send(.removeApp, argument: name, success: "Unblocked \(name)")
            if resp?.ok != true { pendingRemoveApps.remove(name) }
        }
    }

    func addSchedule(_ schedule: Schedule) {
        guard let data = try? JSONEncoder().encode(schedule), let json = String(data: data, encoding: .utf8) else { return }
        Task { await send(.addSchedule, argument: json, success: "Schedule added") }
    }

    func removeSchedule(_ id: String) {
        Task { await send(.removeSchedule, argument: id, success: "Schedule removed") }
    }
}
