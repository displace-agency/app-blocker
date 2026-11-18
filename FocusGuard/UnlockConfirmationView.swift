import SwiftUI

struct UnlockConfirmationView: View {
    var delayMinutes: Int
    var windowMinutes: Int = 15
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    @State private var confirmText = ""

    private let requiredPhrase = "I am choosing to procrastinate"

    private var isConfirmEnabled: Bool {
        confirmText == requiredPhrase
    }

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FG.Spacing.l) {
            VStack(alignment: .leading, spacing: FG.Spacing.s) {
                Text(L10n.appName).fgEyebrow()
                Text(L10n.Unlock.title).fgTitle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Blocks will lift in \(delayMinutes) minutes.")
                Text("You'll have \(windowMinutes) minutes before auto-relock.")
                Text("FocusGuard will notify you when it's ready.").foregroundColor(FG.inkSecondary)
            }
            .font(FG.bodyFont).foregroundColor(FG.ink)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Type: \"\(requiredPhrase)\"").fgCaption()
                TextField("", text: $confirmText)
                    .textFieldStyle(.plain)
                    .font(FG.bodyFont).foregroundColor(FG.ink)
                    .focused($fieldFocused)
                    .fgField(focused: fieldFocused)
            }

            HStack(spacing: FG.Spacing.s) {
                Button(L10n.Unlock.keepLocked) {
                    confirmText = ""
                    onDismiss()
                }
                .buttonStyle(.fgPrimary)
                .keyboardShortcut(.cancelAction)

                Button(L10n.Unlock.confirm) {
                    onConfirm()
                    confirmText = ""
                    onDismiss()
                }
                .buttonStyle(.fgSecondary)
                .disabled(!isConfirmEnabled)
            }
        }
        .padding(FG.Spacing.xl)
        .frame(width: 340)
        .background(FG.surface)
        .preferredColorScheme(.light)
    }
}
