# Category drag-to-reparent (CP2 Step 1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add drag-to-reparent to the category tree — drag a row onto another row to nest it under that row, or onto a "Top level" zone to un-nest it — appended under the destination.

**Architecture:** Three pieces: (1) add `sortOrder` to `FinchCore.updateCategory`'s patch (iOS-only divergence, mirroring `Groups.swift`); (2) a pure, unit-tested `CategoryReorder.reparent` helper that computes the move (destination parent + append index); (3) wire `.draggable`/`.dropDestination` into the existing `CategoryAdminView` rows + a "Top level" drop zone. Reparenting validity (self / under-descendant / depth>3) is enforced by the existing engine guards and surfaced via the existing `errorAlert`. Sibling reorder (between-rows insertion) is CP2 **Step 2**, a separate plan.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14 deployment), FinchCore (GRDB engine + projections), XcodeGen, XCTest. FinchCore tests via `swift test`; FinchApp tests via `xcodebuild … -only-testing:FinchAppTests/…`.

## Global Constraints

- **iOS-only `sortOrder` divergence (documented).** Add `sortOrder` to `FinchCore.updateCategory` **only** — the web's `updateCategory` does not accept it and is not changed. Mark it in code as a deliberate iOS-only divergence (D7-style). Web still loads packs and respects `sort_order`; it just can't create a reorder.
- **No web changes. No new engine reparent logic** — `parentId` + its guards (self / under-descendant / depth≤3) already exist; reuse them.
- **Must build iOS AND macOS (FinchMac).** Avoid macOS-unavailable APIs. `.draggable`/`.dropDestination`/`Transferable` String are available (iOS 16+/macOS 13+; deployment is iOS 17/macOS 14).
- **Reorder (sibling ordering within a parent) is OUT of Step 1.** Step 1 only reparents (append under the destination). Dropping anywhere on a row nests under that row; the middle-vs-gap distinction arrives in Step 2.
- **Append uses position count** (the destination's current child count), which is correct because the engine keeps `sort_order` contiguous (creates use `MAX(sort_order)+1`; Step 2 renumbers contiguously).
- New `.swift` files → run `xcodegen generate` before building. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Sim: `iPhone 17 Pro Max`.
- Conventional-commit messages; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):**
- `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift` — add `sortOrder` to the `cols` map + the `update` patch loop, with the divergence comment.

