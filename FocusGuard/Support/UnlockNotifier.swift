import Foundation
import AppKit
@preconcurrency import UserNotifications
import FocusGuardShared

/// Keeps the user informed about the unlock flow without relying on them watching
/// the menu bar:
///
/// - "Sites unlocked" when the unlock delay ends. Scheduled with the system at the
///   deadline (+ grace for the daemon's 30 s enforcement tick), so it fires even if
///   this app is busy or the Mac just woke; the live pending -> unlocked transition
///   posts it immediately when observed first.
/// - "5 minutes left" before the auto-relock.
/// - Cleans up when the blocker relocks, so no stale "unlocked" alert remains.
///
/// Alerts are persistent by default (Info.plist `NSUserNotificationAlertStyle` =
/// `alert`), so a missed moment still waits on screen.
@MainActor
final class UnlockNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Permission { case unknown, allowed, denied }

    @Published private(set) var permission: Permission = .unknown

    nonisolated static let readyID = "focusguard.unlock.ready"
    nonisolated static let soonID = "focusguard.relock.soon"
    /// Daemon enforces every 30 s; the unlock lands on the first tick after the deadline.
    static let daemonGrace: TimeInterval = 40
    static let warnBeforeRelock: TimeInterval = 5 * 60

    var onOpen: (() -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var lastStatus: BlockerStatus?
    private var scheduledReadyFor: Date?
    private var scheduledSoonFor: Date?

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshPermission() }
        }
    }

    func refreshPermission() {
        center.getNotificationSettings { [weak self] settings in
            let p: Permission
            switch settings.authorizationStatus {
            case .authorized, .provisional: p = settings.alertSetting == .disabled ? .denied : .allowed
            case .denied: p = .denied
            default: p = .unknown
            }
            Task { @MainActor in self?.permission = p }
        }
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.focusguard.app"
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for s in urls { if let u = URL(string: s), NSWorkspace.shared.open(u) { return } }
    }

    // MARK: - Reconcile with daemon state

    /// Call on every status read (cheap: only touches the system when a deadline changes).
    func reconcile(_ info: StatusInfo, unlockDeadline: Date?) {
        let previous = lastStatus
        lastStatus = info.status

        switch info.status {
        case .unlockPending:
            removeSoon()
            if let deadline = unlockDeadline {
                let fire = deadline.addingTimeInterval(Self.daemonGrace)
                if scheduledReadyFor != fire {
                    scheduledReadyFor = fire
                    schedule(id: Self.readyID, at: fire, content: readyContent(info))
                }
            }

        case .unlocked:
            if previous == .unlockPending { postReadyNowUnlessDelivered(info) }
            scheduledReadyFor = nil
            if let end = info.cooldownEndTime {
                let fire = end.addingTimeInterval(-Self.warnBeforeRelock)
                if fire > Date().addingTimeInterval(5) {
                    if scheduledSoonFor != fire {
                        scheduledSoonFor = fire
                        schedule(id: Self.soonID, at: fire, content: soonContent(end))
                    }
                }
            }

        case .locked, .focusSession:
            if previous == .unlockPending || previous == .unlocked || previous == nil {
                clearAll()
            }
        }
    }

    // MARK: - Content

    private func readyContent(_ info: StatusInfo) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        let minutes = max(1, info.cooldownDuration / 60)
        c.title = "Sites unlocked"
        c.body = "Your wait is over. You have \(minutes) minutes before FocusGuard locks again."
        c.sound = .default
        c.threadIdentifier = "focusguard.unlock"
        return c
    }

    private func soonContent(_ end: Date) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        c.title = "5 minutes left"
        c.body = "FocusGuard locks again at \(f.string(from: end))."
        c.sound = .default
        c.threadIdentifier = "focusguard.unlock"
        return c
    }

    // MARK: - System calls

    private func schedule(id: String, at date: Date, content: UNMutableNotificationContent) {
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func postReadyNowUnlessDelivered(_ info: StatusInfo) {
        Task { @MainActor in
            let delivered = await center.deliveredNotifications()
            guard !delivered.contains(where: { $0.request.identifier == Self.readyID }) else { return }
            center.removePendingNotificationRequests(withIdentifiers: [Self.readyID])
            try? await center.add(UNNotificationRequest(identifier: Self.readyID, content: readyContent(info), trigger: nil))
        }
    }

    private func removeSoon() {
        scheduledSoonFor = nil
        center.removePendingNotificationRequests(withIdentifiers: [Self.soonID])
    }

    private func clearAll() {
        scheduledReadyFor = nil
        scheduledSoonFor = nil
        center.removePendingNotificationRequests(withIdentifiers: [Self.readyID, Self.soonID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.readyID, Self.soonID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.onOpen?() }
        completionHandler()
    }
}
