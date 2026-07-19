# Categories Page Redesign — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Categories admin page out of Power Tools to a Settings top-level row and upgrade it — expense/income segmented split, a polished create/edit sheet, a dedicated reorder mode, a clear delete-impact warning, and expand/collapse-all — all as FinchApp UI, no engine/schema/web change.

**Architecture:** Rework the single file `PowerTools/CategoryAdminView.swift` (renamed to `CategoriesView.swift`) in layered tasks: a pure warning-string helper first (unit-tested), then the Settings move, then the expense/income split + sheet rework, then browse-vs-reorder mode gating, then the delete-impact wiring. Every category write continues to flow through the existing `createCategory` / `updateCategory` / `deleteCategory` chokepoints; the drag math continues to use the existing pure `CategoryReorder`.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 deployment floor, running on iOS 26), FinchCore (SwiftPM engine), XCTest, XcodeGen (`project.yml` → `FinchApp.xcodeproj`), Bun-less native build via `xcodebuild`.

## Global Constraints

- **Worktree / branch:** all work happens in `/tmp/finch-cat` on branch `feat/ios-categories-page` (already created off `origin/feat/frontend`). PR targets `feat/frontend`.
- **Environment:** every `xcodebuild` invocation must first `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Regenerate the project after adding or renaming any Swift file:** `cd /tmp/finch-cat/ios && xcodegen generate` (the `.xcodeproj` is git-ignored and generated on demand; sources are path-globbed so no `project.yml` edit is needed for a same-folder add/rename).
- **Simulator for builds/tests:** `platform=iOS Simulator,name=ios-finch2`. Use a dedicated `-derivedDataPath` (e.g. `/tmp/dd-cat`) so a sibling worktree's identically-named DerivedData can't be picked up.
- **Commits:** no `Co-Authored-By` trailer. Conventional-commit `feat(ios): …` subjects.
- **No engine / schema / web changes.** Writes stay on `createCategory`, `updateCategory` (also used for reparent/reorder via a `parentId`+`sortOrder` patch), and `deleteCategory`. Do not touch `ios/FinchCore` or `frontend/`.
- **Color palette:** category color swatches use **`CategoryPalette.hexes`** and the effective-color default **`CategoryPalette.defaultHex`** (`#00a0c5`). The design doc's mention of `TagPalette.hexes` is a typo — do NOT switch categories to `TagPalette` (it belongs to Tags and would break parity with the `effectiveColor` fallback).
- **Kind values:** `CategoryRow.kind` is `String?` with values `"expense"` / `"income"`; a `nil` kind is treated as `"expense"` everywhere. Default tab is Expense.
- **Copy strings (use verbatim; en source == key, zh-Hans translated separately later):**
  - `"Categories"`, `"Expense"`, `"Income"`, `"Add category"`, `"Add subcategory under \(name)"` (existing).
  - New: `"Reorder"`, `"Expand all"`, `"Collapse all"`, `"Done"`, `"Edit"`, `"Delete"`, `"No expense categories yet"`, `"No income categories yet"`, `"Tap + to add one."`, `"\(count) transactions will become uncategorized"` (catalog key `%lld transactions will become uncategorized`), `"\(count) subcategories move to top level"` (catalog key `%lld subcategories move to top level`).
  - No plural variants — the flat strings above are intentional (they match the tracked zh-Hans batch).

