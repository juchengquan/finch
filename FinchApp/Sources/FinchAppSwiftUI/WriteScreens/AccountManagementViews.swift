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
                            Image(systemName: AccountTypeIcon.icon(for: a.type))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)   // align names/separators across type glyphs
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
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
            }
        }
    }

    private func unarchive(_ a: AccountRow) {
        do { try store.apply(.unarchiveAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

