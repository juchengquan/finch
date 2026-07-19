# Multi-select Category Merge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user select several same-kind categories from a ⋯-menu "Merge" mode and combine them into one atomically, choosing which name survives.

**Architecture:** Refactor the pairwise `mergeCategory` handler's per-source body into a shared `mergeOne` helper, then add a new atomic `mergeCategories(sourceIds, targetId)` action that loops it over N sources in one transaction. In `CategoriesView`, add a select mode (mirroring reorder mode) with checkmark rows, an ancestor/descendant-aware disable rule, and a toolbar-anchored "Keep which name?" dialog.

**Tech Stack:** Swift, GRDB (SQLite) via FinchCore; SwiftUI (iOS 17 / macOS 14 floor); XCTest; XcodeGen; `xcodebuild`.

## Global Constraints

- **Worktree / branch:** this builds on the pairwise merge (#511). Execute on a fresh worktree **`/tmp/finch-mm`** created off `origin/feat/frontend` **after #511 merges** (so `mergeCategory` + `CategoriesView`'s merge UI are present). Branch `feat/ios-category-merge-multi`; PR targets `feat/frontend`. If a command below shows a different worktree path, use your assigned worktree.
- **Environment:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`xcodegen`. Run `xcodegen generate` (from `<worktree>/ios`) after adding a file. Sim `ios-finch2`; iOS `-derivedDataPath /tmp/dd-cat`, mac `/tmp/dd-catmac`.
- **Commits:** no `Co-Authored-By` trailer. Conventional `feat(ios): …` subjects.
- **No schema change.** Only SQL UPDATE/DELETE. Do not edit `Storage/Schema.swift`.
- **Engine facts (verbatim):** `Apply.apply` wraps the handler in one `dbQueue.write` (atomic). Depth helpers `categoryDepth`(top-level=1)/`subtreeDepth`(leaf=1), cap `categoryDepth(newParent)+subtreeDepth(moving) > 3`; `isInSubtreeOf(db,candidate,ancestor)` for the descendant guard — all private static in `Categories`. `ArgsTests.test_actionCount` hardcodes the count (78 after #511) → becomes 79. `ApplyTests` asserts every `ActionName` has a registered handler (dynamic).
- **Copy (verbatim; en source == key):** `"Merge…"`, `"Keep which name?"`, `"Merge (%lld)"` (Swift `"Merge (\(count))"`), `Keep "%@"` (`"Keep \"\(name)\""`), and the existing `"%lld transactions will be combined"` / `"1 transaction will be combined"`. New keys join the tracked zh-Hans batch.

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` | 1 | add `case mergeCategories` |
| `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift` | 1 | extract `mergeOne`; add `mergeMany` handler + register |
| `ios/FinchCore/Tests/FinchCoreTests/CategoryMergeMultiTests.swift` | 1 (create) | multi-merge engine tests |
| `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift` | 1 | action count 78 → 79 |
| `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift` | 2 | `mergeSelectionDisabled(_:selected:byId:)` |
| `ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift` | 2 | helper tests |
| `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift` | 3 | select mode + survivor dialog |

Consumed (present): `mergeCategory`/`merge` handler (#511), `Selectors.categoryTransactions`, `mergeImpactMessage`, `flattenCategories`/`categoryForest`/`FlatCategory`, `store.apply`, `Args`, `JSONValue`.

---

### Task 1: `mergeCategories` engine action (refactor `mergeOne` + new action)

**Files:** Modify `ActionName.swift`, `Categories.swift`, `ArgsTests.swift`; Create `CategoryMergeMultiTests.swift`.

**Interfaces:**
- Consumes: the existing `merge` handler body, `categoryDepth`/`subtreeDepth`/`isInSubtreeOf`.
- Produces: `ActionName.mergeCategories`; handler `Categories.mergeMany(_ db:_ args:)` dispatched as `"mergeCategories"` with args `{ sourceIds: [String], targetId: String }` (sources absorbed, target survives). A private `mergeOne(_ db:, source:, target:)` reused by both merge actions. Task 3 calls `store.apply(.mergeCategories, …)`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/CategoryMergeMultiTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class CategoryMergeMultiTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','a1','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            for c in ["cKeep", "cB", "cC"] {  // cKeep = survivor/target; cB,cC = absorbed
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }
    private func addTx(_ q: DatabaseQueue, _ id: String, _ cat: String) throws {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string(id), "categoryId": .string(cat), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
    }
    private func mergeMany(_ q: DatabaseQueue, _ sources: [String], _ target: String) throws {
        try Apply.apply(dbQueue: q, action: "mergeCategories",
                        args: Args(["sourceIds": .array(sources.map(JSONValue.string)), "targetId": .string(target)]))
    }

    func test_all_sources_repoint_and_are_deleted() throws {
        let q = try seeded()
        try addTx(q, "t1", "cB")
        try addTx(q, "t2", "cC")
        try mergeMany(q, ["cB", "cC"], "cKeep")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id IN ('cB','cC')"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cKeep'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id IN ('cB','cC')"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cKeep'"), 1)
        }
    }

    func test_child_of_a_source_reparents_under_target() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cB','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        try mergeMany(q, ["cB"], "cKeep")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = 'cKid'"), "cKeep")
        }
    }

    func test_bad_source_rejects_and_leaves_everything_untouched() throws {
        let q = try seeded()
        try addTx(q, "t1", "cB")
        try q.write { db in  // cC2 is INCOME — cross-kind, must abort the whole set
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cInc','l1',NULL,'Salary','income',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try mergeMany(q, ["cB", "cInc"], "cKeep"))
        try q.read { db in  // cB's tx NOT repointed, cB still present — nothing merged
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cB'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cB'"), 1)
        }
    }

    func test_target_in_sources_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try mergeMany(q, ["cB", "cKeep"], "cKeep"))
    }

    func test_empty_sources_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try mergeMany(q, [], "cKeep"))
    }

    func test_descendant_target_rejected() throws {
        let q = try seeded()
        try q.write { db in  // cKid is a child of cB; merging cB into cKid = into own descendant
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cB','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try mergeMany(q, ["cB"], "cKid"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/CategoryMergeMultiTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `Apply.apply` throws for the unknown action `"mergeCategories"`.

- [ ] **Step 3: Add the `ActionName` case**

In `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift`, in the `// --- categories (4) ---` block (after `case mergeCategory`), add `case mergeCategories` and update the count comment to `(5)`:

```swift
    // --- categories (5) ---
    case createCategory
    case updateCategory
    case deleteCategory
    case mergeCategory
    case mergeCategories
```

- [ ] **Step 4: Refactor `merge` to use `mergeOne`, and add `mergeMany`**

In `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift`, register both merges in the `handlers` map (add the `mergeCategories` line):

```swift
        .mergeCategory: merge,
        .mergeCategories: mergeMany,
```

Replace the current `merge(_:_:)` handler (the whole function, its body ends with the `DELETE FROM categories` line) with the extracted-helper version plus `mergeMany`:

```swift
    static func merge(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceId: String; let targetId: String }
        let a = try args.to(A.self)
        try validateMerge(db, source: a.sourceId, target: a.targetId)
        try mergeOne(db, source: a.sourceId, target: a.targetId)
        try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [a.sourceId])
    }

    /// Combine many `sourceIds` into `targetId` in one transaction (Apply wraps).
    /// All sources are validated up-front, so a bad one aborts the whole set with
    /// nothing merged. Sources' children re-parent under target; sources deleted.
    static func mergeMany(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceIds: [String]; let targetId: String }
        let a = try args.to(A.self)
        if a.sourceIds.isEmpty {
            throw I18nError("error.invalidArgs", [:], "mergeCategories requires at least one source")
        }
        for source in a.sourceIds { try validateMerge(db, source: source, target: a.targetId) }
        for source in a.sourceIds { try mergeOne(db, source: source, target: a.targetId) }
        for source in a.sourceIds {
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [source])
        }
    }

    /// Shared guards for a single source→target merge (self, existence, same-kind,
    /// not-into-own-descendant). Read-only — no writes.
    private static func validateMerge(_ db: Database, source: String, target: String) throws {
        if source == target {
            throw I18nError("error.category.mergeSelf", [:], "Cannot merge a category into itself")
        }
        guard let sKind = try String.fetchOne(db, sql: "SELECT kind FROM categories WHERE id = ?", arguments: [source]),
              let tKind = try String.fetchOne(db, sql: "SELECT kind FROM categories WHERE id = ?", arguments: [target]) else {
            throw I18nError("error.notFound.category", [:], "Category does not exist")
        }
        if sKind != tKind {
            throw I18nError("error.category.mergeKind", [:], "Categories must be the same type to merge")
        }
        if try isInSubtreeOf(db, target, source) {
            throw I18nError("error.category.mergeDescendant", [:], "Cannot merge a category into its own subcategory")
        }
    }

    /// Repoint every reference `source` holds onto `target` and re-parent source's
    /// children under target (top-level fallback past the 3-level cap). Does NOT
    /// validate or delete `source`. Runs inside the caller's transaction.
    private static func mergeOne(_ db: Database, source: String, target: String) throws {
        try db.execute(sql: "UPDATE postings SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        try db.execute(sql: "UPDATE scheduled_templates SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        try db.execute(sql: "UPDATE scheduled_splits SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        for row in try Row.fetchAll(db, sql: "SELECT id, category_ids FROM budgets WHERE category_ids LIKE ?", arguments: ["%\(source)%"]) {
            guard let raw = row["category_ids"] as String?, let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: data), parsed.contains(source) else { continue }
            var seen = Set<String>()
            let rewritten = parsed.map { $0 == source ? target : $0 }.filter { seen.insert($0).inserted }
            let json = String(data: try JSONEncoder().encode(rewritten), encoding: .utf8)
            try db.execute(sql: "UPDATE budgets SET category_ids = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [json, row["id"] as String])
        }
        let children = try String.fetchAll(db, sql: "SELECT id FROM categories WHERE parent_id = ?", arguments: [source])
        for child in children {
            let fits = try categoryDepth(db, target) + subtreeDepth(db, child) <= 3
            try db.execute(sql: "UPDATE categories SET parent_id = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [fits ? target : nil, child])
        }
    }
```

- [ ] **Step 5: Run the multi-merge tests + the pairwise regression to verify GREEN**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/CategoryMergeMultiTests -only-testing:FinchCoreTests/CategoryMergeTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (6 new + the pairwise suite — the refactor preserves pairwise behavior).

- [ ] **Step 6: Bump the action count**

In `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift`, change `XCTAssertEqual(ActionName.allCases.count, 78)` to `79`, and extend the doc comment above it with `+ mergeCategories = 79`.

- [ ] **Step 7: Run ArgsTests + ApplyTests**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/ArgsTests -only-testing:FinchCoreTests/ApplyTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd /tmp/finch-mm && git add ios/FinchCore/Sources/FinchCore/Store/ActionName.swift ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift ios/FinchCore/Tests/FinchCoreTests/CategoryMergeMultiTests.swift ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift && git commit -m "feat(ios): mergeCategories action (atomic multi-source merge; extract mergeOne)"
```

---

### Task 2: `mergeSelectionDisabled` pure helper

**Files:** Modify `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift`; Test `ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift`.

**Interfaces:**
- Consumes: `CategoryRow`.
- Produces: `func mergeSelectionDisabled(_ candidate: String, selected: Set<String>, byId: [String: CategoryRow]) -> Bool` — true when `candidate` is an ancestor or descendant of any id in `selected` (excluding itself). Task 3 uses it to disable relatives during select mode.

- [ ] **Step 1: Write the failing test**

Add to `ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift` (inside the class, using the existing `cat(_:_:parent:)` helper):

```swift
    func test_mergeSelectionDisabled_flags_ancestors_and_descendants_only() {
        // food → groc → organic ; home (unrelated)
        let rows = [cat("food", "Food"), cat("groc", "Groceries", parent: "food"),
                    cat("organic", "Organic", parent: "groc"), cat("home", "Home")]
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        // With "groc" selected: its ancestor (food) and descendant (organic) are disabled…
        XCTAssertTrue(mergeSelectionDisabled("food", selected: ["groc"], byId: byId))
        XCTAssertTrue(mergeSelectionDisabled("organic", selected: ["groc"], byId: byId))
        // …an unrelated peer is not, and the selected row itself is not disabled.
        XCTAssertFalse(mergeSelectionDisabled("home", selected: ["groc"], byId: byId))
        XCTAssertFalse(mergeSelectionDisabled("groc", selected: ["groc"], byId: byId))
        // Nothing selected → nothing disabled.
        XCTAssertFalse(mergeSelectionDisabled("food", selected: [], byId: byId))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryForestTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `cannot find 'mergeSelectionDisabled' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift`:

```swift
/// True if `candidate` shares an ancestor/descendant line with any id in
/// `selected` (excluding itself). Used to disable a category during multi-select
/// merge when one of its ancestors or descendants is already selected, so the
/// selected set stays mutually unrelated (no merging a category with its own
/// parent/child). Bounded walk (≤10 hops; the tree is ≤3 deep).
func mergeSelectionDisabled(_ candidate: String, selected: Set<String>, byId: [String: CategoryRow]) -> Bool {
    func isAncestor(_ a: String, of b: String) -> Bool {
        var cur = byId[b]?.parentId
        var hops = 0
        while let c = cur, hops < 10 {
            if c == a { return true }
            cur = byId[c]?.parentId
            hops += 1
        }
        return false
    }
    for s in selected where s != candidate {
        if isAncestor(candidate, of: s) || isAncestor(s, of: candidate) { return true }
    }
    return false
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryForestTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-mm && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift && git commit -m "feat(ios): mergeSelectionDisabled helper for multi-select merge"
```

---

### Task 3: Select-mode UI on the Categories page

**Files:** Modify `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`.

**Interfaces:**
- Consumes: `ActionName.mergeCategories` (Task 1), `mergeSelectionDisabled` (Task 2), `mergeImpactMessage` + `Selectors.categoryTransactions` (present), `rows`/`byId`, `store.apply`.
- Produces: nothing downstream.

- [ ] **Step 1: Add select-mode state**

In `CategoriesView`, after `@State private var mergeChoice: MergePair?`, add:

```swift
    @State private var isSelecting = false                  // ⋯ → Merge multi-select mode
    @State private var selected: Set<String> = []           // ids ticked in select mode
    @State private var mergeManySurvivorChoice: [CategoryRow]?   // → keep-which-name dialog
```

- [ ] **Step 2: Add "Merge…" to the ⋯ menu and a select-mode toolbar**

Replace the whole `toolbarContent` computed property with the three-way version:

```swift
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge (\(selected.count))") { mergeManySurvivorChoice = selected.compactMap { byId[$0] } }
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
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
            }
        }
    }
```

- [ ] **Step 3: Add the survivor dialog + clear selection on kind change**

In `body`, immediately after the existing merge `.alert(... presenting: mergeChoice ...)` block, add the multi-merge confirmation dialog and an `onChange` that clears a stale cross-kind selection:

```swift
        .confirmationDialog("Keep which name?", isPresented: Binding(
            get: { mergeManySurvivorChoice != nil }, set: { if !$0 { mergeManySurvivorChoice = nil } }),
            titleVisibility: .visible, presenting: mergeManySurvivorChoice) { picks in
            ForEach(picks) { survivor in
                Button("Keep \"\(survivor.name)\"") { mergeMany(keeping: survivor, from: picks) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { picks in
            if let msg = mergeImpactMessage(txCount: mergeManyTxCount(picks)) { Text(msg) }
        }
        .onChange(of: kind) { _, _ in selected = [] }
```

- [ ] **Step 4: Add the select-mode row branch**

In `row(_:_:)`, add an `isSelecting` branch as the FIRST case (before `if isReordering`). Change the opening of the method from:

```swift
    @ViewBuilder private func row(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
        let c = item.row
        if isReordering {
```
to:
```swift
    @ViewBuilder private func row(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
        let c = item.row
        if isSelecting {
            rowContent(item, counts)   // rowContent shows the checkmark + toggles selection
        } else if isReordering {
```

(The rest of `row` — the reorder and browse branches — stays exactly as is.)

- [ ] **Step 5: Make `rowContent` selection-aware**

Replace `rowContent(_:_:)` with the version that shows a leading checkmark, toggles selection, and dims disabled relatives in select mode:

```swift
    /// The shared row visual. In select mode it shows a leading checkmark and taps
    /// toggle selection (relatives of a selected row are dimmed + inert); otherwise
    /// the swatch/name/count opens the category's transactions, with a trailing
    /// disclosure chevron for parents.
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
        .opacity(selectDisabled ? 0.35 : 1)
        .contentShape(Rectangle())
    }
```

- [ ] **Step 6: Add the merge helpers**

In `CategoriesView`, next to the existing `merge(source:target:)`, add:

```swift
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
```

- [ ] **Step 7: Build FinchApp**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Build FinchMac**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-catmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Run the full category test set**

```bash
cd /tmp/finch-mm/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/CategoryMergeMultiTests -only-testing:FinchCoreTests/CategoryMergeTests -only-testing:FinchAppTests/CategoryForestTests -only-testing:FinchAppTests/CategoryMergeImpactTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
cd /tmp/finch-mm && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift && git commit -m "feat(ios): multi-select merge mode on the Categories page"
```

---

## Manual sim verification (controller / human, after Task 3)

Build, install to `ios-finch2`, open Settings › Categories:
1. ⋯ → **Merge…** enters select mode (checkmark circles; toolbar shows "Merge (0)" disabled + ✕).
2. Tick two expense categories → "Merge (2)" enables; ticking a category dims/disables its parent and children.
3. "Merge (N)" → the **"Keep which name?"** dialog lists the selected names + "X transactions will be combined"; pick one → the others fold in and select mode exits.
4. Switching the Expense/Income segment while selecting clears the selection.
5. The per-row swipe/context **Merge…** still works (unchanged).

## Out of scope

Subtree flattening (merging a category with its own parent/child), web parity, archive (Phase 3). New strings (`"Merge (%lld)"`, reused merge copy) tracked for the zh-Hans batch.

## Self-Review

**Spec coverage:** select mode entry via ⋯ (Task 3 Step 2); checkmark rows + ancestor/descendant disable (Task 2 helper + Task 3 Step 5); "Merge (N)" ≥2 + Cancel (Step 2); survivor dialog with combined count (Step 3, reusing `mergeImpactMessage`); atomic `mergeCategories` reusing `mergeOne` (Task 1); both entry points kept (browse branch untouched); same-kind/self/descendant/empty guards (Task 1 `validateMerge` + `mergeMany`); action-count/coverage bump (Task 1 Steps 6–7). All covered.

**Placeholder scan:** none — complete code and exact commands throughout.

**Type consistency:** `mergeCategories` args `{sourceIds:[String], targetId:String}` defined in Task 1, called with those exact keys in Task 3's `mergeMany`. `mergeSelectionDisabled(_:selected:byId:)` defined in Task 2, called in Task 3 Step 5. `mergeManySurvivorChoice: [CategoryRow]?`, `selected: Set<String>`, `isSelecting`, `mergeManyTxCount`, `mergeMany(keeping:from:)` consistent within Task 3. `mergeOne`/`validateMerge` are private, reused by both `merge` and `mergeMany` — pairwise behavior unchanged (guards + `mergeOne` + single delete).
