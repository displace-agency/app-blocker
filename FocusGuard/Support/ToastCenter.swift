import SwiftUI

/// Transient bottom-of-popover feedback messages (command acks + errors).
@MainActor
final class ToastCenter: ObservableObject {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style
        var undo: (@MainActor () -> Void)?

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    enum Style {
        case success, error, info
        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .success: return FG.Palette.emerald
            case .error: return .red
            case .info: return .secondary
            }
        }
    }

    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Style = .info, undo: (@MainActor () -> Void)? = nil) {
        dismissTask?.cancel()
        withAnimation(FG.Motion.quick) { current = Toast(message: message, style: style, undo: undo) }
        let id = current?.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.current?.id == id else { return }
                withAnimation(FG.Motion.quick) { self.current = nil }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(FG.Motion.quick) { current = nil }
    }
}
