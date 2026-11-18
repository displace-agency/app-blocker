// Owner-only: hardcodes a private worker URL. Excluded from the public release (PUBLIC_BUILD).
#if !PUBLIC_BUILD
import SwiftUI
import FocusGuardShared

struct iPhoneSetupView: View {
    @ObservedObject var daemon: DaemonClient
    var onDismiss: () -> Void

    @State private var selectedOption: SetupOption? = nil

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
                        .foregroundColor(FG.inkTertiary)
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
        .background(FG.surface)
        .preferredColorScheme(.light)
    }

    // MARK: - Options Menu

    private var optionsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "iphone")
                .font(.system(size: 44))
                .foregroundColor(FG.ink)

            Text("Protect Your iPhone")
                .font(.title3).fontWeight(.bold)

            Text("Two layers of protection")
                .font(.caption)
                .foregroundColor(FG.inkSecondary)

            VStack(spacing: 10) {
                // Option 1: DNS Profile
                optionCard(
                    icon: "network",
                    title: "Install DNS blocker",
                    subtitle: "Scan QR code to block websites. Synced with Mac. Takes 10 seconds.",
                    recommended: true
                ) { selectedOption = .dnsProfile }

                // Option 2: Screen Time Lock
                optionCard(
                    icon: "lock.shield",
                    title: "Lock with Screen time",
                    subtitle: "Prevents profile removal. Makes blocking permanent.",
                    recommended: false
                ) { selectedOption = .screenTimePasscode }
            }
            .padding(.horizontal, 20)

            Spacer()

            Text("Install DNS first, then lock with Screen Time")
                .font(.caption2)
                .foregroundColor(FG.inkSecondary)
                .padding(.bottom, 16)
        }
    }

    private func optionCard(icon: String, title: String, subtitle: String, recommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(FG.ink)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(FG.ink)
                        if recommended {
                            Text("START HERE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(FG.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FG.accentFill, in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(FG.inkSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(FG.inkTertiary)
            }
            .padding(14)
            .fgCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QR Code Profile Install

struct QRProfileView: View {
    var onDismiss: () -> Void
    let profileURL: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Scan with iPhone Camera")
                .font(.title3).fontWeight(.bold)

            // QR code generated locally via CoreImage — instant, offline.
            if let qr = QRCodeGenerator.image(for: profileURL, size: 180) {
                Image(nsImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 180, height: 180)
                    .cornerRadius(FG.Radius.card)
                    .accessibilityLabel("QR code to install the DNS blocker profile")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FG.canvas)
                    .frame(width: 180, height: 180)
                    .overlay(Image(systemName: "qrcode").font(.largeTitle).foregroundColor(FG.inkSecondary))
            }

            VStack(spacing: 6) {
                Text("1. Open Camera on iPhone")
                Text("2. Point at this QR code")
                Text("3. Tap the notification banner")
                Text("4. Tap Install > Install > Done")
            }
            .font(.caption)
            .foregroundColor(FG.inkSecondary)

            Spacer()

            Text("Domains are synced with your Mac automatically")
                .font(.caption2)
                .foregroundColor(FG.ink)

            Button {
                onDismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(.fgPrimary)
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
                .foregroundColor(FG.ink)
            Text("Lock Screen Time")
                .font(.title3).fontWeight(.bold)
            Text("This prevents the DNS profile\nfrom being removed.")
                .font(.callout)
                .foregroundColor(FG.inkSecondary)
                .multilineTextAlignment(.center)
            Text("On iPhone, go to:\nSettings > Screen Time\nTurn it on > Use Screen Time Passcode")
                .font(.caption)
                .foregroundColor(FG.inkSecondary)
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
                .foregroundColor(FG.inkSecondary)

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < currentDigit ? FG.ink : i == currentDigit ? FG.inkSecondary : FG.border)
                        .frame(width: 10, height: 10)
                }
            }

            if currentDigit < digits.count {
                Text("\(digits[currentDigit])")
                    .font(.system(size: 120, weight: .light))
                    .foregroundColor(FG.ink)
                    .monospacedDigit()
                    .padding(.vertical, 4)

                Text("Tap this on iPhone")
                    .font(.callout)
                    .foregroundColor(FG.inkSecondary)
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
                .foregroundColor(FG.accent)
            Text("Re-enter passcode")
                .font(.title3).fontWeight(.bold)
            Text("iPhone asks to confirm.")
                .font(.callout).foregroundColor(FG.inkSecondary)
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
                .foregroundColor(FG.ink)
            Text("Lock it down")
                .font(.title3).fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                step("1", "Content & Privacy Restrictions > ON")
                step("2", "Allow Changes > Passcode Changes > Don't Allow")
                step("3", "Allow Changes > Account Changes > Don't Allow")
            }
            .padding(12)
            .fgCard()

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
                .foregroundColor(FG.ink)
            Text("iPhone locked")
                .font(.title3).fontWeight(.bold)
            Text("Profile can't be removed.\nPasscode visible in FocusGuard when unlocked.")
                .font(.callout)
                .foregroundColor(FG.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            button("Close") { onDismiss() }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.fgPrimary)
    }

    private func step(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num).font(.caption2).fontWeight(.bold).foregroundColor(FG.ink)
                .frame(width: 16, height: 16).background(FG.canvas, in: Circle())
            Text(text).font(.caption).foregroundColor(FG.ink)
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
#endif
