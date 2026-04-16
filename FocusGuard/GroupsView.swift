import SwiftUI
import FocusGuardShared

struct GroupsView: View {
    @ObservedObject var daemon: DaemonClient
    @Binding var showGroups: Bool
    @State private var expandedGroup: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showGroups = false
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text("Quick Add Groups")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(DomainGroups.all) { group in
                        groupRow(group)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 260)
            .padding(.bottom, 8)
        }
    }

    private func groupRow(_ group: DomainGroup) -> some View {
        let blockedSet = Set(daemon.blockedDomains)
        let alreadyBlocked = group.domains.filter { blockedSet.contains($0) }.count
        let isFullyBlocked = alreadyBlocked == group.domains.count
        let isExpanded = expandedGroup == group.id

        return VStack(spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                Image(systemName: group.icon)
                    .font(.body)
                    .foregroundColor(isFullyBlocked ? .green : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(alreadyBlocked)/\(group.domains.count) blocked")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Fixed-width action area for consistent alignment
                Group {
                    if isFullyBlocked {
                        if daemon.status == .unlocked {
                            Button("Remove") {
                                daemon.removeDomains(group.domains)
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        Button(alreadyBlocked > 0 ? "+\(group.domains.count - alreadyBlocked)" : "Block") {
                            let toAdd = group.domains.filter { !blockedSet.contains($0) }
                            daemon.addDomains(toAdd)
                        }
                        .font(.caption2)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                }
                .frame(minWidth: 56, alignment: .trailing)

                // Expand/collapse chevron with fixed width
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedGroup = isExpanded ? nil : group.id
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.4))
                }
                .buttonStyle(.plain)
                .frame(width: 20)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFullyBlocked ? Color.green.opacity(0.05) : Color.clear)
            )

            // Expanded domain list with improved spacing
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.domains, id: \.self) { domain in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(blockedSet.contains(domain) ? Color.green : Color(white: 0.25))
                                .frame(width: 6, height: 6)
                            Text(domain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(blockedSet.contains(domain) ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 36)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 6)
                .background(Color(white: 0.08))
                .cornerRadius(6)
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}
