import SwiftUI
import FinchCore

/// Budgets grouped by budget group, each row's figures from
/// Selectors.budgetProgress (used/base/pct/over). `pct` is an INTEGER 0–100, so
/// ProgressView needs pct/100 and thresholds compare against 70/90.
///
/// Native enhancements (NOT web parity): the green/yellow/red 3-color banding
/// (green < 70, yellow 70–90, red > 90) and the "N days left" caption. The web
/// budget bar is 2-state (over ? destructive : primary) with remaining-amount
/// text and no day countdown.
/// Compact drill-in target: presented as a top-level cover so the iOS 26 resume
/// shadow never forms (a top-level scroll view doesn't re-converge on resume).
private enum BudgetsDrill: Identifiable {
    case detail(String)
    var id: String { switch self { case .detail(let id): return id } }
}

/// One view, two layouts: with `selection == nil` (compact) budget rows push
/// `BudgetDetailView`; with a `selection` binding (the iPad/Mac three-column
/// shell) rows are selectable and drive the shell's detail column.
struct BudgetsTab: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    /// Non-nil → three-column selection mode (drives the shell's detail column).
    var selection: Binding<String?>? = nil
    /// False when a UIKit `UINavigationController` owns the stack (Phase 2 tabs);
    /// wrapping it again would double the nav bars. Same seam as `AccountsTab`.
    var ownsNavigationStack: Bool = true
    @State private var showingAdd = false
    @State private var addingGroup = false
    @State private var editing: BudgetRow?
    @State private var quickAddFor: BudgetRow?     // leading swipe → Add sheet, category prefilled
    /// Asks the UIKit shell to push a converted screen; false when it is not
    /// converted (or on Mac/iPad), and the SwiftUI cover/push handles it as before.
    @Environment(\.nativeRoute) private var nativeRoute
    #if os(iOS)
    @State private var drill: BudgetsDrill?           // compact-mode drill (cover, not push)
    #endif
    @State private var path: [String] = []            // compact-mode push stack (budget ids)
    @State private var errorMessage: String?
    @State private var collapsedGroups: Set<String> = []   // loaded per active ledger on appear
    @State private var searchQuery = ""                // filters budget rows by name
    @State private var renamingGroupId: String?
    @State private var renameText = ""
    @State private var groupPendingDelete: GroupRow?
    @State private var pendingBudgetDelete: BudgetRow?   // budget awaiting delete confirmation
    #if os(iOS)
    @State private var editMode: EditMode = .inactive  // drives reorder; entered via the ⋯ overflow menu
    @State private var reorderRows: [BudgetReorderRow] = []
    @State private var expandedReorderGroups: Set<String> = []   // reorder mode: groups start collapsed
    #endif

    var body: some View {
        MaybeNavigationStack(enabled: ownsNavigationStack, path: $path) {
            listContent
            #if os(iOS)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            #else
            .searchable(text: $searchQuery, prompt: "Search")
            #endif
            .navigationTitle("Budgets")
            #if os(iOS)
            // Pin the large title. This root renders a bare ProgressView until the
            // deferred txns projection lands (see listContent), and a non-scrollable
            // root settles the bar to inline — permanently, since it never re-expands
            // once the list arrives. Accounts and Settings have no loading branch, so
            // only this tab came up inline. Setting the UIHostingController's
            // largeTitleDisplayMode from the UIKit side does NOT work: SwiftUI owns
            // the hosted navigationItem and overwrites it on first layout.
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                if editMode.isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { reorderRows = []; withAnimation { editMode = .inactive } } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Cancel")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { withAnimation { editMode = .inactive } } label: { Image(systemName: "checkmark") }
                            .accessibilityLabel("Done")
                            .confirmCheckmarkStyle()
                    }
                } else {
                    standardToolbar
                }
                #else
                standardToolbar
                #endif
            }
            .sheet(isPresented: $showingAdd) { BudgetSheet() }
            .sheet(item: $editing) { BudgetSheet(budget: $0) }
            .sheet(item: $quickAddFor) { AddTransactionSheet(defaultCategoryId: $0.categoryIds.first) }
            .sheet(isPresented: $addingGroup) { AddGroupSheet() }
            .errorAlert($errorMessage)
            .alert("Delete this budget?", isPresented: Binding(
                get: { pendingBudgetDelete != nil }, set: { if !$0 { pendingBudgetDelete = nil } }),
                presenting: pendingBudgetDelete) { b in
                Button("Delete", role: .destructive) { delete(b) }
                Button("Cancel", role: .cancel) {}
            } message: { b in
                Text("This permanently deletes \(b.name).")
            }
            .alert("Delete group?", isPresented: Binding(
                get: { groupPendingDelete != nil }, set: { if !$0 { groupPendingDelete = nil } }),
                presenting: groupPendingDelete) { g in
                Button("Delete \(g.name)", role: .destructive) { deleteGroup(g) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Budgets in this group become ungrouped.")
            }
            .alert("Rename group", isPresented: Binding(
                get: { renamingGroupId != nil },
                set: { if !$0 { renamingGroupId = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { renameGroup() }
            }
            .navigationDestination(for: String.self) { BudgetDetailView(budgetId: $0) }
            .onAppear { consumeFocus(); collapsedGroups = BudgetGroupCollapse.collapsed(ledger: store.activeLedgerId) }
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
            .onChange(of: store.activeLedgerId) { _, lid in collapsedGroups = BudgetGroupCollapse.collapsed(ledger: lid) }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { _, mode in
                if mode.isEditing {
                    reorderRows = BudgetReorder.buildRows(groups: store.budgetGroups, budgets: store.budgets)
                    expandedReorderGroups = []
                } else {
                    persistReorder()
                    reorderRows = []
                }
            }
            // Compact drill-in cover (no resume shadow). State-driven, so a deep
            // link into a budget (openBudget → drill) opens it, not just row taps.
            .rightSlideDrill(item: $drill) { target in
                NavigationStack {
                    BudgetDetailView(budgetId: target.id)
                        .rsdBackToolbar { drill = nil }
                        // See AccountsTab: the tab's FAB sits behind the cover, so
                        // the drilled page carries its own, seeded with whatever
                        // subject the budget publishes (its first account and/or
                        // category). Inside the stack, on the destination.
                        .addTransactionFABInCover()
                }
            }
            #endif
        }
    }

    /// The complete non-editing toolbar item set (both platforms) — hidden as a
    /// block while reordering, when only ✕/✓ show (see the branch in `body`).
    @ToolbarContentBuilder private var standardToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }
        #endif
        ToolbarItem(placement: .primaryAction) { PrivacyToggleButton() }
        ToolbarItem(placement: .primaryAction) {
            Button { showingAdd = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add Budget")
                .disabled(store.ledgers.isEmpty)
        }
        // Group management moved off the + into the ⋯ overflow menu (matches Accounts).
        ToolbarItem(placement: .secondaryAction) {
            Button { addingGroup = true } label: { Label("Add Group", systemImage: "folder.badge.plus") }
        }
        // Reorder in the ⋯ overflow menu, after Manage Groups (matches Accounts).
        #if os(iOS)
        ToolbarItem(placement: .secondaryAction) {
            Button { withAnimation { editMode = .active } } label: {
                Label("Reorder", systemImage: "arrow.up.arrow.down")
            }
            .disabled(store.budgets.isEmpty)
        }
        #endif
        // (Group order lives in the Reorder editor; create via Add Group;
        // rename/delete via the group header's long-press menu.)
    }

    @ViewBuilder private var listContent: some View {
        if !store.txnsReady {
            // Launch-only: budget "spent" comes from the deferred txns projection,
            // so every bar would read $0 for ~600ms then fill. Spin instead.
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.budgets.isEmpty {
            EmptyState(tab: .budgets,
                       description: store.ledgers.isEmpty ? nil : "Tap + to create a budget.")
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
                summarySection
                groupedSections { budget in
                    BudgetRowView(budget: budget)
                        .tag(budget.id)
                        .swipeActions(edge: .trailing) { trailingSwipeActions(budget) }
                        .swipeActions(edge: .leading) { leadingActions(budget) }
                        .contextMenu { leadingActions(budget); Divider(); rowActions(budget) }
                }
            }
            #if os(macOS)
            .onDeleteCommand { if let id = selection.wrappedValue, let b = store.budgets.first(where: { $0.id == id }) { delete(b) } }
            #endif
        } else {
            List {
                summarySection
                groupedSections { budget in
                    // Plain Button (navigates via the path) instead of NavigationLink
                    // so there's no trailing disclosure chevron — same convention as
                    // the Accounts rows; contentShape keeps the whole row tappable.
                    Button {
                        #if os(iOS)
                        if selection == nil {
                            if !nativeRoute(.budget(budget.id)) { drill = .detail(budget.id) }
                        } else { path.append(budget.id) }
                        #else
                        path.append(budget.id)
                        #endif
                    } label: {
                        BudgetRowView(budget: budget).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) { trailingSwipeActions(budget) }
                    .swipeActions(edge: .leading) { leadingActions(budget) }
                    .contextMenu { leadingActions(budget); Divider(); rowActions(budget) }
                }
            }
        }
    }

    /// Budget health pinned at the top: remaining-to-spend, an overall banded bar,
    /// an "N over" badge, and a separate goals line (see BudgetSummaryCard).
    @ViewBuilder private var summarySection: some View {
        Section { BudgetSummaryCard(summary: store.budgetSummary) }
    }

    /// True while the user has typed a non-empty budget search.
    private var searchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Budgets in `group`, narrowed by the search query (case-insensitive name
    /// contains). No query → the full group.
    private func filteredBudgets(in group: String) -> [BudgetRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let budgets = store.budgets(in: group)
        guard !q.isEmpty else { return budgets }
        return budgets.filter { $0.name.lowercased().contains(q) }
    }

    /// Ungrouped budgets, narrowed by the search query — rendered bare at the top.
    private var filteredUngroupedBudgets: [BudgetRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let buds = store.ungroupedBudgets
        guard !q.isEmpty else { return buds }
        return buds.filter { $0.name.lowercased().contains(q) }
    }

    /// Groups to render: all normally; while searching, only those with at least
    /// one matching budget.
    private var groupsToShow: [String] {
        searchActive ? store.budgetGroupsOrdered.filter { !filteredBudgets(in: $0).isEmpty }
                     : store.budgetGroupsOrdered
    }

    /// Grouped budget sections, shared by both layouts. (Totals live in the
    /// top summary section; see `summarySection`.)
    @ViewBuilder private func groupedSections<Row: View>(
        @ViewBuilder row: @escaping (BudgetRow) -> Row) -> some View {
        if searchActive && groupsToShow.isEmpty && filteredUngroupedBudgets.isEmpty {
            Section { ContentUnavailableView.search(text: searchQuery) }
        }
        // Ungrouped budgets: bare rows pinned to the top, no "Ungrouped" header.
        if !filteredUngroupedBudgets.isEmpty {
            Section {
                ForEach(filteredUngroupedBudgets) { budget in row(budget) }
                    .onMove { moveBudgets(in: "Ungrouped", from: $0, to: $1) }
            }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
            // Tappable Button row (not a section header) so the chevron toggle
            // fires reliably and keeps the default list look — mirrors AccountsTab (#223).
            Section {
                Button {
                    toggleGroup(groupName)
                } label: {
                    HStack {
                        Image(systemName: collapsedGroups.contains(groupName) ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        if let hex = store.budgetGroups.first(where: { $0.name == groupName })?.color,
                           let c = Color(hex: hex) {
                            Circle().fill(c).frame(width: 8, height: 8)
                        }
                        Text(groupName).fontWeight(.semibold)
                        Spacer()
                        Text(store.budgetSubtotalDisplay(for: groupName)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(collapsedGroups.contains(groupName) ? "Collapsed" : "Expanded")
                .accessibilityHint(collapsedGroups.contains(groupName) ? "Double tap to expand" : "Double tap to collapse")
                // Long-press a group → Edit / Delete (real groups only).
                // Reorder Groups lives in the ⋯ overflow menu.
                .contextMenu {
                    if let g = store.budgetGroups.first(where: { $0.name == groupName }) {
                        Button { renamingGroupId = g.id; renameText = g.name } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { groupPendingDelete = g } label: { Label("Delete Group", systemImage: "trash") }
                    }
                }

                // Collapse is bypassed while searching so matches always surface.
                if !collapsedGroups.contains(groupName) || searchActive {
                    ForEach(filteredBudgets(in: groupName)) { budget in row(budget) }
                        .onMove { moveBudgets(in: groupName, from: $0, to: $1) }
                }
            }
        }
    }

    #if os(iOS)
    /// Flat, fully-draggable list used only while reordering: budgets move
    /// across groups, group headers move their whole block.
    private var reorderList: some View {
        let collapsed = Set(store.budgetGroups.map(\.id)).subtracting(expandedReorderGroups)
        return List {
            ForEach(BudgetReorder.visibleRows(reorderRows, collapsed: collapsed)) { row in
                switch row {
                case .group(let gid, let name):
                    if let gid {
                        // Collapsed-by-default group row: the drag handle moves the whole block.
                        Button {
                            if expandedReorderGroups.contains(gid) { expandedReorderGroups.remove(gid) }
                            else { expandedReorderGroups.insert(gid) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: expandedReorderGroups.contains(gid) ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
                                if let hex = store.budgetGroups.first(where: { $0.id == gid })?.color,
                                   let c = Color(hex: hex) {
                                    Circle().fill(c).frame(width: 8, height: 8)
                                }
                                Text(name).fontWeight(.semibold)
                                Text("· \(BudgetReorder.itemCount(of: gid, in: reorderRows)) budgets")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(name).fontWeight(.semibold).foregroundStyle(.secondary)
                    }
                case .item(let b):
                    BudgetRowView(budget: b)
                }
            }
            .onMove { from, to in
                reorderRows = BudgetReorder.applyVisibleMove(reorderRows, collapsed: collapsed, from: from, to: to)
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    /// Persist the reordered state on ✓ (diff-aware, mirrors Accounts'): group
    /// order via updateBudgetGroup, changed membership via updateBudget, then the
    /// ledger-wide flat order in one setBudgetOrder. Writes go through the
    /// per-call `store.apply` chokepoint (like `moveBudgets`), so it isn't
    /// atomic — a mid-loop failure is cosmetic and self-heals on the next
    /// reorder. The ✕ cancel path clears `reorderRows` first → the guard no-ops.
    private func persistReorder() {
        guard !reorderRows.isEmpty else { return }
        let plan = BudgetReorder.plan(reorderRows)
        let curGroupOrder = Dictionary(uniqueKeysWithValues: store.budgetGroups.enumerated().map { ($1.id, $0) })
        let curGroupOf = Dictionary(uniqueKeysWithValues: store.budgets.map { ($0.id, $0.groupId) })
        do {
            for g in plan.groups where curGroupOrder[g.id] != g.order {
                try store.apply(.updateBudgetGroup, Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(g.order)])]))
            }
            for it in plan.items where curGroupOf[it.id] != it.groupId {
                try store.apply(.updateBudget, Args(["id": .string(it.id), "patch": .object(["groupId": it.groupId.map(JSONValue.string) ?? .null])]))
            }
            try store.apply(.setBudgetOrder, Args(["ledgerId": .string(store.activeLedgerId),
                                                   "budgetIds": .array(plan.items.map { .string($0.id) })]))
        } catch { errorMessage = i18nMessage(error) }
    }
    #endif

    /// Toggle a group's collapsed state and persist it.
    private func toggleGroup(_ group: String) {
        let nowCollapsed = !collapsedGroups.contains(group)
        withAnimation {
            if nowCollapsed { collapsedGroups.insert(group) } else { collapsedGroups.remove(group) }
        }
        BudgetGroupCollapse.setCollapsed(group, nowCollapsed, ledger: store.activeLedgerId)
    }

    /// Leading swipe: quick-add a transaction scoped to this budget — expense
    /// budgets and income goals alike are funded by real transactions (goals no
    /// longer contribute), prefilled with the budget's (first) category. Opens a
    /// confirm-first sheet; also merged into the context menu for macOS.
    @ViewBuilder private func leadingActions(_ budget: BudgetRow) -> some View {
        Button { quickAddFor = budget } label: { Label("Add Transaction", systemImage: "plus") }.tint(.green)
    }

    /// Context-menu manage cluster (role stays destructive there).
    @ViewBuilder private func rowActions(_ budget: BudgetRow) -> some View {
        Button { editing = budget } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
        Button(role: .destructive) { pendingBudgetDelete = budget } label: { Label("Delete", systemImage: "trash") }
    }

    /// Trailing swipe: Delete is NOT role: .destructive — the role plays a fake
    /// row-removal animation before the confirm.
    @ViewBuilder private func trailingSwipeActions(_ budget: BudgetRow) -> some View {
        Button { editing = budget } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
        Button { pendingBudgetDelete = budget } label: { Label("Delete", systemImage: "trash") }.tint(.red)
    }

    /// A deep link stashed a budget id + switched to this tab — open it.
    private func consumeFocus() {
        guard let id = router.focusedId, store.budgets.contains(where: { $0.id == id }) else { return }
        if let selection { selection.wrappedValue = id }
        else { openBudget(id) }
        router.focusedId = nil
    }

    /// Compact iOS: present detail as a cover (no resume shadow).
    /// iPad/macOS: push via NavigationStack path.
    private func openBudget(_ id: String) {
        #if os(iOS)
        if !nativeRoute(.budget(id)) { drill = .detail(id) }
        #else
        path = [id]
        #endif
    }

    private func delete(_ budget: BudgetRow) {
        do {
            try store.apply(.removeBudget, Args(["id": .string(budget.id)]))
            if selection?.wrappedValue == budget.id { selection?.wrappedValue = nil }
        } catch { errorMessage = i18nMessage(error) }
    }

    /// Persist a within-group budget reorder (long-press drag, like Accounts).
    /// Writes the ledger-wide flat order to app_state via setBudgetOrder;
    /// membership is untouched. No-op while searching (filtered indices).
    private func moveBudgets(in group: String, from source: IndexSet, to dest: Int) {
        guard !searchActive else { return }
        var seg = store.budgets(in: group)
        seg.move(fromOffsets: source, toOffset: dest)
        var ids: [String] = []
        for g in store.budgetGroupsOrdered + ["Ungrouped"] {
            ids += (g == group ? seg : store.budgets(in: g)).map(\.id)
        }
        do { try store.apply(.setBudgetOrder, Args(["ledgerId": .string(store.activeLedgerId), "budgetIds": .array(ids.map { .string($0) })])) }
        catch { errorMessage = i18nMessage(error) }
    }

    private func renameGroup() {
        guard let id = renamingGroupId else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renamingGroupId = nil
        guard !name.isEmpty else { return }
        do { try store.apply(.updateBudgetGroup, Args(["id": .string(id), "patch": .object(["name": .string(name)])])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func deleteGroup(_ g: GroupRow) {
        do { try store.apply(.deleteBudgetGroup, Args(["id": .string(g.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

struct BudgetRowView: View {
    @EnvironmentObject private var store: FinchStore
    let budget: BudgetRow
    var body: some View {
        let progress = Selectors.budgetProgress(budget, store.txns, store.budgetToday, store.categoryNodes)
        // Goals (income, non-recurring — funded by real matched inflows) have no
        // cycle: no days-left countdown, no Over flag, and MORE saved is better
        // (so the 3-color spend banding would read backwards) — show % saved
        // with a green bar instead.
        let isGoal = budget.type == "income" && budget.isRecurring == 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(budget.name)
                Spacer()
                // Amounts read as data (primary), matching account rows; group
                // headers keep the secondary summary style on both pages.
                Text("\(store.displayMoneyBase(progress.used)) / \(store.displayMoneyBase(progress.base))")
                    .font(.body)
            }
            ProgressView(value: min(Double(progress.pct) / 100, 1.0))
                .tint(isGoal ? .green : BudgetThreshold.color(pct: progress.pct))   // native enhancement
            HStack(spacing: 0) {
                // Percentage on every item (red when an expense is over budget); the
                // day-countdown only where there's a cycle — goals have none.
                Text("\(progress.pct)%")
                    .foregroundStyle(progress.over ? .red : .secondary)
                if isGoal {
                    Text(" saved").foregroundStyle(.secondary)
                } else {
                    // Hours on the final day — "7 hours left" is what you need when
                    // deciding whether to spend now. Plural suffix inline, matching the
                    // house pattern (see ActivityTab's "transaction\(…)").
                    // The cycle stops at the turnover time on `progress.to`, so the
                    // countdown has to as well — `budget.startTime` IS that moment.
                    switch store.remaining(until: progress.to, toTime: budget.startTime) {
                    case .days(let d):
                        Text(" · \(d) day\(d == 1 ? "" : "s") left").foregroundStyle(.secondary)
                    case .hours(let h):
                        Text(" · \(h) hour\(h == 1 ? "" : "s") left").foregroundStyle(.secondary)
                    case .lessThanAnHour:
                        Text(" · less than an hour left").foregroundStyle(.secondary)
                    case .ended:
                        EmptyView()
                    }
                }
            }
            .font(.caption2)
        }
    }
}

/// Add Group — a medium-detent bottom sheet (same element family as Add Budget):
/// name + the shared 8-swatch palette. Creates via createBudgetGroup.
///
/// Internal rather than private because `BudgetsListVC` presents the same sheet: the
/// list is UIKit now, but the write form stays SwiftUI so the Mac keeps rendering one
/// implementation of it.
struct AddGroupSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex: String? = nil
    @State private var selectedBudgetIds: Set<String> = []
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name", text: $name)
                Section {
                    HStack(spacing: 10) {
                        ForEach(TagPalette.hexes, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .secondary)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.primary.opacity(colorHex == hex ? 0.6 : 0), lineWidth: 2))
                                .onTapGesture { colorHex = (colorHex == hex ? nil : hex) }
                                .accessibilityLabel(Text(hex))
                        }
                    }
                } header: {
                    Text("Color")
                } footer: {
                    Text("Select budgets below to move them into this new group (optional).")
                        .padding(.top, 10)
                }
                // Pick what moves into the new group — mirrored from the Budgets
                // page structure: ungrouped first (headerless), then each group
                // in display order.
                if !store.ungroupedBudgets.isEmpty {
                    Section { ForEach(store.ungroupedBudgets) { budgetRow($0) } }
                }
                ForEach(store.budgetGroupsOrdered, id: \.self) { g in
                    let items = store.budgets(in: g)
                    if !items.isEmpty {
                        Section(g) { ForEach(items) { budgetRow($0) } }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Add Group")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .finchSectionSpacing()
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { add() } label: { Image(systemName: "checkmark") }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add")
                        .confirmCheckmarkStyle()
                }
            }
        }
    }
    @ViewBuilder private func budgetRow(_ b: BudgetRow) -> some View {
        Button {
            if selectedBudgetIds.contains(b.id) { selectedBudgetIds.remove(b.id) }
            else { selectedBudgetIds.insert(b.id) }
        } label: {
            HStack {
                Text(b.name).foregroundStyle(.primary)
                Spacer()
                if selectedBudgetIds.contains(b.id) {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))   // denser picker rows
    }

    private func add() {
        let gid = "bgg-\(UUID().uuidString.prefix(8).lowercased())"
        var args: [String: JSONValue] = ["id": .string(gid),
                                         "ledgerId": .string(store.activeLedgerId),
                                         "name": .string(name.trimmingCharacters(in: .whitespaces))]
        if let colorHex { args["color"] = .string(colorHex) }
        do {
            try store.apply(.createBudgetGroup, Args(args))
            for id in selectedBudgetIds {
                try store.apply(.updateBudget, Args(["id": .string(id), "patch": .object(["groupId": .string(gid)])]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
