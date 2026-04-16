import SwiftUI
import FocusGuardShared

struct BlockedSitesView: View {
    @ObservedObject var daemon: DaemonClient
    @Binding var showGroups: Bool
    @State private var newDomain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Blocked Sites (\(daemon.blockedDomains.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showGroups = true
                    }
                } label: {
                    Label("Groups", systemImage: "square.grid.2x2")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if daemon.blockedDomains.isEmpty {
                Text("No sites blocked")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(daemon.blockedDomains, id: \.self) { domain in
                            domainRow(domain)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            addSiteRow
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    private func domainRow(_ domain: String) -> some View {
        HStack {
            Text(domain)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)

            Spacer()

            if daemon.status == .unlocked {
                Button {
                    daemon.removeDomain(domain)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Remove \(domain)")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
    }

    private var addSiteRow: some View {
        HStack(spacing: 6) {
            TextField("Add site...", text: $newDomain)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { addDomain() }

            Button {
                addDomain()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }
        daemon.addDomain(domain)
        newDomain = ""
    }
}
