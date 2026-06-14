import SwiftUI
import FinchCore

/// Accounts grouped by account group, each section with a subtotal, plus a
/// net-worth footer (includeInNetWorth == 1). All amounts convert
/// account-currency → base → display via Money. The toolbar `+` menu covers add
/// / manage groups / archived; swipe + context menus cover edit / archive /
/// delete.
///
/// One view, two layouts: with `selection == nil` (compact / iPhone) rows are
/// `NavigationLink`s that push `AccountDetailView`; with a `selection` binding
/// (the iPad/Mac three-column shell) rows are selectable and drive the shell's
/// detail column. The toolbar / sheets / actions / focus handling are written
/// once.
struct AccountsTab: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    /// Non-nil → three-column selection mode (drives the shell's detail column).
    var selection: Binding<String?>? = nil
    @State private var showingReconcile = false
    @State private var showingImport = false
    @State private var showingAdd = false
    @State private var showingGroups = false
    @State private var showingArchived = false
    @State private var editing: AccountRow?
    @State private var focused: AccountRow?            // deep-link / Spotlight drill-in (push mode)
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            listContent
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
            .errorAlert($errorMessage)
            .navigationDestination(item: $focused) { AccountDetailView(accountId: $0.id) }
            .onAppear(perform: consumeFocus)
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        }
    }

    @ViewBuilder private var listContent: some View {
        if store.accounts.isEmpty {
            EmptyState(tab: .accounts)
        } else if let selection {
            List(selection: selection) {
                groupedSections { account in
                    AccountRowView(account: account)
                        .tag(account.id)
                        .swipeActions(edge: .trailing) { rowActions(account) }
                        .contextMenu { rowActions(account) }
                }
            }
        } else {
            List {
                groupedSections { account in
                    NavigationLink { AccountDetailView(accountId: account.id) } label: {
                        AccountRowView(account: account)
                    }
                    .swipeActions(edge: .trailing) { rowActions(account) }
                    .contextMenu { rowActions(account) }
                }
            }
        }
    }

    /// The grouped account sections + net-worth footer, shared by both layouts —
    /// only the per-row view differs (push link vs. selectable row).
    @ViewBuilder private func groupedSections<Row: View>(
        @ViewBuilder row: @escaping (AccountRow) -> Row) -> some View {
        ForEach(store.accountGroupsOrdered, id: \.self) { groupName in
            Section {
                ForEach(store.accounts(in: groupName)) { account in row(account) }
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

    @ViewBuilder private func rowActions(_ account: AccountRow) -> some View {
        Button { editing = account } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
        Button { archive(account) } label: { Label("Archive", systemImage: "archivebox") }.tint(.orange)
        Button(role: .destructive) { delete(account) } label: { Label("Delete", systemImage: "trash") }
    }

    /// A deep link / Spotlight tap stashed an id + switched to this tab — open it
    /// (select in three-column mode, push in compact mode).
    private func consumeFocus() {
        guard let id = router.focusedId, store.accounts.contains(where: { $0.id == id }) else { return }
        if let selection { selection.wrappedValue = id }
        else { focused = store.accounts.first { $0.id == id } }
        router.focusedId = nil
    }

    private func archive(_ a: AccountRow) {
        do { try store.apply(.archiveAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ a: AccountRow) {
        do {
            try store.apply(.deleteAccount, Args(["id": .string(a.id)]))
            if selection?.wrappedValue == a.id { selection?.wrappedValue = nil }
        } catch { errorMessage = i18nMessage(error) }   // engine rejects accounts with transactions
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
