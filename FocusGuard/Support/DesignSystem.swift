import SwiftUI
import AppKit
import FocusGuardShared

/// Single source of truth for FocusGuard's visual language. Replaces the
/// per-file emerald definitions and the duplicated status-color switches.
enum FG {
    // MARK: Color tokens (Displace website palette)

    static let ink = Color(hex: 0x1C1C1C)
    static let inkSecondary = Color(hex: 0x686C6D)
    static let inkTertiary = Color(hex: 0xA5A7A8)
    static let surface = Color.white
    static let canvas = Color(hex: 0xF5F5F5)
    static let border = Color(hex: 0xDBDBDB)
    static let hairline = Color(hex: 0xEDEDED)
    static let accent = Color(hex: 0xFF5831)
    static let accentFill = Color(hex: 0xFFE7B6)
    static let danger = Color(hex: 0xA92924)

    static let inkNS = NSColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255, alpha: 1)
    static let accentNS = NSColor(red: 1, green: 0x58 / 255, blue: 0x31 / 255, alpha: 1)
    static let dangerNS = NSColor(red: 0xA9 / 255, green: 0x29 / 255, blue: 0x24 / 255, alpha: 1)

    // MARK: Type tokens

    /// 12pt semibold uppercase title label.
    static let titleFont = Font.system(size: 12, weight: .semibold)
    static let titleTracking: CGFloat = 0.6
    /// 10pt monospaced uppercase eyebrow.
    static let eyebrowFont = Font.system(size: 10, design: .monospaced)
    static let eyebrowTracking: CGFloat = 0.8
    static let bodyFont = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let captionFont = Font.system(size: 11)
    static let domainFont = Font.system(size: 12, design: .monospaced)
    static func bigNumber(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .light).monospacedDigit()
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

        /// Accent color for glyphs and text on white (never the only status cue).
        var color: Color {
            switch self {
            case .locked, .focusSession: return FG.ink
            case .unlockPending: return FG.accent
            case .unlocked: return FG.danger
            case .offline: return FG.inkSecondary
            }
        }

        var pillFill: Color {
            switch self {
            case .locked: return FG.ink
            case .unlockPending: return FG.accentFill
            case .unlocked: return FG.danger
            case .focusSession: return FG.surface
            case .offline: return FG.canvas
            }
        }

        var pillText: Color {
            switch self {
            case .locked, .unlocked: return .white
            case .unlockPending, .focusSession: return FG.ink
            case .offline: return FG.inkSecondary
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
            case .unlockPending: return FG.accentNS
            case .unlocked: return FG.dangerNS
            case .focusSession: return .white
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
        static let control: CGFloat = 4
        static let card: CGFloat = 4
        static let pill: CGFloat = 999
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

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Text modifiers

extension View {
    /// 12pt semibold uppercase title label.
    func fgTitle() -> some View {
        font(FG.titleFont).tracking(FG.titleTracking).textCase(.uppercase).foregroundColor(FG.ink)
    }
    /// 10pt monospaced uppercase grey eyebrow.
    func fgEyebrow() -> some View {
        font(FG.eyebrowFont).tracking(FG.eyebrowTracking).textCase(.uppercase).foregroundColor(FG.inkSecondary)
    }
    func fgCaption() -> some View {
        font(FG.captionFont).foregroundColor(FG.inkSecondary)
    }
    /// White card with a 1px border.
    func fgCard() -> some View {
        background(FG.surface, in: RoundedRectangle(cornerRadius: FG.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: FG.Radius.card).stroke(FG.border, lineWidth: 1))
    }
    /// Text-field chrome: white, 1px border, ink focus ring.
    func fgField(focused: Bool = false) -> some View {
        padding(.horizontal, FG.Spacing.s).frame(height: 32)
            .background(FG.surface, in: RoundedRectangle(cornerRadius: FG.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: FG.Radius.control).stroke(focused ? FG.ink : FG.border, lineWidth: 1))
    }
}

// MARK: - Button styles

struct FGPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(enabled ? .white : FG.inkTertiary)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(enabled ? FG.ink : FG.canvas, in: RoundedRectangle(cornerRadius: FG.Radius.control))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

struct FGSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    var fullWidth = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height < 32 ? 12 : 13, weight: .medium))
            .foregroundColor(enabled ? FG.ink : FG.inkTertiary)
            .padding(.horizontal, height < 32 ? 10 : 0)
            .frame(maxWidth: fullWidth ? .infinity : nil).frame(height: height)
            .background(enabled ? FG.surface : FG.canvas, in: RoundedRectangle(cornerRadius: FG.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: FG.Radius.control).stroke(enabled ? FG.border : FG.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == FGPrimaryButtonStyle {
    static var fgPrimary: FGPrimaryButtonStyle { FGPrimaryButtonStyle() }
}
extension ButtonStyle where Self == FGSecondaryButtonStyle {
    static var fgSecondary: FGSecondaryButtonStyle { FGSecondaryButtonStyle() }
    static var fgSecondarySmall: FGSecondaryButtonStyle { FGSecondaryButtonStyle(height: 26, fullWidth: false) }
}

/// Boxed segmented control: 1px border, selected segment ink fill with white text.
struct FGSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let on = opt.0 == selection
                Button { withAnimation(FG.Motion.quick) { selection = opt.0 } } label: {
                    Text(opt.1).font(.system(size: 12, weight: .medium))
                        .foregroundColor(on ? .white : FG.ink)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(on ? FG.ink : FG.surface)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FG.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: FG.Radius.control).stroke(FG.border, lineWidth: 1))
    }
}
