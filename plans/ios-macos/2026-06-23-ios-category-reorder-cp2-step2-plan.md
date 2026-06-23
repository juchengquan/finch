# Category sibling reorder (CP2 Step 2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a drag reorder categories among their siblings — drop on a row's top quarter to place the dragged category *before* it, the bottom quarter to place it *after*, the middle to nest under it (Step 1) — persisting the new order via `sort_order`.

**Architecture:** Two pieces, no engine change (reuses Step 1's `updateCategory` `sortOrder` patch): (1) extend the pure `CategoryReorder` helper with `reorder(_:_:of:in:)` that inserts the source before/after a target within the target's sibling group and returns the renumbered `CategoryMove`s; (2) in `CategoryAdminView`, read the drop **location** in the row's `.dropDestination` action + the row height (captured via a background `GeometryReader`) to pick before/nest/after, and apply the moves. Position is decided **at drop** (SwiftUI's `isTargeted` is location-less, so there's no live insertion line — the existing row highlight is the hover feedback).

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest. FinchCore tests via `swift test`; FinchApp via `xcodebuild … -only-testing:FinchAppTests/…`.

## Global Constraints

- **No engine change.** Step 1 already added `sortOrder` to `FinchCore.updateCategory`; reorder reuses it. Do not touch `frontend/` or FinchCore engine code.
- **Position decided at drop** (not a live insertion line): top quarter (`y/height < 0.25`) → insert *before*; bottom quarter (`> 0.75`) → insert *after*; middle (`0.25…0.75`, generous) → nest under the row (the existing Step 1 reparent). Hover feedback is the existing row highlight.
- **Reorder renumbers the affected sibling group contiguously** (`sort_order` 0,1,2,…) — the `BudgetGroupsView.onReorder` pattern. A move whose source comes from another parent both reparents and positions; the engine's guards (self / under-descendant / depth>3) still apply to the source and surface via `errorAlert`.
- **Must build iOS AND macOS.** No macOS-unavailable API. Sim: `iPhone 17 Pro Max`. New `.swift` files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit messages; **no `Co-Authored-By` trailer**.
- **Known limitation (acceptable for v1):** drag *gestures* aren't scriptable via simctl, so the feel is verified by hands-on sim use; the move *logic* is unit-tested. If the thirds gesture tests poorly, the spec's fallback is a "Move up / Move down" action (not in this plan).

---

## File Structure

**Modify (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift` — add `enum InsertPosition` + `reorder(_:_:of:in:)`.
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` — capture row height; row `.dropDestination` reads location → before/nest/after; add `applyMoves` + `movePatch`.

**Modify (tests):**
- `ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift` — add reorder tests (reuse the existing `cat(...)` helper).

**Common run commands:**
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/<ClassName>
```

---

### Task 1: `CategoryReorder.reorder` — sibling insertion + renumber (pure)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift` (add tests)

**Interfaces:**
- Consumes: `CategoryRow` (has `id`, `parentId`, `sortOrder`); `CategoryMove` (existing).
- Produces:
  - `enum InsertPosition { case before, after }`
  - `static func reorder(_ sourceId: String, _ position: InsertPosition, of targetId: String, in rows: [CategoryRow]) -> [CategoryMove]` — inserts `sourceId` before/after `targetId` within `targetId`'s sibling group (parent = target's parent), renumbers that group contiguously, and returns a `CategoryMove` for every member in the new order (`parentId` = the target's parent, `sortOrder` = its new index). Returns `[]` for a no-op (source == target, target missing, or the resulting order equals the current order). `rows` is the projection's `sort_order`-ordered list, so filtering preserves sibling order.

- [ ] **Step 1: Write the failing tests**

Append to `ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift` (inside the `CategoryReorderTests` class, after the existing reparent tests):

```swift
    // MARK: reorder (CP2 Step 2)

    func test_reorder_within_parent_move_down() {
        // food children a(0), b(1), c(2); move a to AFTER c → [b, c, a] renumbered 0,1,2
        let rows = [cat("food"), cat("a", parent: "food", sortOrder: 0),
                    cat("b", parent: "food", sortOrder: 1), cat("c", parent: "food", sortOrder: 2)]
        XCTAssertEqual(CategoryReorder.reorder("a", .after, of: "c", in: rows), [
            CategoryMove(id: "b", parentId: "food", sortOrder: 0),
            CategoryMove(id: "c", parentId: "food", sortOrder: 1),
            CategoryMove(id: "a", parentId: "food", sortOrder: 2),
        ])
    }

    func test_reorder_within_parent_move_up() {
        // move c to BEFORE a → [c, a, b]
        let rows = [cat("food"), cat("a", parent: "food", sortOrder: 0),
                    cat("b", parent: "food", sortOrder: 1), cat("c", parent: "food", sortOrder: 2)]
        XCTAssertEqual(CategoryReorder.reorder("c", .before, of: "a", in: rows), [
            CategoryMove(id: "c", parentId: "food", sortOrder: 0),
            CategoryMove(id: "a", parentId: "food", sortOrder: 1),
            CategoryMove(id: "b", parentId: "food", sortOrder: 2),
        ])
    }

    func test_reorder_cross_parent_inserts_and_reparents() {
        // x lives under "other"; drop x BEFORE b (under food) → food group [a, x, b]
        let rows = [cat("food"), cat("a", parent: "food", sortOrder: 0), cat("b", parent: "food", sortOrder: 1),
                    cat("other"), cat("x", parent: "other", sortOrder: 0)]
        XCTAssertEqual(CategoryReorder.reorder("x", .before, of: "b", in: rows), [
            CategoryMove(id: "a", parentId: "food", sortOrder: 0),
            CategoryMove(id: "x", parentId: "food", sortOrder: 1),
            CategoryMove(id: "b", parentId: "food", sortOrder: 2),
        ])
    }

    func test_reorder_to_top_level_group() {
        // top level [food, other]; move "other" BEFORE "food" → [other, food]
        let rows = [cat("food", sortOrder: 0), cat("other", sortOrder: 1)]
        XCTAssertEqual(CategoryReorder.reorder("other", .before, of: "food", in: rows), [
            CategoryMove(id: "other", parentId: nil, sortOrder: 0),
            CategoryMove(id: "food", parentId: nil, sortOrder: 1),
        ])
    }

    func test_reorder_in_place_is_noop() {
        // dropping a BEFORE b when order is already [a, b, c] → no change
        let rows = [cat("food"), cat("a", parent: "food", sortOrder: 0),
                    cat("b", parent: "food", sortOrder: 1), cat("c", parent: "food", sortOrder: 2)]
        XCTAssertEqual(CategoryReorder.reorder("a", .before, of: "b", in: rows), [])
    }

    func test_reorder_self_is_noop() {
        let rows = [cat("a", parent: "food", sortOrder: 0)]
        XCTAssertEqual(CategoryReorder.reorder("a", .before, of: "a", in: rows), [])
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/CategoryReorderTests
```
Expected: FAIL to compile — `InsertPosition` / `reorder` undefined.

- [ ] **Step 3: Implement `reorder`**

In `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift`, add `import`-level enum + the method inside `enum CategoryReorder` (after `reparent`):

```swift
/// Where a sibling-reorder drop lands relative to the target row.
enum InsertPosition { case before, after }
```

and inside `enum CategoryReorder { … }`:

```swift
    /// Insert `sourceId` before/after `targetId` within the target's sibling
    /// group (parent = the target's parent), renumbering that group 0,1,2,….
    /// Returns a move for every member in the new order, or `[]` for a no-op
    /// (source == target, target missing, or order unchanged). `rows` is the
    /// projection's sort_order-ordered list, so the filtered group is in order.
    static func reorder(_ sourceId: String, _ position: InsertPosition, of targetId: String, in rows: [CategoryRow]) -> [CategoryMove] {
        guard sourceId != targetId,
              let target = rows.first(where: { $0.id == targetId }),
              let source = rows.first(where: { $0.id == sourceId }) else { return [] }
        let destParent = target.parentId
        var group = rows.filter { $0.parentId == destParent && $0.id != sourceId }
        guard let ti = group.firstIndex(where: { $0.id == targetId }) else { return [] }
        let insertAt = position == .before ? ti : ti + 1
        group.insert(source, at: insertAt)
        // No-op: the group already has exactly this id order (source already in place).
        let currentIds = rows.filter { $0.parentId == destParent }.map(\.id)
        if currentIds == group.map(\.id) { return [] }
        return group.enumerated().map { idx, row in
            CategoryMove(id: row.id, parentId: destParent, sortOrder: idx)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/CategoryReorderTests
```
Expected: PASS (existing 5 reparent tests + 6 new reorder tests = 11).

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift \
        ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift
git commit -m "feat(ios): CategoryReorder.reorder — sibling insert + renumber"
```

---

### Task 2: Position-aware drop in `CategoryAdminView`

**Files:**
- Modify (full rewrite): `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift`

**Interfaces:**
- Consumes: `CategoryReorder.reorder`/`reparent`, `CategoryMove`, `InsertPosition` (Task 1); `updateCategory` `sortOrder` patch (Step 1).
- Produces: the position-aware drag UX. No new public symbols.

- [ ] **Step 1: Replace the view file**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` with (Step 1 view + a row-height capture, a thirds-aware row drop, and `applyMoves`/`movePatch`):

```swift
import SwiftUI
import FinchCore

/// Categories admin — a 3-level tree (inline expand/collapse) with per-category
/// icon + color, search, create-child, edit, delete (children promote up a
/// level), and **drag to reparent + reorder**: drop on a row's middle to nest
/// under it, its top quarter to place the dragged category before it, its bottom
/// quarter to place it after it; the "Top level" zone un-nests. All through the
/// chokepoint (create / update / deleteCategory).
struct CategoryAdminView: View {
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
        List {
            topLevelDropZone
            ForEach(visible) { item in row(item) }
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
        .confirmationDialog("Delete \(deleting?.name ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible,
                            presenting: deleting) { c in
            Button("Delete", role: .destructive) { delete(c) }
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

    @ViewBuilder private func row(_ item: FlatCategory) -> some View {
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
```

- [ ] **Step 2: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (incl. CategoryReorderTests' new cases + all prior).

- [ ] **Step 3: Build macOS (FinchMac) — CI gate**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification on the simulator**

Build/install/launch to Categories (create a few siblings under one parent if the seed lacks them), then:
- **Reorder down:** drag a sibling and drop on the **bottom quarter** of a lower sibling → it lands *after* that sibling; the order persists across relaunch.
- **Reorder up:** drag and drop on the **top quarter** of a higher sibling → it lands *before* it.
- **Still nests:** drop on the **middle** of a row → it becomes that row's child (Step 1 behavior intact).
- **Cross-parent insert:** drag a child out and drop on the top/bottom quarter of a row under a different parent → it joins that parent at that position.
- **Un-nest:** the **Top level** zone still works.
- **Invalid:** an under-descendant / depth>3 drop surfaces the engine error (no change persists).
- Confirm CP1 + Step 1 flows (tap-edit, create-child, search, swipe-delete, reparent) still work.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift
git commit -m "feat(ios): drag to reorder siblings (drop on row top/bottom quarter)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-23-ios-category-reparent-cp2-design.md`, Step 2):
- Sibling reorder via between-rows drop (insert before/after) → Tasks 1 + 2. ✓
- Renumber the affected group (`BudgetGroupsView` loop pattern) → `reorder` + `applyMoves`. ✓
- Position-sensitive drop (top/mid/bottom) reusing Step 1's nest for the middle → Task 2. ✓
- Cross-parent before/after reparents + positions → `reorder` (parent = target's parent) + engine guards. ✓
- No engine change (reuses Step 1 `sortOrder`); iOS + macOS build; full tests green → Task 2 steps 2-3. ✓
- **Insertion line** (live, finger-following) → intentionally **not** built (SwiftUI `isTargeted` is location-less); decided-at-drop + row highlight instead. Documented in Global Constraints. Fallback ("Move up/down") not in scope.

**Placeholder scan:** No TBD/TODO; every code step has complete code; the sim step lists concrete checks. ✓

**Type consistency:** `InsertPosition`/`reorder(_:_:of:in:)` (Task 1) match the Task 2 call sites; `reorder` returns `[CategoryMove]` consumed by `applyMoves([CategoryMove])`; `reparent` still returns `CategoryMove?` and is wrapped `.map { [$0] } ?? []`; `movePatch` mirrors Step 1's `applyMove` patch (`sortOrder` `.int`, `parentId` `.string`/`.null`). `rowHeights` keyed by `c.id`. ✓

---

## Out of scope (later / polish)

Live finger-following insertion line (needs a `DropDelegate`/`DragGesture`); showing the Top-level zone only during an active drag; "Move up/Move down" fallback actions; animated row movement beyond default.
