import AppKit
import SwiftUI

/// Builds the standalone floating windows (onboarding, unlock, iPhone setup),
/// replacing the ~3x duplicated NSWindow boilerplate that lived in AppDelegate.
enum WindowFactory {
    struct Style {
        var size: NSSize?
        var darkChrome: Bool = true // kept for call sites; every window is now light
        var hideTitle: Bool = false
        var movableByBackground: Bool = false
    }

    static func make<V: View>(_ root: V, style: Style, delegate: NSWindowDelegate?) -> NSWindow {
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        if let size = style.size { window.setContentSize(size) }
        window.styleMask = style.hideTitle ? [.titled, .closable, .fullSizeContentView] : [.titled, .closable]
        window.title = L10n.appName
        window.titlebarAppearsTransparent = true
        if style.hideTitle { window.titleVisibility = .hidden }
        window.isMovableByWindowBackground = style.movableByBackground
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor.white
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = delegate
        return window
    }
}
