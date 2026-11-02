import SwiftUI
import AppKit
import UserNotifications
import FocusGuardShared

// AppKit NSStatusBar directly -- more reliable than SwiftUI MenuBarExtra for SPM builds.

extension Notification.Name {
    static let focusGuardShowUnlock = Notification.Name("focusGuardShowUnlock")
    static let focusGuardShowiPhoneSetup = Notification.Name("focusGuardShowiPhoneSetup")
}

@main
struct FocusGuardApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let daemon = DaemonClient()
    private let notifier = UnlockNotifier()
    private var onboardingWindow: NSWindow?
    private var unlockWindow: NSWindow?
    private var iphoneSetupWindow: NSWindow?
    private var lastStatus: BlockerStatus?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestPermission()
        notifier.onOpen = { [weak self] in self?.showPopover() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.renderBarIcon(style: .locked)
            button.action = #selector(handleStatusClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = FG.Layout.popover
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: RootView(daemon: daemon, notifier: notifier))

        daemon.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                let previous = self.lastStatus
                self.lastStatus = status
                _ = previous
                self.updateIcon(for: status)
            }
        }
        daemon.onInfoChange = { [weak self] info in
            guard let self else { return }
            self.notifier.reconcile(info, unlockDeadline: self.daemon.unlockDeadline)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(showUnlockWindow), name: .focusGuardShowUnlock, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showIPhoneSetupWindow), name: .focusGuardShowiPhoneSetup, object: nil)

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    // MARK: - Status item interaction

    @objc private func handleStatusClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.Action.replayIntro, action: #selector(replayOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: "Notification Settings…", action: #selector(openNotificationSettings), keyEquivalent: "")
        // No Quit: FocusGuard runs as a login agent (KeepAlive) so unlock alerts always arrive.
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // reset so left-click opens the popover again
    }

    @objc private func openNotificationSettings() { UnlockNotifier.openSystemSettings() }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func replayOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        showOnboarding()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            notifier.refreshPermission()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Windows

    private func showOnboarding() {
        let view = OnboardingView(daemon: daemon) { [weak self] in self?.dismissOnboarding() }
        let window = WindowFactory.make(view, style: .init(size: NSSize(width: 600, height: 500), hideTitle: true, movableByBackground: true), delegate: self)
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    @objc private func showUnlockWindow() {
        popover.performClose(nil)
        unlockWindow?.close()
        let view = UnlockConfirmationView(
            delayMinutes: daemon.unlockDelayMinutes,
            windowMinutes: daemon.windowMinutes,
            onConfirm: { [weak self] in self?.daemon.requestUnlock() },
            onDismiss: { [weak self] in self?.unlockWindow?.close(); self?.unlockWindow = nil }
        )
        let window = WindowFactory.make(view, style: .init(darkChrome: false), delegate: self)
        unlockWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showIPhoneSetupWindow() {
        popover.performClose(nil)
        iphoneSetupWindow?.close()
        let view = iPhoneSetupView(daemon: daemon, onDismiss: { [weak self] in self?.iphoneSetupWindow?.close(); self?.iphoneSetupWindow = nil })
        let window = WindowFactory.make(view, style: .init(size: NSSize(width: 360, height: 440)), delegate: self)
        iphoneSetupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            onboardingWindow = nil
        } else if window === unlockWindow {
            unlockWindow = nil
        } else if window === iphoneSetupWindow {
            iphoneSetupWindow = nil
        }
    }

    // MARK: - Menu bar icon

    private func updateIcon(for status: BlockerStatus) {
        statusItem.button?.image = Self.renderBarIcon(style: FG.StatusStyle(status))
    }

    /// Pre-renders an SF Symbol into a non-template bitmap tinted with the style
    /// color. Works around the macOS 26 regression where NSStatusBarButton draws
    /// template images at zero alpha for ad-hoc-signed apps.
    private static func renderBarIcon(style: FG.StatusStyle) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let source = NSImage(systemSymbolName: style.barSymbol, accessibilityDescription: style.label)?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let size = source.size
        let image = NSImage(size: size)
        image.lockFocus()
        style.barColor.set()
        let rect = NSRect(origin: .zero, size: size)
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        rect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = "FocusGuard: \(style.label)"
        return image
    }
}
