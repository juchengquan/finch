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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Done")
            }
        }
    }

    private func unarchive(_ a: AccountRow) {
        do { try store.apply(.unarchiveAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Create / rename / delete account groups (via the shared GroupAdminView).
struct AccountGroupsView: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        GroupAdminView(
            title: "Account Groups",
            groups: store.accountGroups,
            onCreate: { try store.apply(.createAccountGroup, Args(["ledgerId": .string(store.activeLedgerId), "name": .string($0)])) },
            onRename: { try store.apply(.updateAccountGroup, Args(["id": .string($0), "patch": .object(["name": .string($1)])])) },
            onDelete: { try store.apply(.deleteAccountGroup, Args(["id": .string($0)])) },
            onReorder: { ids in
                for (i, id) in ids.enumerated() {
                    try store.apply(.updateAccountGroup, Args(["id": .string(id), "patch": .object(["sortOrder": .int(i)])]))
                }
            })
    }
}
