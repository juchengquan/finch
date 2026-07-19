import SwiftUI
import FinchCore

/// Categories admin — a 3-level tree (inline expand/collapse) with per-category
/// icon + color, search, create-child, edit, delete (children promote up a
/// level), and **drag to reparent + reorder**: drop on a row's middle to nest
/// under it, its top quarter to place the dragged category before it, its bottom
/// quarter to place it after it; the "Top level" zone un-nests. All through the
/// chokepoint (create / update / deleteCategory).
struct CategoriesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var expanded: Set<String> = []
    @State private var search = ""
    @State private var editing: CategoryRow?
    @State private var creatingTop = false
    @State private var creatingUnder: CategoryRow?
    @State private var deleting: CategoryRow?
    @State private var dropTargetId: String?      // row currently targeted by a drag
    @State private var topLevelTargeted = false
    @State private var rowHeights: [String: CGFloat] = [:]   // per-row height for drop-position thirds
    @State private var errorMessage: String?

    private var rows: [CategoryRow] { store.pickableCategories }
    private var byId: [String: CategoryRow] { Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }) }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(rows), expanded: expanded, search: search)
    }

    var body: some View {
        let counts = Selectors.categoryTxCounts(store.txns, store.activeLedgerId)
        return List {
            topLevelDropZone
            ForEach(visible) { item in row(item, counts) }
        }
        .modifier(SearchableModifier(text: $search))
        .navigationTitle("Categories")
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingTop = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $creatingTop) { CategoryEditSheet(category: nil) }
        .sheet(item: $creatingUnder) { parent in CategoryEditSheet(category: nil, parent: parent) }
        .sheet(item: $editing) { CategoryEditSheet(category: $0) }
        // A centered ALERT, not a row-anchored confirmationDialog — see
        // ActivityTab (window-level survives swipe collapse / recycling).
        .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting) { c in
            Button("Delete", role: .destructive) { delete(c) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its subcategories move up a level — they won't be deleted.")
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
        HStack(spacing: 8) {
            if item.hasChildren {
                Button {
                    if expanded.contains(c.id) { expanded.remove(c.id) } else { expanded.insert(c.id) }
                } label: {
                    Image(systemName: (expanded.contains(c.id) || !search.isEmpty) ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                }
                .buttonStyle(.plain)
                .disabled(!search.isEmpty)   // search force-expands; chevron is inert
            } else {
                Color.clear.frame(width: 16)
            }

            ZStack {
                Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 28, height: 28)
                Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                    .font(.system(size: 13)).foregroundStyle(.white)
            }

            Button { editing = c } label: {
                Text(c.name).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let n = counts[c.id], n > 0 {
                Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("\(n) transactions")
            }

            if item.depth < 2 {   // engine caps nesting at 3 levels
                Button { creatingUnder = c } label: {
                    Image(systemName: "plus.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add subcategory under \(c.name)")
            }
        }
        .padding(.leading, CGFloat(item.depth) * 16)
        .contentShape(Rectangle())
        // Capture the row's height (background GeometryReader doesn't affect layout
        // or block taps) so the drop handler can map location.y → top/mid/bottom.
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
        .swipeActions(edge: .trailing) {
            // Not role: .destructive — see ActivityTab (fake removal animation
            // kills the row-anchored popout).
            Button { deleting = c } label: { Label("Delete", systemImage: "trash") }.tint(.red)
        }
        .contextMenu {
            Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
        }
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

/// Create (category == nil), create-under-a-parent (parent != nil), or edit an
/// existing category. Name + icon + color always; kind is create-top-level only.
struct CategoryEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let category: CategoryRow?
    let parent: CategoryRow?
    @State private var name: String
    @State private var kind: String
    @State private var icon: String     // "" = none (inherit at render)
    @State private var color: String    // "" = none (inherit/default at render)
    @State private var errorMessage: String?

    init(category: CategoryRow?, parent: CategoryRow? = nil) {
        self.category = category
        self.parent = parent
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: category?.kind ?? parent?.kind ?? "expense")
        _icon = State(initialValue: category?.icon ?? "")
        _color = State(initialValue: category?.color ?? "")
    }

    private let iconColumns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if category == nil && parent == nil {
                    Picker("Kind", selection: $kind) { Text("Expense").tag("expense"); Text("Income").tag("income") }
                        .pickerStyle(.segmented)
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
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").bold()
                }
            }
        }
    }

    private var title: String {
        if category != nil { return "Edit Category" }
        if let parent { return "New under \(parent.name)" }
        return "New Category"
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let c = category {
                let patch: [String: JSONValue] = [
                    "name": .string(trimmed),
                    "icon": icon.isEmpty ? .null : .string(icon),
                    "color": color.isEmpty ? .null : .string(color),
                ]
                try store.apply(.updateCategory, Args(["id": .string(c.id), "patch": .object(patch)]))
            } else {
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed), "type": .string(kind),
                ]
                if !icon.isEmpty { args["icon"] = .string(icon) }
                if !color.isEmpty { args["color"] = .string(color) }
                if let parent { args["parentId"] = .string(parent.id) }
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
