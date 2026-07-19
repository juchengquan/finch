import SwiftUI
import FinchCore

/// Expense/income filter for the Categories page (maps to `CategoryRow.kind`).
private enum CategoryKind: String, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .expense ? "Expense" : "Income" }
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

    @State private var dropTargetId: String?      // row currently targeted by a drag
    @State private var topLevelTargeted = false
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
        .sheet(isPresented: $creating) { CategoryEditSheet(createIn: kind.rawValue) }
        .sheet(item: $editing) { CategoryEditSheet(category: $0) }
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
        if isReordering {
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
                } label: { Image(systemName: "ellipsis.circle") }
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
            guard let src = items.first, let m = CategoryReorder.reparent(src, under: nil, in: rows) else { return false }
            applyMoves([m]); return true
        } isTargeted: { topLevelTargeted = $0 }
        .listRowBackground(topLevelTargeted ? Color.accentColor.opacity(0.15) : nil)
    }

    @ViewBuilder private func row(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
        let c = item.row
        if isReordering {
            rowContent(item, counts)
                // Capture row height (background GeometryReader doesn't affect
                // layout or block taps) so the drop handler can map location.y.
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { rowHeights[c.id] = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, h in rowHeights[c.id] = h }
                })
                .draggable(c.id)
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
                    guard !moves.isEmpty else { return false }
                    applyMoves(moves); return true
                } isTargeted: { isTargeted in
                    if isTargeted { dropTargetId = c.id }
                    else if dropTargetId == c.id { dropTargetId = nil }
                }
                .listRowBackground(dropTargetId == c.id ? Color.accentColor.opacity(0.15) : nil)
        } else {
            rowContent(item, counts)
                .swipeActions(edge: .trailing) {
                    // Edit is declared first so it sits at the outer edge and is the
                    // full-swipe action — a careless full swipe edits, never deletes.
                    Button { editing = c } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
                    // Not role: .destructive — see ActivityTab (fake removal
                    // animation kills the row-anchored popout).
                    Button { deleting = c } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                }
                .contextMenu {
                    Button { editing = c } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    /// The shared row visual: a tap target (swatch + name + count pill) that opens
    /// the category's transactions, plus — for parents — a trailing disclosure
    /// chevron that expands/collapses. The swatch is leftmost (no leading gutter)
    /// and the chevron is on the right, so rows read tight. Mode-specific modifiers
    /// (drag vs swipe) are applied by `row`; tap-navigation is inert while reordering.
    @ViewBuilder private func rowContent(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
        let c = item.row
        HStack(spacing: 8) {
            Button {
                if !isReordering { selectedCategoryId = c.id }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 26, height: 26)
                        Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                            .font(.system(size: 12)).foregroundStyle(.white)
                    }
                    Text(c.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let n = counts[c.id], n > 0 {
                        Text("\(n)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                            .accessibilityLabel("\(n) transactions")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.hasChildren {
                Button {
                    if expanded.contains(c.id) { expanded.remove(c.id) } else { expanded.insert(c.id) }
                } label: {
                    Image(systemName: (expanded.contains(c.id) || !search.isEmpty) ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 22, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!search.isEmpty)   // search force-expands; chevron is inert
            } else {
                // Reserve the chevron slot on leaf rows so count pills / trailing
                // edges line up across parent and leaf rows.
                Color.clear.frame(width: 22, height: 30)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 14)
        .contentShape(Rectangle())
    }

    /// Apply one or more category moves (parentId + sortOrder) through the
    /// chokepoint, in order. The engine rejects self/descendant/depth>3 with a
    /// localized error; on the first throw we stop and surface it.
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
    let kind: String                 // fixed kind for this sheet
    @State private var name: String
    @State private var parentId: String?    // nil = top level
    @State private var icon: String     // "" = none (inherit at render)
    @State private var color: String    // "" = none (inherit/default at render)
    @State private var errorMessage: String?

    init(createIn kind: String, parentId: String? = nil) {
        self.category = nil; self.kind = kind
        _name = State(initialValue: "")
        _parentId = State(initialValue: parentId)
        _icon = State(initialValue: ""); _color = State(initialValue: "")
    }
    init(category: CategoryRow) {
        self.category = category; self.kind = category.kind ?? "expense"
        _name = State(initialValue: category.name)
        _parentId = State(initialValue: category.parentId)
        _icon = State(initialValue: category.icon ?? "")
        _color = State(initialValue: category.color ?? "")
    }

    private let iconColumns = Array(repeating: GridItem(.flexible()), count: 6)

    /// Same-kind categories eligible as a parent: depth < 2 (so the child stays
    /// within the 3-level cap) and, when editing, excluding the category itself
    /// and its descendants. Tree-ordered for an indented menu.
    private var parentOptions: [FlatCategory] {
        let all = store.pickableCategories.filter { ($0.kind ?? "expense") == kind }
        let flat = flattenCategories(categoryForest(all), expanded: Set(all.map(\.id)), search: "")
        var excluded = Set<String>()
        if let c = category {
            excluded.insert(c.id)
            for f in flat where f.row.parentId.map(excluded.contains) == true { excluded.insert(f.row.id) }
        }
        return flat.filter { $0.depth < 2 && !excluded.contains($0.row.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Parent", selection: $parentId) {
                    Text("None (top level)").tag(String?.none)
                    ForEach(parentOptions) { f in
                        Text(String(repeating: "   ", count: f.depth) + f.row.name).tag(Optional(f.row.id))
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: iconColumns, spacing: 12) {
                        ForEach(CategoryIcon.names, id: \.self) { n in
                            Image(systemName: CategoryIcon.symbol(for: n))
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(icon == n ? Color.accentColor.opacity(0.2) : .clear))
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: icon == n ? 2 : 0))
                                .contentShape(Circle())
                                .onTapGesture { icon = (icon == n ? "" : n) }
                                .accessibilityLabel("Icon \(n)")
                        }
                    }
                    .padding(.vertical, 4)
                }
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
                    let kinRows = store.pickableCategories.filter { ($0.kind ?? "expense") == kind }
                    let sortOrder = CategoryReorder.reparent(c.id, under: parentId, in: kinRows)?.sortOrder ?? 0
                    patch["parentId"] = parentId.map(JSONValue.string) ?? .null
                    patch["sortOrder"] = .int(sortOrder)
                }
                try store.apply(.updateCategory, Args(["id": .string(c.id), "patch": .object(patch)]))
            } else {
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                    "type": .string(kind),
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

/// Cross-platform search: uses `.navigationBarDrawer(displayMode:.always)` on iOS
/// (keeps search bar always visible) and the default placement on macOS.
private struct SearchableModifier: ViewModifier {
    @Binding var text: String
    func body(content: Content) -> some View {
        #if os(iOS)
        content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
        #else
        content.searchable(text: $text)
        #endif
    }
}
