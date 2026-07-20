# Budget Sheet Pickers + Top Type Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Add/Edit Budget sheet's long inline category/account checklists with transaction-style bottom-sheet pickers (category = hierarchy-tree multi-select, account = flat multi-select), and move the Expense|Income control to the top toolbar.

**Architecture:** A flat `MultiSelectPickerRow` (sibling of `SearchablePickerRow`) for accounts; a `CategoryMultiPickerRow`/`Sheet` reusing a shared `CategoryTreeRow` extracted from the existing single-select `CategoryPickerSheet` for categories; then `BudgetSheet` swaps its two inline sections for two rows and moves its type picker to `.principal`. Selection state and `save()` are untouched.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 floor); FinchCore (`CategoryRow`); XCTest; XcodeGen; `xcodebuild`.

## Global Constraints

- **Worktree / branch:** `/tmp/finch-budsheet` on `feat/ios-budget-sheet-pickers` (off `origin/feat/frontend`). PR targets `feat/frontend`.
- **Environment:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`xcodegen`; run `xcodegen generate` (from `/tmp/finch-budsheet/ios`) after adding any new file. Sim `ios-finch2`; iOS `-derivedDataPath /tmp/dd-buds`, mac `-derivedDataPath /tmp/dd-budsmac CODE_SIGNING_ALLOWED=NO`.
- **Commits:** no `Co-Authored-By` trailer. `feat(ios): …` subjects.
- **No engine/schema/web change** — FinchApp only. `BudgetSheet.save()` and `selectedCategories`/`selectedAccounts` (`Set<String>`) are UNCHANGED.
- **Reuse, don't redefine:** `PickerOption` (id, name) already exists in `WriteScreens/SearchablePickerRow.swift` — reuse it. `TxnKindIcon.icon(for:)`, `effectiveColor(_,_)`, `effectiveIcon(_,_)`, `CategoryIcon.symbol(for:)`, `categoryForest(_)`, `flattenCategories(_,expanded:,search:)`, `FlatCategory{row,depth,hasChildren}` all exist and are in scope from `WriteScreens/`.
- **SwiftUI-first** (no UIKit). Stage-then-Confirm on every picker sheet (Cancel discards).

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchApp/Sources/FinchApp/WriteScreens/MultiSelectPickerRow.swift` | 1 (create) | `multiSelectSummary` + flat multi-select row/sheet (accounts) |
| `ios/FinchApp/Tests/FinchAppTests/MultiSelectSummaryTests.swift` | 1 (create) | `multiSelectSummary` unit tests |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryPickerRow.swift` | 2 (modify) | extract shared `CategoryTreeRow`; refactor single-select sheet to use it |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryMultiPickerRow.swift` | 3 (create) | tree multi-select row/sheet (categories) |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift` | 3 (modify) | type→toolbar `.principal`; two inline sections → two picker rows |

---

### Task 1: `multiSelectSummary` + flat `MultiSelectPickerRow` (accounts)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/MultiSelectPickerRow.swift`
- Create: `ios/FinchApp/Tests/FinchAppTests/MultiSelectSummaryTests.swift`

