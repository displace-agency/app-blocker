import SwiftUI
import AppKit
import UserNotifications
import FocusGuardShared

// Use AppKit NSStatusBar directly -- much more reliable than SwiftUI MenuBarExtra for SPM builds

extension Notification.Name {
    static let focusGuardShowUnlock = Notification.Name("focusGuardShowUnlock")
    static let focusGuardShowiPhoneSetup = Notification.Name("focusGuardShowiPhoneSetup")
}

@main
struct FocusGuardApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let daemon = DaemonClient()
    private var onboardingWindow: NSWindow?
    private var unlockWindow: NSWindow?
    private var iphoneSetupWindow: NSWindow?
    private var lastStatus: BlockerStatus?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()

        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Pre-render the SF Symbol into a non-template bitmap. Works around
            // a macOS 26 regression where NSStatusBarButton draws template
            // images at zero alpha for ad-hoc-signed apps, making the icon
            // invisible while still clickable.
            button.image = Self.renderBarIcon(symbol: "shield.checkered", color: .white)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: StatusView(daemon: daemon)
        )

        // Listen for status changes to update the icon + post a notification
        // when the 20-minute wait ends and blocks actually lift.
        daemon.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                let previous = self.lastStatus
                self.lastStatus = status
                self.updateIcon(for: status)
                if previous == .unlockPending && status == .unlocked {
                    self.postUnlockReadyNotification()
                }
            }
        }

        // Listen for window requests from StatusView
        NotificationCenter.default.addObserver(
            self, selector: #selector(showUnlockWindow),
            name: .focusGuardShowUnlock, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showIPhoneSetupWindow),
            name: .focusGuardShowiPhoneSetup, object: nil
        )

        // Show onboarding on first launch
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompleted {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView(daemon: daemon) { [weak self] in
            self?.dismissOnboarding()
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 600, height: 500))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.title = "FocusGuard"

        window.delegate = self
        self.onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Handle user closing windows via X button
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

    private func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring the popover to front
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Standalone Windows (fixes popover auto-dismiss)

    @objc private func showUnlockWindow() {
        // Close popover so it can resume .transient behavior
        popover.performClose(nil)

        // Close existing if any
        unlockWindow?.close()

        let view = UnlockConfirmationView(
            delayMinutes: daemon.unlockDelay / 60,
            onConfirm: { [weak self] in
                self?.daemon.requestUnlock()
            },
            onDismiss: { [weak self] in
                self?.unlockWindow?.close()
                self?.unlockWindow = nil
            }
        )

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.title = "FocusGuard"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        unlockWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showIPhoneSetupWindow() {
        // Close popover so it can resume .transient behavior
        popover.performClose(nil)

        // Close existing if any
        iphoneSetupWindow?.close()

        let view = iPhoneSetupView(
            daemon: daemon,
            onDismiss: { [weak self] in
                self?.iphoneSetupWindow?.close()
                self?.iphoneSetupWindow = nil
            }
        )

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 360, height: 440))
        window.styleMask = [.titled, .closable]
        window.title = "FocusGuard"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        iphoneSetupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateIcon(for status: BlockerStatus) {
        let symbolName: String
        let color: NSColor
        switch status {
        case .locked:
            symbolName = "shield.checkered"
            color = .white
        case .unlockPending:
            symbolName = "shield.badge.exclamationmark"
            color = .systemOrange
        case .unlocked:
            symbolName = "shield.slash"
            color = .systemRed
        }
        statusItem.button?.image = Self.renderBarIcon(symbol: symbolName, color: color)
    }

    /// Pre-renders an SF Symbol into a non-template bitmap NSImage tinted with
    /// the given color. Fixes the macOS 26 regression where NSStatusBarButton
    /// draws template images at zero alpha for ad-hoc-signed apps.
    private static func renderBarIcon(symbol: String, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let source = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let size = source.size
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        rect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postUnlockReadyNotification() {
        let content = UNMutableNotificationContent()
        content.title = "FocusGuard"
        content.body = "Blocks are lifted. You have 15 minutes before auto-relock."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "focusguard.unlock.ready",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
