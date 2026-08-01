import SwiftUI
import FinchCore

/// Expense/income filter for the Categories page (maps to `CategoryRow.kind`).
private enum CategoryKind: String, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .expense ? "Expense" : "Income" }
}

/// A chosen (initiating A, target B) pair for a merge; the alert picks which survives.
private struct MergePair: Identifiable {
    let a: CategoryRow   // the row the merge was started from
    let b: CategoryRow   // the picked other category
    var id: String { a.id + "|" + b.id }
}

/// Categories admin — a 3-level tree (inline expand/collapse) with per-category
/// icon + color, search, create-child, edit, delete (children promote up a
/// level), and **drag to reparent + reorder** (only in Reorder mode, entered via
/// ⋯ → Reorder): drop on a row's middle to nest under it, its top quarter to
/// place the dragged category before it, its bottom quarter to place it after it;
/// the "Top level" zone un-nests. All through the chokepoint (create / update /
/// deleteCategory).
struct CategoriesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var kind: CategoryKind = .expense
    @State private var isReordering = false
    @State private var expanded: Set<String> = []
    @State private var search = ""
    @State private var editing: CategoryRow?
    @State private var creating = false
    @State private var deleting: CategoryRow?
    @State private var selectedCategoryId: String?   // tapped row → transactions
    @State private var mergingFrom: CategoryRow?   // → target picker sheet
    @State private var pendingMerge: MergePair?    // staged in the sheet, promoted on its dismiss
    @State private var mergeChoice: MergePair?     // → keep-which-name alert
    @State private var isSelecting = false                  // ⋯ → Merge multi-select mode
    @State private var selected: Set<String> = []           // ids ticked in select mode
    @State private var mergeManySurvivorChoice: [CategoryRow]?   // → keep-which-name dialog
    @State private var importing = false                    // ⋯ → Import-from-ledger sheet
    @State private var copyingCategory: CategoryRow?          // row → Copy-to-ledger sheet

    @State private var dropTargetId: String?      // row currently targeted by a drag
    @State private var topLevelTargeted = false
    /// The category folded away for the duration of a drag — see `.onDrag` in
    /// `reorderableRow`. Restored by whichever drop handler accepts the drag.
    @State private var collapsedForDrag: String?
    @State private var rowHeights: [String: CGFloat] = [:]   // per-row height for drop-position thirds
    @State private var errorMessage: String?

    private var rows: [CategoryRow] {
        store.pickableCategories.filter { ($0.kind ?? "expense") == kind.rawValue }
    }
    private var byId: [String: CategoryRow] { Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }) }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(rows), expanded: expanded, search: search)
    }

    var body: some View {
        let counts = Selectors.categoryTxCounts(store.txns, store.activeLedgerId)
        // The kind picker is the List's first row (not a safeAreaInset / VStack):
        // that keeps the List the nav stack's primary scroll view so the large
        // "Categories" title renders and collapses normally. See ScheduledTab —
        // safeAreaInset(.top) here makes the title disappear.
        return List {
            Section {
                kindPicker
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if isReordering { topLevelDropZone }
            if rows.isEmpty {
                emptyKindMessage
            } else {
                ForEach(visible) { item in row(item, counts) }
            }
        }
        .modifier(SearchableModifier(text: $search))
        .navigationTitle("Categories")
        .errorAlert($errorMessage)
        .toolbar { toolbarContent }
        .navigationDestination(item: $selectedCategoryId) { id in
            if let c = store.pickableCategories.first(where: { $0.id == id }) {
                CategoryDetailView(category: c)
            }
        }
        // Present the keep-name alert only AFTER the picker sheet has fully
        // dismissed (onDismiss) — chaining dismiss + present in one transaction can
        // drop the second presentation on some iOS versions.
        .sheet(item: $mergingFrom, onDismiss: {
            if let p = pendingMerge { mergeChoice = p; pendingMerge = nil }
        }) { a in
            NavigationStack {
                List {
                    if mergeTargets(excluding: a).isEmpty {
                        ContentUnavailableView("No other categories", systemImage: "arrow.triangle.merge",
                                               description: Text("There's nothing to merge \(a.name) with yet."))
                    } else {
                        ForEach(mergeTargets(excluding: a)) { f in
                            Button {
                                pendingMerge = MergePair(a: a, b: f.row)
                                mergingFrom = nil
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(Color(hex: effectiveColor(f.row, byId)) ?? .gray).frame(width: 24, height: 24)
                                        Image(systemName: CategoryIcon.symbol(for: effectiveIcon(f.row, byId)))
                                            .font(.system(size: 11)).foregroundStyle(.white)
                                    }
                                    Text(String(repeating: "   ", count: f.depth) + f.row.name).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Merge \(a.name) with…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { mergingFrom = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                    }
                }
            }
        }
        .alert("Keep which name after merge?", isPresented: Binding(
            get: { mergeChoice != nil }, set: { if !$0 { mergeChoice = nil } }),
            presenting: mergeChoice) { pair in
            Button("Keep \"\(pair.a.name)\"") { merge(source: pair.b, target: pair.a) }
            Button("Keep \"\(pair.b.name)\"") { merge(source: pair.a, target: pair.b) }
            Button("Cancel", role: .cancel) {}
        } message: { pair in
            if let msg = mergeImpactMessage(txCount: mergeTxCount(pair.a, pair.b)) { Text(msg) }
        }
        // Centered alert (the delete-confirmation style), not a bottom action-sheet
        // popout — consistent with deletes and the pairwise merge prompt.
        .alert("Keep which name?", isPresented: Binding(
            get: { mergeManySurvivorChoice != nil }, set: { if !$0 { mergeManySurvivorChoice = nil } }),
            presenting: mergeManySurvivorChoice) { picks in
            ForEach(picks) { survivor in
                Button("Keep \"\(survivor.name)\"") { mergeMany(keeping: survivor, from: picks) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { picks in
            if let msg = mergeImpactMessage(txCount: mergeManyTxCount(picks)) { Text(msg) }
        }
        .onChange(of: kind) { _, _ in selected = [] }
        .sheet(isPresented: $creating) { CategoryEditSheet(createIn: kind.rawValue) }
        .sheet(item: $editing) { CategoryEditSheet(category: $0) }
        .sheet(isPresented: $importing) {
            LedgerPickerSheet(title: "Import categories from…") { from in
                do { copyDone(try store.applyReturningCount(.copyCategories, Args(["fromLedgerId": .string(from), "toLedgerId": .string(store.activeLedgerId)]))) }
                catch { errorMessage = i18nMessage(error) }
            }
        }
        .sheet(item: $copyingCategory) { c in
            LedgerPickerSheet(title: "Copy \(c.name) to…") { to in
                do { copyDone(try store.applyReturningCount(.copyCategories, Args(["fromLedgerId": .string(store.activeLedgerId), "toLedgerId": .string(to), "ids": .array([.string(c.id)])]))) }
                catch { errorMessage = i18nMessage(error) }
            }
        }
        // A centered ALERT, not a row-anchored confirmationDialog — see
        // ActivityTab (window-level survives swipe collapse / recycling).
        .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting) { c in
            Button("Delete", role: .destructive) { delete(c) }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            if let msg = deleteImpactMessage(
                txCount: counts[c.id] ?? 0,
                subcatCount: rows.filter { $0.parentId == c.id }.count) {
                Text(msg)
            }
        }
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            ForEach(CategoryKind.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// Centered per-kind empty state, shown as a List row so the kind picker
    /// above it stays visible (letting the user switch to the other kind).
    private var emptyKindMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(.secondary)
            Text(kind == .expense ? "No expense categories yet" : "No income categories yet")
                .font(.headline)
            Text("Tap + to add one.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge (\(selected.count))") { mergeManySurvivorChoice = selected.compactMap { byId[$0] }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
                    .disabled(selected.count < 2)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { isSelecting = false; selected = [] } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel")
            }
        } else if isReordering {
            ToolbarItem(placement: .confirmationAction) {
                Button { isReordering = false; dropTargetId = nil; topLevelTargeted = false } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Done")
                    .confirmCheckmarkStyle()
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New category")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isReordering = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                    Button { isSelecting = true; selected = [] } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                    Button { importing = true } label: { Label("Import from another ledger…", systemImage: "square.and.arrow.down.on.square") }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
            }
        }
    }

    /// Drop here to move a category to the top level (un-nest).
    private var topLevelDropZone: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.to.line").font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text("Top level").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let src = items.first, let m = CategoryReorder.reparent(src, under: nil, in: rows) else {
                restoreCollapsedForDrag(); return false
            }
            applyMoves([m])
            restoreCollapsedForDrag()
            return true
        } isTargeted: { topLevelTargeted = $0 }
        .listRowBackground(topLevelTargeted ? Color.accentColor.opacity(0.15) : nil)
    }

    /// A row in reorder mode, draggable and droppable.
    ///
    /// **`.onDrag`, not `.draggable`, for one reason: it is the only lift hook.**
    /// A move rewrites just the dragged row's `parentId`/`sortOrder`, so its children
    /// point at it and travel with it — but an expanded parent lifts as ONE row while
    /// its children sit still in the list, which reads as the parent tearing itself
    /// out of its own group. Folding it on lift makes that one row genuinely *be* the
    /// group, and hides the descendants that could otherwise be dropped onto (which
    /// `reorder` would turn into `parentId == sourceId` for the engine to reject).
    ///
    /// **SwiftUI has no drag-END callback**, so the restore happens in the drop
    /// handlers. A drag abandoned mid-air therefore leaves the parent collapsed —
    /// one chevron tap to reopen, and that chevron is now a 44pt target.
    @ViewBuilder private func reorderableRow(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
        let c = item.row
        rowContent(item, counts)
            // Capture row height (background GeometryReader doesn't affect
            // layout or block taps) so the drop handler can map location.y.
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { rowHeights[c.id] = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in rowHeights[c.id] = h }
            })
            .onDrag {
                if expanded.contains(c.id) {
                    expanded.remove(c.id)
                    collapsedForDrag = c.id
                }
                return NSItemProvider(object: c.id as NSString)
            }
            .dropDestination(for: String.self) { items, location in
                guard let src = items.first else { return false }
                let h = rowHeights[c.id] ?? 44
                let frac = h > 0 ? location.y / h : 0.5
                let moves: [CategoryMove]
                if frac < 0.25 {
                    moves = CategoryReorder.reorder(src, .before, of: c.id, in: rows)
                } else if frac > 0.75 {
                    moves = CategoryReorder.reorder(src, .after, of: c.id, in: rows)
                } else {
                    moves = CategoryReorder.reparent(src, under: c.id, in: rows).map { [$0] } ?? []
                }
                guard !moves.isEmpty else { restoreCollapsedForDrag(); return false }
                applyMoves(moves)
                restoreCollapsedForDrag()
                return true
            } isTargeted: { isTargeted in
                if isTargeted { dropTargetId = c.id }
                else if dropTargetId == c.id { dropTargetId = nil }
            }
            .listRowBackground(dropTargetId == c.id ? Color.accentColor.opacity(0.15) : nil)
    }

    /// Re-expand whatever `.onDrag` folded away, so the group is visibly intact at
    /// its new home — and so a move the engine refused gives back the tree you had.
    private func restoreCollapsedForDrag() {
        guard let id = collapsedForDrag else { return }
        expanded.insert(id)
        collapsedForDrag = nil
    }

    @ViewBuilder private func row(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
        let c = item.row
        if isSelecting {
            rowContent(item, counts)   // rowContent shows the checkmark + toggles selection
        } else if isReordering {
            if search.isEmpty {
                reorderableRow(item, counts)
            } else {
                // No dragging while searching. The visible list is filtered AND
                // force-expanded, but `CategoryReorder` computes sibling order from
                // the FULL row list, so a drag here would rearrange something you
                // cannot see — and the collapse-on-lift below is impossible anyway,
                // because search overrides `expanded`. The chevron is already inert
                // during search for the same reason.
                rowContent(item, counts)
            }
        } else {
            rowContent(item, counts)
                .swipeActions(edge: .trailing) {
                    // Edit is declared first so it sits at the outer edge and is the
                    // full-swipe action — a careless full swipe edits, never deletes.
                    Button { editing = c } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
                    // Not role: .destructive — see ActivityTab (fake removal
                    // animation kills the row-anchored popout).
                    Button { deleting = c } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                    Button { mergingFrom = c } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }.tint(.orange)
                }
                .contextMenu {
                    Button { editing = c } label: { Label("Edit", systemImage: "pencil") }
                    Button { mergingFrom = c } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                    Button { copyingCategory = c } label: { Label("Copy to another ledger…", systemImage: "square.and.arrow.up.on.square") }
                    Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    /// The shared row visual. In select mode it shows a leading checkmark and taps
    /// toggle selection (relatives of a selected row are dimmed + inert); otherwise
    /// the swatch/name/count opens the category's transactions, with a trailing
    /// disclosure chevron for parents. The trailing chevron here means "expands
    /// children" (unlike Tags/Merchants' nav chevron) — kept trailing-only so the
    /// leading edge stays a clean, aligned icon column.
    ///
    /// Reorder mode swaps the count pill for a `ReorderGrip` rather than adding
    /// one, so the trailing chrome stays two slots wide in both modes and the name
    /// column doesn't reflow on entering or leaving Reorder. The chevron stays live
    /// throughout — you need to expand a parent to drop something inside it.
    @ViewBuilder private func rowContent(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
        let c = item.row
        let selectDisabled = isSelecting && mergeSelectionDisabled(c.id, selected: selected, byId: byId)
        HStack(spacing: 8) {
            if isSelecting {
                Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected.contains(c.id) ? Color.accentColor : .secondary)
            }
            Button {
                if isSelecting {
                    if !selectDisabled {
                        if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
                    }
                } else if !isReordering {
                    selectedCategoryId = c.id
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 26, height: 26)
                        Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                            .font(.system(size: 12)).foregroundStyle(.white)
                    }
                    Text(c.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isReordering { CountPill(count: counts[c.id] ?? 0) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.hasChildren {
                Button {
                    if expanded.contains(c.id) { expanded.remove(c.id) } else { expanded.insert(c.id) }
                } label: {
                    ExpandChevron(expanded: expanded.contains(c.id) || !search.isEmpty)
                }
                .buttonStyle(.plain)
                .disabled(!search.isEmpty)   // search force-expands; chevron is inert
            } else {
                // Reserve the chevron slot on leaf rows so count pills / trailing
                // edges line up across parent and leaf rows.
                ExpandChevron.slot
            }

            if isReordering { ReorderGrip() }
        }
        .padding(.leading, CGFloat(item.depth) * 14)
        .opacity(selectDisabled ? 0.35 : 1)
        .accessibilityAddTraits(isSelecting && selected.contains(c.id) ? [.isSelected] : [])
        .contentShape(Rectangle())
    }

    /// Apply one or more category moves (parentId + sortOrder) through the
    /// chokepoint, in order. The engine rejects self/descendant/depth>3 with a
    /// localized error; on the first throw we stop and surface it.
    /// Confirm a copy: these actions dedup against the target, so a bare "done"
    /// would look identical whether 12 rows landed or none did. Also the ONLY
    /// feedback for the copy-OUT direction, where the target isn't the ledger on
    /// screen and nothing visibly changes.
    private func copyDone(_ added: Int) {
        Haptics.success()
        ToastCenter.shared.show(added > 0 ? "\(added) added" : "Nothing new to copy")
    }

    private func applyMoves(_ moves: [CategoryMove]) {
        errorMessage = nil
        do {
            for m in moves {
                try store.apply(.updateCategory, Args(["id": .string(m.id), "patch": .object(movePatch(m))]))
            }
        } catch { errorMessage = i18nMessage(error) }
    }

    private func movePatch(_ m: CategoryMove) -> [String: JSONValue] {
        var patch: [String: JSONValue] = ["sortOrder": .int(m.sortOrder)]
        patch["parentId"] = m.parentId.map(JSONValue.string) ?? .null
        return patch
    }

    private func delete(_ c: CategoryRow) {
        errorMessage = nil
        do { try store.apply(.deleteCategory, Args(["id": .string(c.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    /// Same-kind categories eligible as a merge target: everything in the current
    /// kind except `a` itself and `a`'s descendants (no depth filter — a target may
    /// be at any depth, including an ancestor of `a`). Tree-ordered for an indented list.
    private func mergeTargets(excluding a: CategoryRow) -> [FlatCategory] {
        let flat = flattenCategories(categoryForest(rows), expanded: Set(rows.map(\.id)), search: "")
        var excluded: Set<String> = [a.id]
        for f in flat where f.row.parentId.map(excluded.contains) == true { excluded.insert(f.row.id) }
        return flat.filter { !excluded.contains($0.row.id) }
    }

    /// Choice-independent union of transactions referencing either category.
    private func mergeTxCount(_ a: CategoryRow, _ b: CategoryRow) -> Int {
        let ledger = store.activeLedgerId
        let ids = Set(Selectors.categoryTransactions(store.txns, a.id, ledger).map(\.id))
            .union(Selectors.categoryTransactions(store.txns, b.id, ledger).map(\.id))
        return ids.count
    }

    private func merge(source: CategoryRow, target: CategoryRow) {
        errorMessage = nil
        mergeChoice = nil
        do { try store.apply(.mergeCategory, Args(["sourceId": .string(source.id), "targetId": .string(target.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    /// Combined transaction count across the selected categories (choice-independent).
    private func mergeManyTxCount(_ catRows: [CategoryRow]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for c in catRows { ids.formUnion(Selectors.categoryTransactions(store.txns, c.id, ledger).map(\.id)) }
        return ids.count
    }

    /// Merge every selected category except the survivor into it, atomically.
    private func mergeMany(keeping survivor: CategoryRow, from all: [CategoryRow]) {
        errorMessage = nil
        mergeManySurvivorChoice = nil
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        do {
            try store.apply(.mergeCategories, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false; selected = []
        } catch { errorMessage = i18nMessage(error) }
    }
}

/// Create a category (`init(createIn:)`, optional preset parent) or edit an
/// existing one (`init(category:)`). Name, **parent**, icon, and color are all
/// editable; kind is fixed to the sheet's kind so a category with transactions
/// never crosses expense↔income. Choosing a parent nests the category (or moves
/// it, on edit); "None" keeps/makes it top-level. Reparent sort-order reuses the
/// same `CategoryReorder.reparent` math as drag.
struct CategoryEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let category: CategoryRow?       // nil = create
    @State private var kindSel: String   // editable on create; fixed (read-only) on edit
    @State private var name: String
    @State private var parentId: String?    // nil = top level
    @State private var icon: String     // "" = none (inherit at render)
    @State private var color: String    // "" = none (inherit/default at render)
    @State private var errorMessage: String?

    init(createIn kind: String, parentId: String? = nil) {
        self.category = nil
        _kindSel = State(initialValue: kind)
        _name = State(initialValue: "")
        _parentId = State(initialValue: parentId)
        _icon = State(initialValue: ""); _color = State(initialValue: "")
    }
    init(category: CategoryRow) {
        self.category = category
        _kindSel = State(initialValue: category.kind ?? "expense")
        _name = State(initialValue: category.name)
        _parentId = State(initialValue: category.parentId)
        _icon = State(initialValue: category.icon ?? "")
        _color = State(initialValue: category.color ?? "")
    }

    /// Same-kind categories eligible as a parent: depth < 2 (so the child stays
    /// within the 3-level cap) and, when editing, excluding the category itself
    /// and its descendants. Tree-ordered for an indented menu.
    private var parentOptions: [FlatCategory] {
        let all = store.pickableCategories.filter { ($0.kind ?? "expense") == kindSel }
        let flat = flattenCategories(categoryForest(all), expanded: Set(all.map(\.id)), search: "")
        var excluded = Set<String>()
        if let c = category {
            excluded.insert(c.id)
            for f in flat where f.row.parentId.map(excluded.contains) == true { excluded.insert(f.row.id) }
        }
        return flat.filter { $0.depth < 2 && !excluded.contains($0.row.id) }
    }

    /// Bridges the `String?` parentId to CategoryPickerRow's `String` (empty == top level).
    private var parentBinding: Binding<String> {
        Binding(get: { parentId ?? "" }, set: { parentId = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                if category == nil {
                    Picker("Type", selection: $kindSel) {
                        Text("Expense").tag("expense")
                        Text("Income").tag("income")
                    }
                    .pickerStyle(.segmented)
                } else {
                    LabeledContent("Type", value: kindSel == "income" ? "Income" : "Expense")
                }
                TextField("Name", text: $name)
                // The same swatch+icon tree the transaction Category field uses
                // (and the Categories page renders), restricted to eligible
                // parents, with "None (top level)" as the empty choice.
                // String(localized:) because both params are plain Strings —
                // literals would bypass extraction and ship English in zh-Hans.
                CategoryPickerRow(title: String(localized: "Parent"), glyph: .category, categories: parentOptions.map(\.row),
                                  selection: parentBinding, noneLabel: String(localized: "None (top level)"))
                IconPickerRow(title: "Icon", glyph: .icon, selection: $icon)
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(CategoryPalette.hexes, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == hex ? 2.5 : 0))
                                .contentShape(Circle())
                                .onTapGesture { color = (color == hex ? "" : hex) }
                                .accessibilityLabel("Color \(hex)")
                        }
                    }
                }
                Section {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                } footer: {
                    Text("When unset, icon and color inherit from the parent category, or fall back to a default.")
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .onChange(of: kindSel) { _, _ in parentId = nil }   // parents are kind-specific
            .finchSectionSpacing()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").confirmCheckmarkStyle()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let c = category {
                var patch: [String: JSONValue] = [
                    "name": .string(trimmed),
                    "icon": icon.isEmpty ? .null : .string(icon),
                    "color": color.isEmpty ? .null : .string(color),
                ]
                if parentId != c.parentId {
                    // Reparent: place last in the new parent's group (same math as drag).
                    let kinRows = store.pickableCategories.filter { ($0.kind ?? "expense") == kindSel }
                    let sortOrder = CategoryReorder.reparent(c.id, under: parentId, in: kinRows)?.sortOrder ?? 0
                    patch["parentId"] = parentId.map(JSONValue.string) ?? .null
                    patch["sortOrder"] = .int(sortOrder)
                }
                try store.apply(.updateCategory, Args(["id": .string(c.id), "patch": .object(patch)]))
            } else {
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                    "type": .string(kindSel),
                ]
                if !icon.isEmpty { args["icon"] = .string(icon) }
                if !color.isEmpty { args["color"] = .string(color) }
                if let parentId { args["parentId"] = .string(parentId) }
                try store.apply(.createCategory, Args(args))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
