import SwiftUI
import FocusGuardShared

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var selectedGroups: Set<String> = []

    let daemon: DaemonClient
    let onComplete: () -> Void


    var body: some View {
        ZStack {
            FG.surface.ignoresSafeArea()

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
                .foregroundColor(FG.ink)

            Text("Welcome to FocusGuard")
                .font(.system(size: 22, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                .foregroundColor(FG.ink)

            Text("A website blocker that actually works.\nNo app cleaner can remove it.")
                .font(.body)
                .foregroundColor(FG.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            primaryButton("Get started") {
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
                .font(.system(size: 18, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                .foregroundColor(FG.ink)

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
                featureRow(
                    icon: "hourglass",
                    title: "Sessions & Schedules",
                    description: "Start an uncancellable focus session, or block on a weekly routine"
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
                .foregroundColor(FG.ink)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(FG.ink)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(FG.inkSecondary)
            }

            Spacer()
        }
        .padding(16)
        .fgCard()
    }

    // MARK: - Step 3: Choose What to Block

    private var chooseBlocksStep: some View {
        VStack(spacing: 16) {
            Text("Choose What to Block")
                .font(.system(size: 18, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                .foregroundColor(FG.ink)
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
                .foregroundColor(FG.inkSecondary)
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
                    .foregroundColor(isSelected ? FG.ink : FG.inkSecondary)

                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FG.ink)

                Text("\(group.domains.count) sites")
                    .font(.system(size: 11))
                    .foregroundColor(FG.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(isSelected ? FG.canvas : FG.surface, in: RoundedRectangle(cornerRadius: FG.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: FG.Radius.card)
                    .stroke(isSelected ? FG.ink : FG.border, lineWidth: isSelected ? 1.5 : 1)
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
                .foregroundColor(FG.ink)

            Text("You're all set!")
                .font(.system(size: 22, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                .foregroundColor(FG.ink)

            Text("FocusGuard is now protecting your focus.")
                .font(.body)
                .foregroundColor(FG.inkSecondary)

            // Menu bar hint
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: FG.Radius.control)
                    .fill(FG.canvas)
                    .frame(height: 28)
                    .overlay(
                        HStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "wifi")
                                .font(.system(size: 12))
                                .foregroundColor(FG.inkSecondary)
                            Image(systemName: "battery.75percent")
                                .font(.system(size: 12))
                                .foregroundColor(FG.inkSecondary)
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 12))
                                .foregroundColor(FG.ink)
                                .padding(.trailing, 8)
                        }
                    )
            }
            .frame(width: 200)
            .padding(.vertical, 4)

            Text("Look for the shield icon in your menu bar\nto manage your blocks.")
                .font(.system(size: 13))
                .foregroundColor(FG.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Text("To unlock blocked sites, you'll need to\ntype a confirmation phrase and wait.")
                .font(.system(size: 12))
                .foregroundColor(FG.inkTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()

            primaryButton("Start blocking") {
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
        }
        .buttonStyle(FGPrimaryButtonStyle(height: 40))
        .frame(maxWidth: 280)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? FG.ink : FG.border)
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
        var allDomains: [String] = []
        for group in DomainGroups.all where selectedGroups.contains(group.id) {
            allDomains.append(contentsOf: group.domains)
        }
        if !allDomains.isEmpty {
            daemon.addDomains(allDomains)
        }
    }
}