**Interfaces:**
- Consumes: `PickerOption` (from `SearchablePickerRow.swift`).
- Produces: `func multiSelectSummary(names: [String], emptyLabel: String) -> String`; `struct MultiSelectPickerRow(title: String, options: [PickerOption], selection: Binding<Set<String>>, emptyLabel: String)`. Task 3 uses both.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/MultiSelectSummaryTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class MultiSelectSummaryTests: XCTestCase {
    func test_empty_uses_label() {
        XCTAssertEqual(multiSelectSummary(names: [], emptyLabel: "All accounts"), "All accounts")
    }
    func test_one_name() {
        XCTAssertEqual(multiSelectSummary(names: ["Checking"], emptyLabel: "All accounts"), "Checking")
    }
    func test_several_joined() {
        XCTAssertEqual(multiSelectSummary(names: ["Groceries", "Dining"], emptyLabel: "All categories"), "Groceries, Dining")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /tmp/finch-budsheet/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/MultiSelectSummaryTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL — `cannot find 'multiSelectSummary' in scope`.

- [ ] **Step 3: Implement the row + helper**

Create `ios/FinchApp/Sources/FinchApp/WriteScreens/MultiSelectPickerRow.swift`:

```swift
import SwiftUI

/// A multi-select picker row's value: the selected names joined, or `emptyLabel`
/// when nothing is selected (e.g. "All accounts"). Mirrors `splitSummaryText`.
func multiSelectSummary(names: [String], emptyLabel: String) -> String {
    names.isEmpty ? emptyLabel : names.joined(separator: ", ")
}

/// A form row that shows a multi-selection summary and opens a full-height BOTTOM
/// SHEET with a searchable multi-select list — the multi-select sibling of
/// `SearchablePickerRow` (reuses its `PickerOption`). The sheet STAGES a set and
/// commits it on Confirm; Cancel discards.
struct MultiSelectPickerRow: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: Set<String>
    let emptyLabel: String
    @State private var presented = false

    private var summary: String {
        multiSelectSummary(names: options.filter { selection.contains($0.id) }.map(\.name), emptyLabel: emptyLabel)
    }

    var body: some View {
        Button { presented = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Text(summary).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1).truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            MultiSelectPickerSheet(title: title, options: options, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: searchable, multi-select. Tapping toggles a staged id; Confirm
/// applies the staged set to the binding; Cancel discards.
private struct MultiSelectPickerSheet: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: Set<String>

    init(title: String, options: [PickerOption], selection: Binding<Set<String>>) {
        self.title = title
        self.options = options
        self._selection = selection
        self._staged = State(initialValue: selection.wrappedValue)
    }

    private var filtered: [PickerOption] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { opt in
                Button {
                    if staged.contains(opt.id) { staged.remove(opt.id) } else { staged.insert(opt.id) }
                } label: {
                    HStack {
                        Text(opt.name)
                        Spacer()
                        if staged.contains(opt.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { selection = staged; dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Confirm").confirmCheckmarkStyle()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /tmp/finch-budsheet/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/MultiSelectSummaryTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-budsheet && git add ios/FinchApp/Sources/FinchApp/WriteScreens/MultiSelectPickerRow.swift ios/FinchApp/Tests/FinchAppTests/MultiSelectSummaryTests.swift && git commit -m "feat(ios): MultiSelectPickerRow (flat multi-select bottom sheet) + summary helper"
```

---

### Task 2: Extract shared `CategoryTreeRow`; refactor the single-select sheet

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryPickerRow.swift` (replace `CategoryPickerSheet.row(_:)`, currently lines 117–152, and add `CategoryTreeRow`)

**Interfaces:**
- Consumes: `FlatCategory` (`.row: CategoryRow`, `.depth: Int`, `.hasChildren: Bool`), `effectiveColor(_,_)`, `effectiveIcon(_,_)`, `CategoryIcon.symbol(for:)`, `Color(hex:)`.
- Produces: `struct CategoryTreeRow(item: FlatCategory, byId: [String: CategoryRow], isSelected: Bool, expanded: Bool, searchActive: Bool, onTap: () -> Void, onToggleExpand: () -> Void)`. Task 3 uses it.

- [ ] **Step 1: Add `CategoryTreeRow`**

In `CategoryPickerRow.swift`, add this struct (e.g. after `CategoryPickerSheet`):

```swift
/// One category-tree row shared by the single- and multi-select picker sheets:
/// swatch + icon + indented name + a trailing selection checkmark + an
/// expand/collapse chevron for parents. Selection + expand state are caller-driven.
struct CategoryTreeRow: View {
    let item: FlatCategory
    let byId: [String: CategoryRow]
    let isSelected: Bool
    let expanded: Bool
    let searchActive: Bool
    let onTap: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        let c = item.row
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 26, height: 26)
                        Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                            .font(.system(size: 12)).foregroundStyle(.white)
                    }
                    Text(c.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: (expanded || searchActive) ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 22, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(searchActive)   // search force-expands; chevron is inert
            } else {
                // Reserve the chevron slot so checkmarks/edges line up across rows.
                Color.clear.frame(width: 22, height: 30)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 14)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Refactor `CategoryPickerSheet.row(_:)` to use it**

Replace the entire existing `row(_:)` method (from `@ViewBuilder private func row(_ item: FlatCategory) -> some View {` through its closing brace, currently lines 117–152) with:

```swift
    @ViewBuilder private func row(_ item: FlatCategory) -> some View {
        CategoryTreeRow(
            item: item, byId: byId,
            isSelected: item.row.id == staged,
            expanded: expanded.contains(item.row.id),
            searchActive: !query.isEmpty,
            onTap: { staged = item.row.id },
            onToggleExpand: {
                if expanded.contains(item.row.id) { expanded.remove(item.row.id) } else { expanded.insert(item.row.id) }
            }
        )
    }
```

- [ ] **Step 3: Build FinchApp + FinchMac (behavior-preserving refactor)**

```bash
cd /tmp/finch-budsheet/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null
xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-buds 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-budsmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: both `** BUILD SUCCEEDED **`. (The transaction Category picker is unchanged in behavior — same swatch/icon/name/checkmark/chevron, now via the shared row.)

- [ ] **Step 4: Commit**

```bash
cd /tmp/finch-budsheet && git add ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryPickerRow.swift && git commit -m "refactor(ios): extract shared CategoryTreeRow from the category picker sheet"
```

---

### Task 3: Category tree multi-select + rewire `BudgetSheet`

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryMultiPickerRow.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift`

**Interfaces:**
- Consumes: `CategoryTreeRow` (Task 2), `multiSelectSummary` + `MultiSelectPickerRow` + `PickerOption` (Task 1), `categoryForest`, `flattenCategories`, `FlatCategory`, `TxnKindIcon.icon(for:)`.
- Produces: `struct CategoryMultiPickerRow(title: String, categories: [CategoryRow], selection: Binding<Set<String>>, emptyLabel: String)`.

- [ ] **Step 1: Create the category tree multi-select row/sheet**

Create `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryMultiPickerRow.swift`:

```swift
import SwiftUI
import FinchCore

/// A form row that shows the selected categories' summary and opens a full-height
/// BOTTOM SHEET rendering the category HIERARCHY as a MULTI-select tree — the
/// multi-select sibling of `CategoryPickerRow`. Staged-then-Confirm.
struct CategoryMultiPickerRow: View {
    let title: String
    let categories: [CategoryRow]
    @Binding var selection: Set<String>
    let emptyLabel: String
    @State private var presented = false

    private var summary: String {
        multiSelectSummary(names: categories.filter { selection.contains($0.id) }.map(\.name), emptyLabel: emptyLabel)
    }

    var body: some View {
        Button { presented = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Text(summary).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1).truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            CategoryMultiPickerSheet(title: title, categories: categories, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: a searchable category tree, MULTI-select. Tapping toggles a
/// staged id (checkmark); the chevron expands/collapses parents; search force-
/// expands. Confirm applies the staged set; Cancel discards.
private struct CategoryMultiPickerSheet: View {
    let title: String
    let categories: [CategoryRow]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var staged: Set<String>

    init(title: String, categories: [CategoryRow], selection: Binding<Set<String>>) {
        self.title = title
        self.categories = categories
        self._selection = selection
        self._staged = State(initialValue: selection.wrappedValue)
    }

    private var byId: [String: CategoryRow] { Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }) }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(categories), expanded: expanded, search: query)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { item in
                    CategoryTreeRow(
                        item: item, byId: byId,
                        isSelected: staged.contains(item.row.id),
                        expanded: expanded.contains(item.row.id),
                        searchActive: !query.isEmpty,
                        onTap: {
                            if staged.contains(item.row.id) { staged.remove(item.row.id) } else { staged.insert(item.row.id) }
                        },
                        onToggleExpand: {
                            if expanded.contains(item.row.id) { expanded.remove(item.row.id) } else { expanded.insert(item.row.id) }
                        }
                    )
                }
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button { selection = staged; dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Confirm").confirmCheckmarkStyle()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Remove the inline Type picker from `BudgetSheet`'s first section**

In `BudgetSheet.swift`, delete these two lines (currently 57–58):

```swift
                    Picker("Type", selection: $kind) { ForEach(Kind.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
```

- [ ] **Step 3: Replace the two inline category/account sections with two picker rows**

In `BudgetSheet.swift`, replace the two `Section` blocks (the "Categories" section and the "Accounts" section, currently lines 73–107) with:

```swift
                Section {
                    CategoryMultiPickerRow(
                        title: kind == .income ? "Income categories" : "Categories",
                        categories: categories,
                        selection: $selectedCategories,
                        emptyLabel: kind == .income ? "All income categories" : "All categories")
                    MultiSelectPickerRow(
                        title: "Accounts",
                        options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "Account") },
                        selection: $selectedAccounts,
                        emptyLabel: "All accounts")
                } footer: {
                    Text("Leave empty to track all \(kind.rawValue) categories and accounts.")
                }
```

- [ ] **Step 4: Move the type picker to the toolbar `.principal` slot**

In `BudgetSheet.swift`, inside the existing `.toolbar { … }` (currently lines 138–148), add a principal item alongside the cancel/save items (mirrors `AddTransactionSheet`):

```swift
                ToolbarItem(placement: .principal) {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { k in
                            Image(systemName: TxnKindIcon.icon(for: k.rawValue)).accessibilityLabel(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
```

- [ ] **Step 5: Build FinchApp + FinchMac**

```bash
cd /tmp/finch-budsheet/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null
xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-buds 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-budsmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the summary test (regression)**

```bash
cd /tmp/finch-budsheet/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/MultiSelectSummaryTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /tmp/finch-budsheet && git add ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryMultiPickerRow.swift ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift && git commit -m "feat(ios): Budget sheet — tree/flat multi-select pickers + Expense|Income in the toolbar"
```

---

## Manual sim verification (controller/human, after Task 3)

Install & open Add Budget (`xcrun simctl launch ios-finch2 com.juchengquan.finch` → Budgets → +). Confirm: the **Expense | Income** segmented control sits centered in the toolbar (icons); the **Categories** row opens the hierarchy tree as a multi-select (check across parents/children, search force-expands, Confirm/Cancel); the **Accounts** row opens the flat searchable multi-select; the row summaries read "All categories/accounts" when empty and the joined names otherwise; saving persists the same sets as before, and editing an existing budget pre-checks its categories/accounts. Also open the Add **Transaction** sheet's Category picker to confirm the shared-row refactor left it unchanged.

## Out of scope

Creating new categories/accounts from the pickers; parent→child UI cascade (the engine `expandDescendants`); any change to `save()`/the engine; account reorder/grouping in the sheet; zh-Hans strings for new copy (standard localization pass).

## Self-Review

**Spec coverage:** categories tree multi-select (Task 3 `CategoryMultiPickerRow`/`Sheet` on Task 2's `CategoryTreeRow`); accounts flat multi-select (Task 1 `MultiSelectPickerRow`); "add = assign existing" (both pickers select existing rows into the `Set` bindings, `save()` untouched); type control to `.principal` (Task 3 Steps 2+4, icons via `TxnKindIcon`); inline sections → two rows + footer (Task 3 Step 3); DRY shared row touching the transaction picker (Task 2); pure summary helper + tests (Task 1); FinchApp + FinchMac builds (Tasks 2, 3). All covered.

**Placeholder scan:** none — complete code and exact line anchors throughout.

**Type consistency:** `PickerOption(id:name:)` reused from `SearchablePickerRow.swift`. `multiSelectSummary(names:emptyLabel:)` and `MultiSelectPickerRow(title:options:selection:emptyLabel:)` (Task 1) are called verbatim in Task 3. `CategoryTreeRow(item:byId:isSelected:expanded:searchActive:onTap:onToggleExpand:)` (Task 2) is called with those exact labels by both the refactored single-select sheet (Task 2) and `CategoryMultiPickerSheet` (Task 3). `FlatCategory.row/.depth/.hasChildren` and `TxnKindIcon.icon(for:)` match the verified source.
