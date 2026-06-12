import SwiftUI
import FocusGuardShared

/// Quick-add preset domain groups, shown as a push inside the Sites tab.
struct GroupsList: View {
    @ObservedObject var daemon: DaemonClient
    @Binding var showGroups: Bool

    var body: some View {
        VStack(spacing: FG.Spacing.s) {
            HStack {
                Button { withAnimation(FG.Motion.quick) { showGroups = false } } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.caption2); Text("Sites") }.font(.caption)
                }
                .buttonStyle(.plain).foregroundColor(FG.Palette.emerald)
                Spacer()
            }

            ScrollView {
                LazyVStack(spacing: FG.Spacing.s) {
                    ForEach(DomainGroups.all) { group in
                        groupRow(group)
                    }
                }
            }
            .frame(maxHeight: 250)
        }
    }

    private func groupRow(_ group: DomainGroup) -> some View {
        let blocked = Set(daemon.blockedDomains)
        let inGroup = Set(group.domains)
        let allBlocked = inGroup.isSubset(of: blocked)
        let missing = group.domains.filter { !blocked.contains($0) }

        return HStack(spacing: FG.Spacing.m) {
            Image(systemName: group.icon).foregroundColor(FG.Palette.emerald).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).font(.caption).fontWeight(.medium)
                Text("\(group.domains.count) sites").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if allBlocked {
                Image(systemName: "checkmark.circle.fill").foregroundColor(FG.Palette.emerald)
            } else {
                Button("Block \(missing.count)") { daemon.addDomains(missing) }
                    .font(.caption2).buttonStyle(.borderedProminent).tint(FG.Palette.emerald).controlSize(.small)
            }
        }
        .padding(FG.Spacing.s)
        .background(FG.Palette.bgCard, in: RoundedRectangle(cornerRadius: FG.Radius.m))
    }
}
