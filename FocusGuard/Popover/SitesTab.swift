import SwiftUI
import FocusGuardShared
import FocusGuardCore

struct SitesTab: View {
    @ObservedObject var daemon: DaemonClient
    @State private var newDomain = ""
    @State private var showGroups = false
    @FocusState.Binding var addFieldFocused: Bool

    private var canRemove: Bool { daemon.status == .unlocked && !daemon.sessionActive }

    private var inputError: String? {
        let trimmed = newDomain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if case .failure(let e) = DomainValidation.clean(trimmed) { return e.commandError.message }
        return nil
    }

    var body: some View {
        VStack(spacing: FG.Spacing.s) {
            if showGroups {
                GroupsList(daemon: daemon, showGroups: $showGroups)
            } else {
                addRow
                if let inputError { caption(inputError, color: .red) }
                list
                Button { withAnimation(FG.Motion.quick) { showGroups = true } } label: {
                    HStack { Image(systemName: "square.grid.2x2"); Text(L10n.Sites.groups); Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                        .font(.caption)
                }
                .buttonStyle(.plain).foregroundColor(FG.Palette.emerald)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: FG.Spacing.s) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundColor(.secondary)
            TextField(L10n.Sites.addPlaceholder, text: $newDomain)
                .textFieldStyle(.plain)
                .focused($addFieldFocused)
                .onSubmit(submit)
            Button(action: submit) { Image(systemName: "plus.circle.fill").foregroundColor(FG.Palette.emerald) }
                .buttonStyle(.plain)
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty || inputError != nil)
                .accessibilityLabel("Block site")
        }
        .padding(FG.Spacing.s)
        .background(FG.Palette.bgInset, in: RoundedRectangle(cornerRadius: FG.Radius.m))
    }

    @ViewBuilder
    private var list: some View {
        if daemon.blockedDomains.isEmpty {
            emptyState(L10n.Sites.empty)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(daemon.blockedDomains, id: \.self) { domain in
                        row(domain)
                        if domain != daemon.blockedDomains.last { Divider().overlay(FG.Palette.hairline) }
                    }
                }
            }
            .frame(maxHeight: 200)
            if !canRemove { caption(L10n.Sites.removeHint, color: Color(white: 0.45)) }
        }
    }

    private func row(_ domain: String) -> some View {
        let pending = daemon.pendingAddDomains.contains(domain) || daemon.pendingRemoveDomains.contains(domain)
        return HStack {
            Text(domain).font(.system(size: 12, design: .monospaced)).lineLimit(1)
            Spacer()
            if pending {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            } else if canRemove {
                Button { daemon.removeDomain(domain) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Unblock \(domain)")
            }
        }
        .opacity(pending ? 0.55 : 1)
        .padding(.vertical, 6)
    }

    private func submit() {
        let value = newDomain.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, inputError == nil else { return }
        daemon.addDomain(value)
        newDomain = ""
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2).foregroundColor(color).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: FG.Spacing.s) {
            Image(systemName: "globe").font(.title2).foregroundColor(Color(white: 0.3))
            Text(text).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, FG.Spacing.xl)
    }
}
