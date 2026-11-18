import SwiftUI
import FocusGuardShared

/// Quick-add preset domain groups, shown under the Groups segment of the Sites tab.
struct GroupsList: View {
    @ObservedObject var daemon: DaemonClient

    var body: some View {
        VStack(alignment: .leading, spacing: FG.Spacing.xs) {
            Text("Quick add").fgEyebrow()
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

    private func groupRow(_ group: DomainGroup) -> some View {
        let blocked = Set(daemon.blockedDomains)
        let inGroup = Set(group.domains)
        let allBlocked = inGroup.isSubset(of: blocked)
        let missing = group.domains.filter { !blocked.contains($0) }

        return HStack(spacing: FG.Spacing.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).font(FG.bodyMedium).foregroundColor(FG.ink)
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
                Button("Block") { daemon.addDomains(missing) }
                    .buttonStyle(.fgSecondarySmall)
            }
        }
        .padding(.vertical, 6)
    }
}
