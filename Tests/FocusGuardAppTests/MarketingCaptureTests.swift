import XCTest
import SwiftUI
import AppKit
import FocusGuardShared
@testable import FocusGuard

/// Renders the real popover and unlock dialog offscreen (NSHostingView, 3x, light mode)
/// with a public sample list. Skipped unless FOCUSGUARD_MARKETING_CAPTURE=1.
/// Output folder: FOCUSGUARD_CAPTURE_DIR (default: a temp folder).
/// Never reads /etc/focusguard and never opens the daemon socket (demo DaemonClient).
@MainActor
final class MarketingCaptureTests: XCTestCase {
    private let sample = [
        "x.com", "youtube.com", "reddit.com", "instagram.com", "tiktok.com", "netflix.com",
    ].sorted()

    private func state(_ status: BlockerStatus = .locked, blocked: [String]? = nil) -> StatusInfo {
        let now = Date()
        var s = StatusInfo(
            status: status,
            blockedDomains: blocked ?? sample,
            unlockDelay: FocusGuardConfig.defaultUnlockDelay,
            lastEnforced: now,
            unlocksToday: 0,
            maxUnlocksPerDay: FocusGuardConfig.defaultMaxUnlocksPerDay,
            cooldownDuration: FocusGuardConfig.defaultCooldownDuration,
            scheduleActive: true,
            blockedApps: [],
            schedules: [Schedule(id: "demo", days: [1, 2, 3, 4, 5], start: "09:00", end: "17:30")],
            daemonVersion: FocusGuardConfig.daemonProtocolVersion
        )
        if status == .unlockPending { s.unlockRequestTime = now.addingTimeInterval(-5 * 60) }
        if status == .unlocked { s.cooldownEndTime = now.addingTimeInterval(11 * 60 + 40) }
        if status == .focusSession { s.sessionEndTime = now.addingTimeInterval(37 * 60 + 12) }
        s.stats = StatsSummary(completedUnlocks: 3, sessionsCompleted: 12, currentStreakDays: 6,
                               bestStreakDays: 14, unlockRequests: 5, deniedUnlocks: 2, focusMinutesToday: 75)
        return s
    }

    private func outDir() throws -> URL {
        let path = ProcessInfo.processInfo.environment["FOCUSGUARD_CAPTURE_DIR"]
            ?? (NSTemporaryDirectory() + "focusguard-capture")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Borderless windows refuse key status by default; a key window draws controls active.
    private final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }

    /// `dark`: kept for the helper's signature; every FocusGuard surface is light now
    /// (AppDelegate forces `.aqua`), so all captures pass `false`.
    private func snapshot<V: View>(_ view: V, width: CGFloat, dark: Bool, to url: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        let size = NSSize(width: width, height: max(1, host.fittingSize.height))
        host.frame = NSRect(origin: .zero, size: size)
        // Parked far off-screen so nothing flashes on the real display.
        let window = KeyWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI (ScrollView, TimelineView, lazy stacks) lay out and draw.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        host.display()

        let scale = 3
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
        window.orderOut(nil)
    }

    func testCaptureMarketingScreens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FOCUSGUARD_MARKETING_CAPTURE"] == "1",
                          "set FOCUSGUARD_MARKETING_CAPTURE=1 to render marketing screenshots")
        let dir = try outDir()
        let notifier = UnlockNotifier(demo: true)
        let w = FG.Layout.popover.width

        let locked = DaemonClient(demo: state(.locked))
        try snapshot(RootView(daemon: locked, notifier: notifier, tab: .sites),
                     width: w, dark: false, to: dir.appendingPathComponent("01-sites.png"))

        let pending = DaemonClient(demo: state(.unlockPending))
        try snapshot(RootView(daemon: pending, notifier: notifier, tab: .sites),
                     width: w, dark: false, to: dir.appendingPathComponent("02-unlock.png"))

        try snapshot(UnlockConfirmationView(delayMinutes: 20, windowMinutes: 15, onConfirm: {}, onDismiss: {}),
                     width: 340, dark: false, to: dir.appendingPathComponent("02b-unlock-request.png"))

        let sched = DaemonClient(demo: state(.locked))
        try snapshot(RootView(daemon: sched, notifier: notifier, tab: .schedule),
                     width: w, dark: false, to: dir.appendingPathComponent("03-schedule.png"))

        // Groups: a short list so the preset groups show their Block buttons.
        let groups = DaemonClient(demo: state(.locked, blocked: ["x.com", "youtube.com", "reddit.com", "netflix.com"]))
        try snapshot(RootView(daemon: groups, notifier: notifier, tab: .sites, showGroups: true),
                     width: w, dark: false, to: dir.appendingPathComponent("04-groups.png"))

        let focus = DaemonClient(demo: state(.focusSession))
        try snapshot(RootView(daemon: focus, notifier: notifier, tab: .sites),
                     width: w, dark: false, to: dir.appendingPathComponent("05-focus.png"))

        let stats = DaemonClient(demo: state(.locked))
        try snapshot(RootView(daemon: stats, notifier: notifier, tab: .stats),
                     width: w, dark: false, to: dir.appendingPathComponent("06-stats.png"))

        let unlocked = DaemonClient(demo: state(.unlocked))
        try snapshot(RootView(daemon: unlocked, notifier: notifier, tab: .sites),
                     width: w, dark: false, to: dir.appendingPathComponent("07-unlocked.png"))
    }
}
