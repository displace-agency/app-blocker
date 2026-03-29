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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: "FocusGuard")
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
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "FocusGuard - \(status.rawValue)"
        )
    }
}
