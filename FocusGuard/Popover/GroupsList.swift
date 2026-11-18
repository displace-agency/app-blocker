import SwiftUI
import FocusGuardShared

/// Quick-add preset domain groups, shown under the Groups segment of the Sites tab.
struct GroupsList: View {
    @ObservedObject var daemon: DaemonClient

    var body: some View {
        VStack(alignment: .leading, spacing: FG.Spacing.xs) {
            Text("Groups · \(DomainGroups.all.count)").fgEyebrow()
            LazyVStack(spacing: 0) {
                ForEach(DomainGroups.all) { group in
                    groupRow(group)
                    if group.id != DomainGroups.all.last?.id { Divider().overlay(FG.hairline) }
                }
            }
            .padding(.horizontal, FG.Spacing.m)
            .fgCard()
        }
    }

    /// View-only: "Social Media" -> "Social media".
    private static func sentenceCase(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst().lowercased()
    }

    private func groupRow(_ group: DomainGroup) -> some View {
        let blocked = Set(daemon.blockedDomains)
        let inGroup = Set(group.domains)
        let allBlocked = inGroup.isSubset(of: blocked)
        let missing = group.domains.filter { !blocked.contains($0) }

        return HStack(spacing: FG.Spacing.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.sentenceCase(group.name)).font(FG.bodyMedium).foregroundColor(FG.ink)
                Text("\(group.domains.count) sites").fgCaption()
            }
            Spacer()
            if allBlocked {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text("Blocked").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(FG.inkSecondary)
            } else {
                Button(missing.count < group.domains.count ? "Block \(missing.count)" : "Block") { daemon.addDomains(missing) }
                    .buttonStyle(.fgSecondarySmall)
            }
        }
        .padding(.vertical, 6)
    }
}
