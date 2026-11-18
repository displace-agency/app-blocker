import SwiftUI
import FocusGuardShared
import FocusGuardCore

struct SitesTab: View {
    @ObservedObject var daemon: DaemonClient
    @State private var newDomain = ""
    @State private var showGroups = false
    @FocusState.Binding var addFieldFocused: Bool

    init(daemon: DaemonClient, addFieldFocused: FocusState<Bool>.Binding, showGroups: Bool = false) {
        _daemon = ObservedObject(wrappedValue: daemon)
        _addFieldFocused = addFieldFocused
        _showGroups = State(initialValue: showGroups)
    }

    private var canRemove: Bool { daemon.status == .unlocked && !daemon.sessionActive }

    private var inputError: String? {
        let trimmed = newDomain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if case .failure(let e) = DomainValidation.clean(trimmed) { return e.commandError.message }
        return nil
    }

    var body: some View {
        VStack(spacing: FG.Spacing.s) {
            addRow
            if let inputError { caption(inputError, color: FG.danger) }
            FGSegmented(options: [(false, L10n.Sites.myList), (true, L10n.Sites.groups)], selection: $showGroups)
            if showGroups {
                GroupsList(daemon: daemon)
            } else {
                list
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: FG.Spacing.s) {
            TextField(L10n.Sites.addPlaceholder, text: $newDomain)
                .textFieldStyle(.plain)
                .font(FG.bodyFont).foregroundColor(FG.ink)
                .focused($addFieldFocused)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(addDisabled ? FG.inkTertiary : FG.ink)
            }
            .buttonStyle(.plain)
            .disabled(addDisabled)
            .accessibilityLabel("Block site")
        }
        .fgField(focused: addFieldFocused)
    }

    private var addDisabled: Bool { newDomain.trimmingCharacters(in: .whitespaces).isEmpty || inputError != nil }

    @ViewBuilder
    private var list: some View {
        if daemon.blockedDomains.isEmpty {
            emptyState(L10n.Sites.empty)
        } else {
            VStack(alignment: .leading, spacing: FG.Spacing.xs) {
                Text("\(L10n.Sites.yourList) · \(daemon.blockedDomains.count)").fgEyebrow()
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVStack(spacing: 0) {
                    ForEach(daemon.blockedDomains, id: \.self) { domain in
                        row(domain)
                        if domain != daemon.blockedDomains.last { Divider().overlay(FG.hairline) }
                    }
                }
                .padding(.horizontal, FG.Spacing.m)
                .fgCard()
            }
            if !canRemove { caption(L10n.Sites.removeHint, color: FG.inkSecondary) }
        }
    }

    private func row(_ domain: String) -> some View {
        let pending = daemon.pendingAddDomains.contains(domain) || daemon.pendingRemoveDomains.contains(domain)
        return HStack {
            Text(domain).font(FG.domainFont).foregroundColor(FG.ink).lineLimit(1)
            if daemon.browserOnlyBlocked.contains(domain) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9)).foregroundColor(FG.accent)
                    .help("Still blocked in your browser by the installed profile, separate from FocusGuard's live list.")
            }
            Spacer()
            if pending {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            } else if canRemove {
                Button { daemon.removeDomain(domain) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundColor(FG.inkSecondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Unblock \(domain)")
            }
        }
        .opacity(pending ? 0.55 : 1)
        .frame(height: 24)
    }

    private func submit() {
        let value = newDomain.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, inputError == nil else { return }
        daemon.addDomain(value)
        newDomain = ""
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text).font(FG.captionFont).foregroundColor(color).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).fgCaption()
            .frame(maxWidth: .infinity).padding(.vertical, FG.Spacing.xl)
            .fgCard()
    }
}