---

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryDeleteImpact.swift` | 1 (create) | Pure `deleteImpactMessage(txCount:subcatCount:)` warning-string builder |
| `ios/FinchApp/Tests/FinchAppTests/CategoryDeleteImpactTests.swift` | 1 (create) | Unit tests for the helper |
| `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` → `.../CategoriesView.swift` | 2 (rename), 3–5 (edit) | The Categories page + `CategoryEditSheet` |
| `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift` | 2 (edit) | Add Categories root row; remove it from Power Tools |

Unchanged but consumed: `CategoryForest.swift` (`categoryForest`, `flattenCategories`, `FlatCategory`, `effectiveColor`, `effectiveIcon`), `CategoryReorder.swift` (`CategoryReorder.reparent`/`.reorder`, `CategoryMove`, `InsertPosition`), `Common/Icons.swift` (`CategoryIcon`), `Common/Color+Hex.swift` (`CategoryPalette`), `Selectors.categoryTxCounts`.

---

### Task 1: `deleteImpactMessage` pure helper

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryDeleteImpact.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/CategoryDeleteImpactTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `func deleteImpactMessage(txCount: Int, subcatCount: Int) -> String?` — returns `nil` when both counts are 0; otherwise the non-zero clauses joined with `" · "`. Task 5 calls this from the delete `.alert`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/CategoryDeleteImpactTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class CategoryDeleteImpactTests: XCTestCase {
    func test_leaf_with_no_transactions_returns_nil() {
        XCTAssertNil(deleteImpactMessage(txCount: 0, subcatCount: 0))
    }

    func test_transactions_only() {
        XCTAssertEqual(deleteImpactMessage(txCount: 5, subcatCount: 0),
                       "5 transactions will become uncategorized")
    }

    func test_subcategories_only() {
        XCTAssertEqual(deleteImpactMessage(txCount: 0, subcatCount: 3),
                       "3 subcategories move to top level")
    }

    func test_both_clauses_joined_with_middot() {
        XCTAssertEqual(deleteImpactMessage(txCount: 2, subcatCount: 1),
                       "2 transactions will become uncategorized · 1 subcategories move to top level")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryDeleteImpactTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — compile error `cannot find 'deleteImpactMessage' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryDeleteImpact.swift`:

```swift
import Foundation

