import SwiftUI
import FinchCore

/// Accounts grouped by account group, each section with a subtotal, plus a
/// net-worth footer (includeInNetWorth == 1). All amounts convert
/// account-currency → base → display via Money. Rows drill into
/// AccountDetailView; the toolbar `+` menu covers add / manage groups /
/// archived; swipe + context menus cover edit / archive / delete.
struct AccountsTab: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingReconcile = false
    @State private var showingImport = false
    @State private var showingAdd = false
    @State private var showingGroups = false
    @State private var showingArchived = false
    @State private var editing: AccountRow?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    EmptyState(tab: .accounts)
                } else {
                    List {
                        ForEach(store.accountGroupsOrdered, id: \.self) { groupName in
                            Section {
                                ForEach(store.accounts(in: groupName)) { account in
                                    AccountListRow(account: account,
                                                   onEdit: { editing = account },
                                                   onArchive: { archive(account) },
                                                   onDelete: { delete(account) })
                                }
                            } header: {
                                HStack {
                                    Text(groupName)
                                    Spacer()
                                    Text(store.subtotalDisplay(for: groupName))
                                }
                            }
                        }
                        Section {
                            HStack {
                                Text("Net worth").fontWeight(.semibold)
                                Spacer()
                                Text(store.netWorthDisplay).fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingAdd = true } label: { Label("Add Account", systemImage: "plus") }
                        Button { showingGroups = true } label: { Label("Manage Groups", systemImage: "folder") }
                        Button { showingArchived = true } label: { Label("Archived Accounts", systemImage: "archivebox") }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add or manage accounts")
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink { HoldingsView() } label: { Label("Holdings", systemImage: "chart.bar") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingReconcile = true } label: { Label("Reconcile", systemImage: "checkmark.circle") }
                        .disabled(store.accounts.isEmpty)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingImport = true } label: { Label("Import statement (CSV)", systemImage: "doc.badge.plus") }
                        .disabled(store.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingReconcile) { ReconcileSheet() }
            .sheet(isPresented: $showingImport) { ImportStatementView() }
            .sheet(isPresented: $showingAdd) { AccountSheet(defaultCurrency: store.baseCurrency) }
            .sheet(item: $editing) { AccountSheet(account: $0, defaultCurrency: store.baseCurrency) }
            .sheet(isPresented: $showingGroups) { NavigationStack { AccountGroupsView() } }
            .sheet(isPresented: $showingArchived) { NavigationStack { ArchivedAccountsView() } }
            .alert("Couldn't complete that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func archive(_ a: AccountRow) {
        do { try store.apply(.archiveAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ a: AccountRow) {
        do { try store.apply(.deleteAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }   // engine rejects accounts with transactions
    }
}

struct AccountRowView: View {
    @EnvironmentObject private var store: FinchStore
    let account: AccountRow
    var body: some View {
        HStack {
            Image(systemName: AccountTypeIcon.icon(for: account.type))
                .foregroundStyle(.secondary)
            Text(account.name ?? "—")
            Spacer()
            Text(store.displayMoney(account.balance, from: account.currency))
                .fontWeight(.semibold)
        }
    }
}

/// A tappable account row (→ detail) with edit / archive / delete via swipe +
/// context menu. Extracted so AccountsTab's body stays type-checkable.
private struct AccountListRow: View {
    let account: AccountRow
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationLink { AccountDetailView(accountId: account.id) } label: {
            AccountRowView(account: account)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }.tint(.blue)
            Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }.tint(.orange)
        }
        .contextMenu {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}
