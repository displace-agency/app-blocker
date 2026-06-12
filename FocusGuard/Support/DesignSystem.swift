import SwiftUI
import AppKit
import FocusGuardShared

/// Single source of truth for FocusGuard's visual language. Replaces the
/// per-file emerald definitions and the duplicated status-color switches.
enum FG {
    enum Palette {
        static let emerald = Color(red: 0.204, green: 0.831, blue: 0.600)   // #34D399
        static let emeraldNS = NSColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1)
        static let teal = Color(red: 0.13, green: 0.74, blue: 0.74)
        static let bgDark = Color(red: 0.102, green: 0.102, blue: 0.102)    // #1A1A1A
        static let bgDarkNS = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
        static let bgCard = Color(white: 0.16)
        static let bgInset = Color(white: 0.09)
        static let hairline = Color.white.opacity(0.08)
    }

    /// Status visuals. Status is NEVER conveyed by color alone — every style
    /// carries a label and an SF Symbol too.
    enum StatusStyle {
        case locked, unlockPending, unlocked, focusSession, offline

        init(_ status: BlockerStatus) {
            switch status {
            case .locked: self = .locked
            case .unlockPending: self = .unlockPending
            case .unlocked: self = .unlocked
            case .focusSession: self = .focusSession
            }
        }

        var color: Color {
            switch self {
            case .locked: return FG.Palette.emerald
            case .unlockPending: return .orange
            case .unlocked: return .red
            case .focusSession: return Color(red: 0.49, green: 0.43, blue: 0.96)
            case .offline: return .gray
            }
        }

        var label: String {
            switch self {
            case .locked: return "Locked"
            case .unlockPending: return "Unlocking"
            case .unlocked: return "Unlocked"
            case .focusSession: return "Focus"
            case .offline: return "Offline"
            }
        }

        /// Glyph used inside the popover header.
        var symbol: String {
            switch self {
            case .locked: return "checkmark.shield.fill"
            case .unlockPending: return "shield.lefthalf.filled"
            case .unlocked: return "shield.slash.fill"
            case .focusSession: return "hourglass"
            case .offline: return "exclamationmark.triangle.fill"
            }
        }

        /// Glyph used in the menu bar (rendered via the macOS 26 bitmap workaround).
        var barSymbol: String {
            switch self {
            case .locked: return "checkmark.shield.fill"
            case .unlockPending: return "shield.lefthalf.filled"
            case .unlocked: return "shield.slash"
            case .focusSession: return "hourglass"
            case .offline: return "shield.slash"
            }
        }

        var barColor: NSColor {
            switch self {
            case .locked: return .white
            case .unlockPending: return .systemOrange
            case .unlocked: return .systemRed
            case .focusSession: return FG.Palette.emeraldNS
            case .offline: return .systemGray
            }
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 10
        static let xl: CGFloat = 12
    }

    enum Layout {
        static let popover = CGSize(width: 360, height: 520)
    }

    enum Motion {
        static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        static var quick: Animation? { reduce ? nil : .easeInOut(duration: 0.15) }
        static var standard: Animation? { reduce ? nil : .easeInOut(duration: 0.25) }
    }

    /// Format a second count as "12m 03s" / "45s".
    static func formatTime(_ totalSeconds: Int) -> String {
        let s = max(0, totalSeconds)
        let m = s / 60
        let sec = s % 60
        return m > 0 ? "\(m)m \(String(format: "%02d", sec))s" : "\(sec)s"
    }
}
