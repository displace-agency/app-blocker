import SwiftUI

struct UnlockConfirmationView: View {
    @Binding var isPresented: Bool
    var delayMinutes: Int
    var onConfirm: () -> Void

    @State private var confirmText = ""

    private let requiredPhrase = "I am choosing to procrastinate"

    private var isConfirmEnabled: Bool {
        confirmText == requiredPhrase
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Are you sure you want to unlock?")
                .font(.headline)

            Text("Blocks will lift in \(delayMinutes) minutes.\nYou'll have 15 minutes before auto-relock.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Text("Type: \"\(requiredPhrase)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("", text: $confirmText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    confirmText = ""
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Confirm Unlock") {
                    onConfirm()
                    confirmText = ""
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!isConfirmEnabled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
