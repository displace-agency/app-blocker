import SwiftUI
import FocusGuardShared

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var selectedGroups: Set<String> = []

    let daemon: DaemonClient
    let onComplete: () -> Void

    private let emerald = Color(red: 0.204, green: 0.831, blue: 0.600) // #34d399
    private let darkBg = Color(red: 0.102, green: 0.102, blue: 0.102) // #1a1a1a
    private let cardBg = Color(red: 0.165, green: 0.165, blue: 0.165) // #2a2a2a

    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Step content
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: howItWorksStep
                    case 2: chooseBlocksStep
                    case 3: readyStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 0)

                // Step indicator
                stepIndicator
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 72))
                .foregroundColor(emerald)

            Text("Welcome to FocusGuard")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("A website blocker that actually works.\nNo app cleaner can remove it.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            primaryButton("Get Started") {
                advance()
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Step 2: How It Works

    private var howItWorksStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("How It Works")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 16) {
                featureRow(
                    icon: "shield.lefthalf.filled",
                    title: "System-Level Protection",
                    description: "Runs as a daemon, invisible to CleanMyMac"
                )
                featureRow(
                    icon: "clock.badge.exclamationmark",
                    title: "Escalating Delays",
                    description: "20 min wait to unlock. Doubles each time. Max 2/day."
                )
                featureRow(
                    icon: "lock.rotation",
                    title: "Auto-Relock",
                    description: "15-minute window, then blocks re-engage automatically"
                )
            }
            .padding(.horizontal, 16)

            Spacer()

            primaryButton("Next") {
                advance()
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(emerald)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBg)
        )
    }

    // MARK: - Step 3: Choose What to Block

    private var chooseBlocksStep: some View {
        VStack(spacing: 16) {
            Text("Choose What to Block")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 28)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(DomainGroups.all) { group in
                    groupCard(group)
                }
            }
            .padding(.horizontal, 8)

            Text("You can always add or remove sites later from the menu bar")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            primaryButton("Next") {
                advance()
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 40)
    }

    private func groupCard(_ group: DomainGroup) -> some View {
        let isSelected = selectedGroups.contains(group.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedGroups.remove(group.id)
                } else {
                    selectedGroups.insert(group.id)
                }
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: group.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? emerald : .gray)

                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text("\(group.domains.count) sites")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? emerald : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(emerald)

            Text("You're all set!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("FocusGuard is now protecting your focus.")
                .font(.body)
                .foregroundColor(.gray)

            // Menu bar hint
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 28)
                    .overlay(
                        HStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "wifi")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Image(systemName: "battery.75percent")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 12))
                                .foregroundColor(emerald)
                                .padding(.trailing, 8)
                        }
                    )
            }
            .frame(width: 200)
            .padding(.vertical, 4)

            Text("Look for the shield icon in your menu bar\nto manage your blocks.")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Text("To unlock blocked sites, you'll need to\ntype a confirmation phrase and wait.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()

            primaryButton("Start Blocking") {
                sendSelectedGroupsToDaemon()
                hasCompletedOnboarding = true
                onComplete()
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Shared Components

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(emerald)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 280)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? emerald : Color.white.opacity(0.2))
                    .frame(width: index == currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }

    // MARK: - Logic

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep += 1
        }
    }

    private func sendSelectedGroupsToDaemon() {
        for group in DomainGroups.all where selectedGroups.contains(group.id) {
            for domain in group.domains {
                daemon.addDomain(domain)
            }
        }
    }
}
