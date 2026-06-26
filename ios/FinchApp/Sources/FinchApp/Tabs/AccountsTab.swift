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
    @State private var path: [String] = []             // compact-mode push stack (account ids)
    @State private var errorMessage: String?
    @State private var collapsedGroups: Set<String> = []   // loaded per active ledger on appear
    @State private var renamingGroupId: String?        // group long-press → Edit (rename)
    @State private var renameText = ""
    @State private var groupPendingDelete: AccountGroupRow?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive  // drives reorder; entered via a group's long-press menu
    @State private var reorderRows: [ReorderRow] = []
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            listContent
            .navigationTitle("Accounts")
            .settingsPush()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    #if os(iOS)
                    // While reordering (entered from a group's long-press menu),
                    // the + turns into the standard "Done" button.
                    if editMode.isEditing {
                        Button { withAnimation { editMode = .inactive } } label: { Image(systemName: "checkmark") }
                                .accessibilityLabel("Done")
                                .fontWeight(.semibold)
                    } else {
                        Button { showingAdd = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add Account")
                    }
                    #else
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Account")
                    #endif
                }
                // Group + archive management moved off the + into the ⋯ overflow menu.
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingGroups = true } label: { Label("Manage Groups", systemImage: "folder") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingArchived = true } label: { Label("Archived Accounts", systemImage: "archivebox") }
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
            .alert("Rename group", isPresented: Binding(
                get: { renamingGroupId != nil },
                set: { if !$0 { renamingGroupId = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { renameGroup() }
            }
            .confirmationDialog("Delete group?", isPresented: Binding(
                get: { groupPendingDelete != nil },
                set: { if !$0 { groupPendingDelete = nil } }),
                presenting: groupPendingDelete) { g in
                Button("Delete \(g.name)", role: .destructive) { deleteGroup(g) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Accounts in this group become ungrouped.")
            }
            .navigationDestination(for: String.self) { AccountDetailView(accountId: $0) }
            .onAppear { consumeFocus(); collapsedGroups = AccountGroupCollapse.collapsed(ledger: store.activeLedgerId) }
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
            .onChange(of: store.activeLedgerId) { _, lid in collapsedGroups = AccountGroupCollapse.collapsed(ledger: lid) }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { _, mode in
                if mode.isEditing {
                    reorderRows = AccountReorder.buildRows(groups: store.accountGroups, accounts: store.accounts)
                } else {
                    persistReorder()
                }
            }
            #endif
        }
    }

    @ViewBuilder private var listContent: some View {
        if store.accounts.isEmpty {
            EmptyState(tab: .accounts)
        } else {
            #if os(iOS)
            if editMode.isEditing {
                reorderList
            } else {
                contentList
            }
            #else
            contentList
            #endif
        }
    }

    @ViewBuilder private var contentList: some View {
        if let selection {
            List(selection: selection) {
                allTransactionsLink
                groupedSections { account in
                    AccountRowView(account: account)
                        .tag(account.id)
                        .swipeActions(edge: .trailing) { rowActions(account) }
                        .contextMenu { rowActions(account) }
                }
            }
        } else {
            List {
                allTransactionsLink
                groupedSections { account in
                    // Plain Button (navigates via the path) instead of NavigationLink
                    // so there's no trailing disclosure chevron; contentShape keeps
                    // the whole row tappable.
                    Button { path.append(account.id) } label: {
                        AccountRowView(account: account).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) { rowActions(account) }
                    .contextMenu { rowActions(account) }
                }
            }
        }
    }

    /// Pinned entry to the global transaction feed (Activity lives here now,
    /// rather than in its own bottom-bar tab). Pushes the reusable feed onto the
    /// Accounts navigation stack.
    @ViewBuilder private var allTransactionsLink: some View {
        Section {
            NavigationLink { ActivityFeedView() } label: {
                Label("All Transactions", systemImage: "list.bullet")
            }
        }
    }

    /// The grouped account sections + net-worth footer, shared by both layouts —
    /// only the per-row view differs (push link vs. selectable row).
    @ViewBuilder private func groupedSections<Row: View>(
        @ViewBuilder row: @escaping (AccountRow) -> Row) -> some View {
        ForEach(store.accountGroupsOrdered, id: \.self) { groupName in
            // The group title is a tappable Button *row* (not a section header):
            // Buttons/tap gestures don't fire in List section headers, and the
            // native Section(isExpanded:) chevron only shows in .sidebar style.
            // A Button row is reliably tappable and keeps the default list look.
            Section {
                Button {
                    toggleGroup(groupName)
                } label: {
                    HStack {
                        Image(systemName: collapsedGroups.contains(groupName) ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Text(groupName).fontWeight(.semibold)
                        Spacer()
                        Text(store.subtotalDisplay(for: groupName)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Long-press a group → Reorder / Edit / Delete. (Reorder is
                // iOS-only; Edit/Delete only for real groups, not "Ungrouped".)
                .contextMenu {
                    #if os(iOS)
                    Button { withAnimation { editMode = .active } } label: {
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                    }
                    #endif
                    if let g = store.accountGroups.first(where: { $0.name == groupName }) {
                        Button { renamingGroupId = g.id; renameText = g.name } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { groupPendingDelete = g } label: { Label("Delete Group", systemImage: "trash") }
                    }
                }
                .accessibilityValue(collapsedGroups.contains(groupName) ? "Collapsed" : "Expanded")
                .accessibilityHint((collapsedGroups.contains(groupName) ? "Double tap to expand" : "Double tap to collapse")
                                   + ". Long press for group options.")

                if !collapsedGroups.contains(groupName) {
                    ForEach(store.accounts(in: groupName)) { account in row(account) }
                        .onMove { moveAccounts(in: groupName, from: $0, to: $1) }
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

    #if os(iOS)
    /// Flat, fully-draggable list used only while reordering: accounts move
    /// across groups, group headers move their whole block.
    private var reorderList: some View {
        List {
            ForEach(reorderRows) { row in
                switch row {
                case .group(_, let name):
                    Text(name).fontWeight(.semibold).foregroundStyle(.secondary)
                case .account(let a):
                    AccountRowView(account: a)
                }
            }
            .onMove { from, to in
                reorderRows = AccountReorder.applyMove(reorderRows, from: from, to: to)
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    /// Persist the reordered state (only rows whose group/order changed). Writes
    /// go through the per-call `store.apply` chokepoint (like `moveAccounts`), so
    /// it isn't atomic — a mid-loop failure leaves some rows at stale sort_order,
    /// which is cosmetic and self-heals on the next reorder.
    private func persistReorder() {
        guard !reorderRows.isEmpty else { return }   // nothing to persist (never entered reorder)
        let plan = AccountReorder.persistencePlan(reorderRows)
        let curGroupOrder = Dictionary(uniqueKeysWithValues: store.accountGroups.enumerated().map { ($1.id, $0) })
        let curAcct = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, ($0.groupId, $0.sortOrder ?? 0)) })
        do {
            for g in plan.groups where curGroupOrder[g.id] != g.order {
                try store.apply(.updateAccountGroup, Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(g.order)])]))
            }
            for a in plan.accounts {
                let cur = curAcct[a.id]
                if cur?.0 != a.groupId || cur?.1 != a.order {
                    var patch: [String: JSONValue] = ["sortOrder": .int(a.order)]
                    patch["groupId"] = a.groupId.map(JSONValue.string) ?? .null
                    try store.apply(.updateAccount, Args(["id": .string(a.id), "patch": .object(patch)]))
                }
            }
        } catch { errorMessage = i18nMessage(error) }
        reorderRows = []
    }
    #endif

    /// Toggle a group's collapsed state and persist it.
    private func toggleGroup(_ group: String) {
        let nowCollapsed = !collapsedGroups.contains(group)
        withAnimation {
            if nowCollapsed { collapsedGroups.insert(group) } else { collapsedGroups.remove(group) }
        }
        AccountGroupCollapse.setCollapsed(group, nowCollapsed, ledger: store.activeLedgerId)
    }

    /// Rename a group (from the long-press → Edit menu).
    private func renameGroup() {
        guard let id = renamingGroupId else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renamingGroupId = nil
        guard !name.isEmpty else { return }
        do { try store.apply(.updateAccountGroup, Args(["id": .string(id), "patch": .object(["name": .string(name)])])) }
        catch { errorMessage = i18nMessage(error) }
    }

    /// Delete a group (accounts fall back to ungrouped via ON DELETE SET NULL).
    private func deleteGroup(_ g: AccountGroupRow) {
        do { try store.apply(.deleteAccountGroup, Args(["id": .string(g.id)])) }
        catch { errorMessage = i18nMessage(error) }
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
        else { path = [id] }
        router.focusedId = nil
    }

    /// Persist a within-group reorder: renumber the group's accounts' sort_order
    /// to the post-drag order (drag across groups isn't offered — use Edit to
    /// change an account's group).
    private func moveAccounts(in group: String, from source: IndexSet, to dest: Int) {
        var ordered = store.accounts(in: group)
        ordered.move(fromOffsets: source, toOffset: dest)
        do {
            for (i, acct) in ordered.enumerated() {
                try store.apply(.updateAccount, Args(["id": .string(acct.id), "patch": .object(["sortOrder": .int(i)])]))
            }
        } catch { errorMessage = i18nMessage(error) }
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
