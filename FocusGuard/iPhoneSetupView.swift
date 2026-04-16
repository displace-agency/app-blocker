import SwiftUI
import FocusGuardShared

struct iPhoneSetupView: View {
    @ObservedObject var daemon: DaemonClient
    var onDismiss: () -> Void

    @State private var selectedOption: SetupOption? = nil

    private let emerald = Color(red: 0.204, green: 0.827, blue: 0.600)
    private let profileURL = "https://focusguard-dns.displace-agency-2-0.workers.dev/profile"

    enum SetupOption {
        case dnsProfile
        case screenTimePasscode
    }

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color(white: 0.3))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            switch selectedOption {
            case nil:
                optionsView
            case .dnsProfile:
                QRProfileView(onDismiss: onDismiss, profileURL: profileURL)
            case .screenTimePasscode:
                ScreenTimeSetupView(daemon: daemon, onDismiss: onDismiss)
            }
        }
        .frame(width: 360, height: 440)
        .background(Color(white: 0.06))
    }

    // MARK: - Options Menu

    private var optionsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "iphone")
                .font(.system(size: 44))
                .foregroundColor(emerald)

            Text("Protect Your iPhone")
                .font(.title3).fontWeight(.bold)

            Text("Two layers of protection")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                // Option 1: DNS Profile
                optionCard(
                    icon: "network",
                    title: "Install DNS Blocker",
                    subtitle: "Scan QR code to block websites. Synced with Mac. Takes 10 seconds.",
                    recommended: true
                ) { selectedOption = .dnsProfile }

                // Option 2: Screen Time Lock
                optionCard(
                    icon: "lock.shield",
                    title: "Lock with Screen Time",
                    subtitle: "Prevents profile removal. Makes blocking permanent.",
                    recommended: false
                ) { selectedOption = .screenTimePasscode }
            }
            .padding(.horizontal, 20)

            Spacer()

            Text("Install DNS first, then lock with Screen Time")
                .font(.caption2)
                .foregroundColor(Color(white: 0.35))
                .padding(.bottom, 16)
        }
    }

    private func optionCard(icon: String, title: String, subtitle: String, recommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(emerald)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        if recommended {
                            Text("START HERE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(emerald)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(emerald.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.3))
            }
            .padding(14)
            .background(Color(white: 0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(recommended ? emerald.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QR Code Profile Install

struct QRProfileView: View {
    var onDismiss: () -> Void
    let profileURL: String
    private let emerald = Color(red: 0.204, green: 0.827, blue: 0.600)

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Scan with iPhone Camera")
                .font(.title3).fontWeight(.bold)

            // QR Code image from API
            AsyncImage(url: URL(string: "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=\(profileURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profileURL)")) { image in
                image
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 180, height: 180)
                    .cornerRadius(12)
            } placeholder: {
                ProgressView()
                    .frame(width: 180, height: 180)
            }

            VStack(spacing: 6) {
                Text("1. Open Camera on iPhone")
                Text("2. Point at this QR code")
                Text("3. Tap the notification banner")
                Text("4. Tap Install > Install > Done")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()

            Text("Domains are synced with your Mac automatically")
                .font(.caption2)
                .foregroundColor(emerald)

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(emerald)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Screen Time Passcode Setup

struct ScreenTimeSetupView: View {
    @ObservedObject var daemon: DaemonClient
    var onDismiss: () -> Void

    @State private var phase: Phase = .intro
    @State private var digits: [Int] = []
    @State private var currentDigit = 0
    @State private var isSecondRound = false
    @State private var passcode = ""

    private let emerald = Color(red: 0.204, green: 0.827, blue: 0.600)

    enum Phase { case intro, tapping, reenter, lockdown, done }

    var body: some View {
        switch phase {
        case .intro: introView
        case .tapping: tappingView
        case .reenter: reenterView
        case .lockdown: lockdownView
        case .done: doneView
        }
    }

    private var introView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(emerald)
            Text("Lock Screen Time")
                .font(.title3).fontWeight(.bold)
            Text("This prevents the DNS profile\nfrom being removed.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("On iPhone, go to:\nSettings > Screen Time\nTurn it on > Use Screen Time Passcode")
                .font(.caption)
                .foregroundColor(Color(white: 0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
            button("I see the number pad") {
                generatePasscode()
                phase = .tapping
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var tappingView: some View {
        VStack(spacing: 12) {
            Spacer()

            Text(isSecondRound ? "Re-enter" : "Enter passcode")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < currentDigit ? emerald : i == currentDigit ? emerald.opacity(0.5) : Color(white: 0.2))
                        .frame(width: 10, height: 10)
                }
            }

            if currentDigit < digits.count {
                Text("\(digits[currentDigit])")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundColor(emerald)
                    .monospacedDigit()
                    .padding(.vertical, 4)

                Text("Tap this on iPhone")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()

            button("Next") {
                if currentDigit < 3 {
                    withAnimation(.easeInOut(duration: 0.12)) { currentDigit += 1 }
                } else if !isSecondRound {
                    phase = .reenter
                } else {
                    phase = .lockdown
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var reenterView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Re-enter passcode")
                .font(.title3).fontWeight(.bold)
            Text("iPhone asks to confirm.")
                .font(.callout).foregroundColor(.secondary)
            Spacer()
            button("Show digits again") {
                isSecondRound = true
                currentDigit = 0
                phase = .tapping
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var lockdownView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundColor(emerald)
            Text("Lock it down")
                .font(.title3).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                step("1", "Content & Privacy Restrictions > ON")
                step("2", "Allow Changes > Passcode Changes > Don't Allow")
                step("3", "Allow Changes > Account Changes > Don't Allow")
            }
            .padding(12)
            .background(Color(white: 0.1))
            .cornerRadius(10)

            Spacer()
            button("Done") { phase = .done }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(emerald)
            Text("iPhone locked")
                .font(.title3).fontWeight(.bold)
            Text("Profile can't be removed.\nPasscode visible in FocusGuard when unlocked.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            button("Close") { onDismiss() }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(emerald)
    }

    private func step(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num).font(.caption2).fontWeight(.bold).foregroundColor(emerald)
                .frame(width: 16, height: 16).background(emerald.opacity(0.15)).cornerRadius(8)
            Text(text).font(.caption).foregroundColor(.white)
        }
    }

    private func generatePasscode() {
        digits = (0..<4).map { _ in Int.random(in: 0...9) }
        passcode = digits.map(String.init).joined()
        currentDigit = 0
        isSecondRound = false

        // Save before showing
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusGuard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? passcode.write(to: dir.appendingPathComponent("screentime_passcode"), atomically: true, encoding: .utf8)
        try? passcode.write(toFile: "/etc/focusguard/.screentime_passcode", atomically: true, encoding: .utf8)
    }
}
