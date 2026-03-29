import SwiftUI
import AppKit
import FocusGuardShared

// Use AppKit NSStatusBar directly -- much more reliable than SwiftUI MenuBarExtra for SPM builds

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

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let daemon = DaemonClient()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: "FocusGuard")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: StatusView(daemon: daemon)
        )

        // Listen for status changes to update the icon
        daemon.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.updateIcon(for: status)
            }
        }

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

        self.onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private func updateIcon(for status: BlockerStatus) {
        let symbolName: String
        switch status {
        case .locked:
            symbolName = "shield.checkered"
        case .unlockPending:
            symbolName = "shield.badge.exclamationmark"
        case .unlocked:
            symbolName = "shield.slash"
        }
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "FocusGuard - \(status.rawValue)"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }
}
