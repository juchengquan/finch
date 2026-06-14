import SwiftUI
import FinchCore

/// Archived accounts (is_active = 0) with one-tap unarchive — the restore path
/// for accounts hidden via Archive.
struct ArchivedAccountsView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        let archived = store.archivedAccounts()
        Group {
            if archived.isEmpty {
                ContentUnavailableView("No archived accounts", systemImage: "archivebox",
                                       description: Text("Accounts you archive show up here."))
            } else {
                List {
                    ForEach(archived) { a in
                        HStack {
                            Image(systemName: AccountTypeIcon.icon(for: a.type)).foregroundStyle(.secondary)
                            Text(a.name ?? "—")
                            Spacer()
                            Button("Unarchive") { unarchive(a) }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Archived Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }

    private func unarchive(_ a: AccountRow) {
        do { try store.apply(.unarchiveAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Create / rename / delete account groups.
struct AccountGroupsView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Add group") {
                HStack {
                    TextField("Group name", text: $newName)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Groups") {
                if store.accountGroups.isEmpty {
                    Text("No groups yet").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.accountGroups) { g in
                        GroupRowEditor(group: g, onError: { errorMessage = $0 })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(g) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Account Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try store.apply(.createAccountGroup, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(name)]))
            newName = ""
        } catch { errorMessage = i18nMessage(error) }
    }

    private func delete(_ g: AccountGroupRow) {
        do { try store.apply(.deleteAccountGroup, Args(["id": .string(g.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// One group row: rename in place (commits on submit).
private struct GroupRowEditor: View {
    @EnvironmentObject private var store: FinchStore
    let group: AccountGroupRow
    let onError: (String) -> Void
    @State private var name: String

    init(group: AccountGroupRow, onError: @escaping (String) -> Void) {
        self.group = group; self.onError = onError
        _name = State(initialValue: group.name)
    }

    var body: some View {
        TextField("Name", text: $name)
            .onSubmit(rename)
    }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != group.name else { name = group.name; return }
        do { try store.apply(.updateAccountGroup, Args(["id": .string(group.id), "patch": .object(["name": .string(trimmed)])])) }
        catch { onError(i18nMessage(error)); name = group.name }
    }
}