**Create (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift` — `CategoryMove` + `CategoryReorder.reparent(_:under:in:)`.

**Modify (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` — add `.draggable`/`.dropDestination` to rows, a "Top level" drop zone, drop-highlight state, and `applyMove`.

**Create (tests):**
- `ios/FinchCore/Tests/FinchCoreTests/CategorySortOrderTests.swift`
- `ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift`

**Common run commands:**
```bash
# FinchCore:
cd /Users/blackmount8/_repository/finch/ios && swift test --filter <ClassName>

# FinchApp (regenerate project first if files were added):
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/<ClassName>
```

---

### Task 1: Add `sortOrder` to `FinchCore.updateCategory` (iOS-only)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift` (the `cols` map ~line 27 + the `update` patch loop ~line 44)
- Test: `ios/FinchCore/Tests/FinchCoreTests/CategorySortOrderTests.swift` (create)

**Interfaces:**
- Produces: `updateCategory` now writes `sort_order` when the patch contains `sortOrder` (an integer JSONValue `.int`). Existing patch keys (`name/type/icon/color/parentId`) and the `parentId` guards are unchanged.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/CategorySortOrderTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class CategorySortOrderTests: XCTestCase {
    func test_updateCategory_sets_sort_order_changing_projection_order() throws {
        let q = try TestSeed.base()   // seeds category c1 "Food" sort_order 0
        try Apply.apply(dbQueue: q, action: "createCategory", args: Args([
            "id": .string("cx"), "ledgerId": .string("l1"), "name": .string("Coffee"), "type": .string("expense"),
        ]))   // cx gets sort_order MAX+1 = 1
        XCTAssertEqual(try Projection.categories(dbQueue: q, ledgerId: "l1").map(\.id), ["c1", "cx"])

        // Move cx ahead of c1 by giving it a lower sort_order.
        try Apply.apply(dbQueue: q, action: "updateCategory", args: Args([
            "id": .string("cx"), "patch": .object(["sortOrder": .int(-1)]),
        ]))
        XCTAssertEqual(try Projection.categories(dbQueue: q, ledgerId: "l1").map(\.id), ["cx", "c1"])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter CategorySortOrderTests`
Expected: FAIL — order is still `["c1","cx"]` because `updateCategory` ignores `sortOrder` today.

- [ ] **Step 3: Add `sortOrder` to the `cols` map**

In `Categories.swift`, replace the `cols` line:

```swift
    private static let cols: [String: String] = ["name": "name", "type": "kind", "icon": "icon", "color": "color", "parentId": "parent_id"]
```

with:

```swift
    // NOTE: `sortOrder` is an iOS-only addition — the web's updateCategory patch
    // does NOT accept it (no category reorder on web). Deliberate divergence
    // (cf. the D7 "Force import" iOS-only override). Web still respects sort_order.
    private static let cols: [String: String] = ["name": "name", "type": "kind", "icon": "icon", "color": "color", "parentId": "parent_id", "sortOrder": "sort_order"]
```

- [ ] **Step 4: Add `sortOrder` to the `update` patch loop**

In `Categories.swift` `update(_:_:)`, change the loop key list:

```swift
        for key in ["name", "type", "icon", "color", "parentId"] where patch.keys.contains(key) {
```

to:

```swift
        for key in ["name", "type", "icon", "color", "parentId", "sortOrder"] where patch.keys.contains(key) {
```

(The loop already does `sets.append("\(cols[key]!) = ?"); bind.append(patch[key]!.sqlBind)`, and `JSONValue.sqlBind` maps `.int` → integer, so no other change is needed.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter CategorySortOrderTests`
Expected: PASS.

- [ ] **Step 6: Run the full FinchCore suite (no regressions)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift \
        ios/FinchCore/Tests/FinchCoreTests/CategorySortOrderTests.swift
git commit -m "feat(ios): updateCategory accepts sortOrder (iOS-only divergence)"
```

---

### Task 2: `CategoryReorder.reparent` helper (pure)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift` (create)

**Interfaces:**
- Produces:
  - `struct CategoryMove: Equatable { let id: String; let parentId: String?; let sortOrder: Int }`
  - `enum CategoryReorder { static func reparent(_ sourceId: String, under destParentId: String?, in rows: [CategoryRow]) -> CategoryMove? }` — returns the move that nests `sourceId` under `destParentId` (nil = top level), appended after the destination's current children (`sortOrder` = count of destination children excluding the source). Returns `nil` for a no-op: dropping a row onto itself (`destParentId == sourceId`).
- Consumes: `CategoryRow` (has `id`, `parentId`).

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift`:

```swift
import XCTest
import FinchCore
@testable import FinchApp

final class CategoryReorderTests: XCTestCase {
    private func cat(_ id: String, parent: String? = nil) -> CategoryRow {
        CategoryRow(id: id, ledgerId: "l1", name: id, parentId: parent, kind: "expense")
    }

    func test_reparent_appends_after_destinations_existing_children() {
        let rows = [cat("food"), cat("g1", parent: "food"), cat("home")]
        // move "home" under "food": food already has [g1] (1 child) → append at index 1
        XCTAssertEqual(CategoryReorder.reparent("home", under: "food", in: rows),
                       CategoryMove(id: "home", parentId: "food", sortOrder: 1))
    }

    func test_reparent_to_empty_parent_appends_at_zero() {
        let rows = [cat("food"), cat("home")]
        XCTAssertEqual(CategoryReorder.reparent("home", under: "food", in: rows),
                       CategoryMove(id: "home", parentId: "food", sortOrder: 0))
    }

    func test_reparent_to_top_level() {
        let rows = [cat("food"), cat("g1", parent: "food"), cat("g2", parent: "food")]
        // top level currently has [food] (1) → moving g1 to top appends at index 1
        XCTAssertEqual(CategoryReorder.reparent("g1", under: nil, in: rows),
                       CategoryMove(id: "g1", parentId: nil, sortOrder: 1))
    }

    func test_reparent_excludes_source_from_count() {
        // moving g1 under food when g1 is already a child of food: other children = [g2] → index 1
        let rows = [cat("food"), cat("g1", parent: "food"), cat("g2", parent: "food")]
        XCTAssertEqual(CategoryReorder.reparent("g1", under: "food", in: rows),
                       CategoryMove(id: "g1", parentId: "food", sortOrder: 1))
    }

    func test_reparent_onto_self_is_noop() {
        XCTAssertNil(CategoryReorder.reparent("food", under: "food", in: [cat("food")]))
    }
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
Expected: FAIL to compile — `CategoryReorder`/`CategoryMove` undefined.

- [ ] **Step 3: Write the implementation**

Create `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift`:

```swift
import Foundation
import FinchCore

/// A single category move: set `id`'s parent + sort_order. Applied via
/// `updateCategory` (parentId + sortOrder patch).
struct CategoryMove: Equatable {
    let id: String
    let parentId: String?
    let sortOrder: Int
}

/// Pure drop math for the category tree. CP2 Step 1 = reparent (append under the
/// destination). `rows` is the projection's sort_order-ordered list, so the
/// destination's children appear in order and the append index is their count.
enum CategoryReorder {
    /// Nest `sourceId` under `destParentId` (nil = top level), appended after the
    /// destination's current children. Returns nil for a no-op (dropping onto
    /// itself). Cycle / depth validity is enforced downstream by the engine.
    static func reparent(_ sourceId: String, under destParentId: String?, in rows: [CategoryRow]) -> CategoryMove? {
        if let dest = destParentId, dest == sourceId { return nil }   // onto itself
        let siblingCount = rows.filter { $0.parentId == destParentId && $0.id != sourceId }.count
        return CategoryMove(id: sourceId, parentId: destParentId, sortOrder: siblingCount)
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
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryReorder.swift \
        ios/FinchApp/Tests/FinchAppTests/CategoryReorderTests.swift
git commit -m "feat(ios): CategoryReorder.reparent move helper (append under destination)"
```

---

### Task 3: Wire drag-to-reparent into `CategoryAdminView`

**Files:**
- Modify (full rewrite): `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift`

**Interfaces:**
- Consumes: `CategoryReorder.reparent` + `CategoryMove` (Task 2); `updateCategory` with `sortOrder` (Task 1); existing `CategoryForest` helpers + `CategoryEditSheet` (CP1, unchanged below).
- Produces: drag-to-reparent UX. No new public symbols.

- [ ] **Step 1: Replace the view file**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` with (CP1 view + drag additions: a Top-level drop zone, `.draggable`/`.dropDestination` per row, drop highlights, and `applyMove`):

```swift
import SwiftUI
import FinchCore

/// Categories admin — a 3-level tree (inline expand/collapse) with per-category
/// icon + color, search, create-child, edit, delete (children promote up a
/// level), and **drag-to-reparent** (drop a row onto another to nest it; onto
/// "Top level" to un-nest). create / update / deleteCategory through the
/// chokepoint. Sibling reorder (between-rows) is CP2 Step 2.
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
            applyMove(m); return true
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
        .draggable(c.id)
        .dropDestination(for: String.self) { items, _ in
            guard let src = items.first, let m = CategoryReorder.reparent(src, under: c.id, in: rows) else { return false }
            applyMove(m); return true
        } isTargeted: { isTargeted in
            if isTargeted { dropTargetId = c.id }
            else if dropTargetId == c.id { dropTargetId = nil }
        }
        .listRowBackground(dropTargetId == c.id ? Color.accentColor.opacity(0.15) : nil)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Apply a reparent move (parentId + sortOrder) through the chokepoint; the
    /// engine rejects self/descendant/depth>3 with a localized error.
    private func applyMove(_ m: CategoryMove) {
        errorMessage = nil
        var patch: [String: JSONValue] = ["sortOrder": .int(m.sortOrder)]
        patch["parentId"] = m.parentId.map(JSONValue.string) ?? .null
        do { try store.apply(.updateCategory, Args(["id": .string(m.id), "patch": .object(patch)])) }
        catch { errorMessage = i18nMessage(error) }
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
Expected: `** TEST SUCCEEDED **` (CategoryReorderTests + all prior FinchAppTests).

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

To exercise nesting you need at least two top-level categories. Build/install/launch to Categories, create a second top-level category if the seed has only one, then:
- **Nest:** long-press a row and drag it **onto another row** → drop; the target row highlights while targeted; on release the dragged category becomes a child of the target (appears indented under it; expand the target to confirm).
- **Un-nest:** drag a child onto the **"Top level"** zone at the top → it returns to the top level.
- **Invalid drop:** drag a parent onto its **own descendant**, or nest deep enough to exceed 3 levels → the move is rejected and the engine's error appears in the alert (no change persists).
- **Persistence:** relaunch — the new parent/order persists.
- Confirm CP1 flows still work (tap to edit, "+" create-child, search, swipe-delete).

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
git commit -m "feat(ios): drag-to-reparent categories (drop onto row / Top level)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-23-ios-category-reparent-cp2-design.md`, Step 1):
- iOS-only `sortOrder` in `updateCategory` (+ divergence comment) → Task 1. ✓
- Pure reorder math (`.into` / top-level append) → Task 2 (`CategoryReorder.reparent`). ✓
- Drag UI: `.draggable`/`.dropDestination` nest + Top-level zone + highlight + engine-error surfacing → Task 3. ✓
- Reparent appends under destination (Step-1 "drop anywhere on a row → nest") → Tasks 2 + 3. ✓
- Build iOS + macOS, full FinchAppTests green → Task 3 steps 2-3. ✓
- Sibling reorder (between-rows) → intentionally **Step 2**, not here. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code; the sim step lists concrete checks. ✓

**Type consistency:** `CategoryMove(id:parentId:sortOrder:)` (Task 2) matches `applyMove` (Task 3). `CategoryReorder.reparent(_:under:in:)` signature matches both call sites in Task 3. `.int(m.sortOrder)` matches the `JSONValue.sqlBind` `.int` path enabled in Task 1. `JSONValue.string`/`.null` used for `parentId` match the engine's `parentId` handling (`.string` runs guards, `.null` writes NULL). ✓

---

## Out of scope (Step 2 / later)

Sibling reorder via between-rows insertion (drop-position thirds + insertion line + renumber); showing the Top-level zone only during an active drag; drag preview customization; the "Move up/down" reorder fallback.