/// Human-readable impact line for deleting a category, or `nil` when there is
/// nothing to warn about (a leaf with no transactions deletes silently).
///
/// - `txCount`: the category's OWN direct transactions — they become
///   uncategorized. Its subcategories keep their own transactions.
/// - `subcatCount`: the category's direct children — they move to top level.
///
/// Clauses join with " · "; each is omitted when its count is 0. Strings are
/// intentionally non-pluralized to match the shared copy / zh-Hans batch.
func deleteImpactMessage(txCount: Int, subcatCount: Int) -> String? {
    var clauses: [String] = []
    if txCount > 0 {
        clauses.append(String(localized: "\(txCount) transactions will become uncategorized"))
    }
    if subcatCount > 0 {
        clauses.append(String(localized: "\(subcatCount) subcategories move to top level"))
    }
    return clauses.isEmpty ? nil : clauses.joined(separator: " · ")
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryDeleteImpactTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (4 tests). The `String(localized:)` calls resolve against the en source (key == value), so the interpolated integers appear literally.

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-cat && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryDeleteImpact.swift ios/FinchApp/Tests/FinchAppTests/CategoryDeleteImpactTests.swift && git commit -m "feat(ios): deleteImpactMessage helper for category deletes"
```

---

### Task 2: Move Categories to Settings top-level (rename + wire)

Rename the file and struct from `CategoryAdminView` to `CategoriesView`, add a Categories row to the Settings root list (right after Currencies), and remove the Categories link from Power Tools. **No behavior change** beyond the page's location and name — the page still has always-on drag, the single `+` toolbar, etc.

**Files:**
- Rename: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` → `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`
- Modify: the renamed file (struct name), and `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift:37` and `:135`

**Interfaces:**
- Consumes: nothing new.
- Produces: `struct CategoriesView: View` (replaces `struct CategoryAdminView`). `SettingsRootList` and `SettingsPowerToolsView` reference it.

- [ ] **Step 1: Rename the file (git mv)**

```bash
cd /tmp/finch-cat && git mv ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift
```

- [ ] **Step 2: Rename the struct**

In `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`, change the declaration (currently line 10):

```swift
struct CategoryAdminView: View {
```

to:

```swift
struct CategoriesView: View {
```

(Leave every other line in the file unchanged in this task.)

- [ ] **Step 3: Add the Settings root row**

In `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`, inside `SettingsRootList`'s first `Section`, immediately after the Currencies row (line 37), insert:

```swift
                NavigationLink { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }
```

So the block reads:

```swift
                NavigationLink { CurrenciesView() } label: { Label("Currencies", systemImage: "dollarsign.circle") }
                NavigationLink { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }
                NavigationLink { SettingsNotificationsView() } label: { Label("Notifications", systemImage: "bell") }
```

- [ ] **Step 4: Remove the Power Tools link**

In `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`, in `SettingsPowerToolsView` (line 135), delete this line:

```swift
            NavigationLink("Categories") { CategoryAdminView() }
```

So `SettingsPowerToolsView`'s `List` becomes:

```swift
        List {
            NavigationLink("Rules") { RulesManagerView() }
            NavigationLink("Tags") { TagAdminView() }
            NavigationLink("Merchants") { CounterpartyAdminView() }
        }
```

- [ ] **Step 5: Build FinchApp**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. (If it fails with `cannot find 'CategoryAdminView'`, a reference to the old name was missed — grep `git grep -n CategoryAdminView` should return nothing.)

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-cat && git add -A ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift ios/FinchApp/Tabs 2>/dev/null; git add -A ios/FinchApp && git commit -m "feat(ios): move Categories to Settings top-level (rename CategoryAdminView→CategoriesView)"
```

---

### Task 3: Expense/Income split + polished edit sheet

Add a segmented Expense/Income control that filters the tree by kind, a per-kind empty state, and rework `CategoryEditSheet` so create inherits the current tab's kind (no Kind picker) and kind is fixed on edit. Drag stays always-on in this task (reorder-mode gating is Task 4).

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`

**Interfaces:**
- Consumes: `store.pickableCategories: [CategoryRow]`, `categoryForest`, `flattenCategories`, `CategoryPalette.hexes`, `CategoryIcon.names`/`.symbol(for:)`, `store.apply(.createCategory/.updateCategory, Args)`.
- Produces (used by Tasks 4–5): `private enum CategoryKind` with `@State private var kind: CategoryKind`; `private var rows` filtered to the current kind; `CategoryEditSheet` initializers `init(category:)`, `init(parent:)`, `init(kind:)`.

- [ ] **Step 1: Add the kind enum + state, and filter `rows` by kind**

At the top of `CategoriesView.swift`, above `struct CategoriesView`, add the enum:

```swift
/// Expense/income filter for the Categories page (maps to `CategoryRow.kind`).
private enum CategoryKind: String, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .expense ? "Expense" : "Income" }
}
```

Add the `kind` state to `CategoriesView` (right after `@EnvironmentObject private var store`):

```swift
    @State private var kind: CategoryKind = .expense
```

Change the `rows` computed property to filter by kind (`nil` kind → expense):

```swift
    private var rows: [CategoryRow] {
        store.pickableCategories.filter { ($0.kind ?? "expense") == kind.rawValue }
    }
```

- [ ] **Step 2: Add the pinned segmented picker + per-kind empty state**

Replace the `body`'s `List { … }` and its `.modifier(SearchableModifier…)` region. The current body opens:

```swift
        return List {
            topLevelDropZone
            ForEach(visible) { item in row(item, counts) }
        }
        .modifier(SearchableModifier(text: $search))
```

Change it to:

```swift
        return List {
            topLevelDropZone
            if rows.isEmpty {
                ContentUnavailableView(
                    kind == .expense ? "No expense categories yet" : "No income categories yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Tap + to add one."))
            } else {
                ForEach(visible) { item in row(item, counts) }
            }
        }
        .safeAreaInset(edge: .top) { kindPicker }
        .modifier(SearchableModifier(text: $search))
```

Add the `kindPicker` view as a new computed property on `CategoriesView` (e.g. right before `topLevelDropZone`):

```swift
    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            ForEach(CategoryKind.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
```

- [ ] **Step 3: Point the create sheets at the current kind / parent**

In `body`, change the three `.sheet` modifiers. Currently:

```swift
        .sheet(isPresented: $creatingTop) { CategoryEditSheet(category: nil) }
        .sheet(item: $creatingUnder) { parent in CategoryEditSheet(category: nil, parent: parent) }
        .sheet(item: $editing) { CategoryEditSheet(category: $0) }
```

Change to:

```swift
        .sheet(isPresented: $creatingTop) { CategoryEditSheet(kind: kind.rawValue) }
        .sheet(item: $creatingUnder) { parent in CategoryEditSheet(parent: parent) }
        .sheet(item: $editing) { CategoryEditSheet(category: $0) }
```

- [ ] **Step 4: Rework `CategoryEditSheet` — three initializers, no Kind picker, footer prompt**

Replace the entire `CategoryEditSheet` struct (from `struct CategoryEditSheet: View {` through its closing brace, currently lines 182–283) with:

```swift
/// Create a top-level category (`init(kind:)`), create under a parent
/// (`init(parent:)`), or edit an existing one (`init(category:)`). Name + icon +
/// color are always editable; kind is fixed (current tab on create, parent's kind
/// for a subcategory, the row's own kind on edit) so a category with transactions
/// never crosses expense↔income.
struct CategoryEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let category: CategoryRow?
    let parent: CategoryRow?
    let createKind: String?     // set only for a top-level create
    @State private var name: String
    @State private var icon: String     // "" = none (inherit at render)
    @State private var color: String    // "" = none (inherit/default at render)
    @State private var errorMessage: String?

    init(category: CategoryRow) {
        self.category = category; self.parent = nil; self.createKind = nil
        _name = State(initialValue: category.name)
        _icon = State(initialValue: category.icon ?? "")
        _color = State(initialValue: category.color ?? "")
    }
    init(parent: CategoryRow) {
        self.category = nil; self.parent = parent; self.createKind = nil
        _name = State(initialValue: ""); _icon = State(initialValue: ""); _color = State(initialValue: "")
    }
    init(kind: String) {
        self.category = nil; self.parent = nil; self.createKind = kind
        _name = State(initialValue: ""); _icon = State(initialValue: ""); _color = State(initialValue: "")
    }

    /// Fixed kind for the save: existing row → parent → create tab → expense.
    private var resolvedKind: String { category?.kind ?? parent?.kind ?? createKind ?? "expense" }

    private let iconColumns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
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
                    Text("Icon and color are inherited from the parent category when left unset.")
                }
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
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                    "type": .string(resolvedKind),
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
```

- [ ] **Step 5: Build FinchApp**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the existing Category unit tests (regression)**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryReorderTests -only-testing:FinchAppTests/CategoryForestTests -only-testing:FinchAppTests/CategoryDeleteImpactTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /tmp/finch-cat && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift && git commit -m "feat(ios): split Categories by expense/income + polished edit sheet"
```

---

### Task 4: Browse vs Reorder mode + expand/collapse menu

Gate the drag affordances behind an explicit reorder mode. In browse mode the toolbar shows `+` and a `⋯` menu (Reorder / Expand all / Collapse all), rows offer tap-to-edit + swipe (Delete/Edit) + context menu, and dragging is off. In reorder mode the toolbar collapses to a single ✓ Done, the "Top level" drop zone appears, and rows become draggable.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`

**Interfaces:**
- Consumes: `kind`/`rows` (Task 3), `CategoryReorder`, `applyMoves`, `rowHeights`, `dropTargetId`, `topLevelTargeted`.
- Produces: `@State private var isReordering`; `toolbarContent`; `expandAll()`; `rowContent(_:_:)` (shared row visual) + a mode-split `row(_:_:)`.

- [ ] **Step 1: Add the `isReordering` state**

In `CategoriesView`, after the `kind` state, add:

```swift
    @State private var isReordering = false
```

- [ ] **Step 2: Show the top-level drop zone only while reordering**

In `body`, change the first line inside `List { … }` from:

```swift
            topLevelDropZone
```

to:

```swift
            if isReordering { topLevelDropZone }
```

- [ ] **Step 3: Replace the toolbar**

In `body`, replace the current `.toolbar { … }` block (the single `+` primary action, currently lines 38–43) with:

```swift
        .toolbar { toolbarContent }
```

Add the `toolbarContent` and `expandAll()` members to `CategoriesView` (e.g. right after `kindPicker`):

```swift
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if isReordering {
            ToolbarItem(placement: .confirmationAction) {
                Button { isReordering = false } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Done")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingTop = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add category")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isReordering = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                    Button { expandAll() } label: { Label("Expand all", systemImage: "chevron.down") }
                    Button { expanded = [] } label: { Label("Collapse all", systemImage: "chevron.right") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More")
            }
        }
    }

    /// Expand every category that has children (in the current kind).
    private func expandAll() {
        expanded = Set(rows.filter { r in rows.contains { $0.parentId == r.id } }.map(\.id))
    }
```

- [ ] **Step 4: Split the row into shared content + mode-specific modifiers**

Replace the entire `row(_:_:)` method (currently lines 74–153, from `@ViewBuilder private func row(` through its closing brace) with the shared-content function plus a mode-split wrapper:

```swift
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
                    // Not role: .destructive — see ActivityTab (fake removal
                    // animation kills the row-anchored popout).
                    Button { deleting = c } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                    Button { editing = c } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
                }
                .contextMenu {
                    Button { editing = c } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    /// The shared row visual (chevron, icon+color swatch, name, count badge,
    /// inline add-subcategory). Mode-specific modifiers are applied by `row`.
    @ViewBuilder private func rowContent(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
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
    }
```

- [ ] **Step 5: Build FinchApp**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-cat && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift && git commit -m "feat(ios): Categories reorder mode + expand/collapse menu"
```

---

### Task 5: Delete-impact warning

Wire the `deleteImpactMessage` helper (Task 1) into the delete `.alert` so it spells out the consequences, and add a FinchMac build as the final cross-platform check.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`

**Interfaces:**
- Consumes: `deleteImpactMessage(txCount:subcatCount:)` (Task 1), `counts` (computed in `body`), `rows` (Task 3).
- Produces: nothing downstream.

- [ ] **Step 1: Replace the delete alert's message closure**

In `body`, the delete `.alert` currently ends with a fixed message:

```swift
        .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting) { c in
            Button("Delete", role: .destructive) { delete(c) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its subcategories move up a level — they won't be deleted.")
        }
```

Replace the `message:` closure so it derives the impact from the direct transaction count and the direct-child count (omitting the message entirely when both are 0):

```swift
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
```

- [ ] **Step 2: Build FinchApp**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Build FinchMac (cross-platform check)**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-catmac CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full Category test set**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryReorderTests -only-testing:FinchAppTests/CategoryForestTests -only-testing:FinchAppTests/CategoryDeleteImpactTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-cat && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift && git commit -m "feat(ios): category delete impact warning"
```

---

## Manual sim verification (controller / human, after Task 5)

Build, install to `ios-finch2`, and confirm:
1. Settings root shows **Categories** (after Currencies); **Power Tools** no longer lists Categories.
2. The Expense/Income segmented control switches the tree; each kind shows only its own categories.
3. Empty a kind (or a fresh ledger) → the per-kind empty state ("No expense/income categories yet · Tap + to add one.").
4. `+` opens the full-height sheet and creates a top-level category **in the current kind** (no Kind picker); the inline `+` creates a subcategory under a row.
5. `⋯` → **Reorder** enters drag mode (single ✓ Done, "Top level" zone visible); drag to nest / reorder / un-nest; ✓ exits. `⋯` → **Expand all** / **Collapse all** work.
6. Swipe a row → **Delete** shows the centered alert; a category with transactions and/or subcategories shows the impact line; a bare leaf shows a title-only "Delete <name>?".

## Out of scope (Phase 1)

Merge categories (Phase 2), archive/hide (Phase 3), spending-per-category figures, web changes, engine/schema changes, and the zh-Hans translation pass (new keys are tracked and translated in the accumulated batch).

## Self-Review

**Spec coverage** — every design decision maps to a task:
- D1 Move out of Power Tools → Settings top-level (rename): **Task 2**.
- D2 Expense/Income split (segmented, per-kind tree/search/empty): **Task 3**.
- D3 Polished create/edit sheet, kind inherited on create, fixed on edit: **Task 3**.
- D4 Reorder editor via ⋯, single ✓, drag only in this mode: **Task 4**.
- D5 Delete polish with impact message (N direct txns + M subcats, clauses omitted at 0): **Task 1** (helper) + **Task 5** (wiring).
- D6 Cleaner browsing — empty state (**Task 3**), Expand/Collapse all (**Task 4**), `.searchable` (retained through all tasks).

**Placeholder scan:** none — every code step contains complete code and exact commands.

**Type consistency:** `deleteImpactMessage(txCount:subcatCount:) -> String?` defined in Task 1, consumed in Task 5 with the same labels. `CategoryEditSheet` initializers `init(category:)`/`init(parent:)`/`init(kind:)` defined in Task 3 and matched by the three call sites in Task 3 Step 3. `CategoryKind`/`kind`/`rows`/`isReordering` names are consistent across Tasks 3–5. `CategoryReorder.reorder`/`.reparent`, `CategoryMove`, `InsertPosition.before/.after`, `applyMoves`, `movePatch`, `effectiveColor`/`effectiveIcon`, `byId` are used exactly as they exist in the current file.
