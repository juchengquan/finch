# Category Merge — Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Combine two same-kind categories into one via a new atomic `mergeCategory` engine action and a "Merge…" flow on the Categories page, where the only choice is which name survives.

**Architecture:** A new `FinchCore` action `mergeCategory(sourceId → targetId)` repoints every reference the absorbed (`source`) category holds — transaction legs (incl. splits), scheduled templates + scheduled splits, budget category-id lists — re-parents the source's children under the survivor (top-level fallback past the 3-level cap), then deletes the source, all in one write transaction. `FinchApp` adds a "Merge…" swipe/context action → same-kind target picker → a "Keep which name?" alert that maps the name choice to source/target.

**Tech Stack:** Swift, GRDB (SQLite) via FinchCore; SwiftUI (iOS 17 / macOS 14 floor); XCTest; XcodeGen (`FinchApp.xcodeproj`); `xcodebuild`.

## Global Constraints

- **Worktree / branch:** this phase builds on the Phase 1 Categories code (the `CategoriesView` rewrite, and the `Selectors.categoryTransactions` selector). At execution, create the worktree off the Phase 1 branch `feat/ios-categories-page` (or off `feat/frontend` once PR #505 has merged). PR targets `feat/frontend`.
- **Environment:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`xcodegen`.
- **Regenerate the project after adding a Swift file:** `cd /tmp/finch-cat/ios && xcodegen generate` (path-globbed sources; `.xcodeproj` is git-ignored).
- **Simulator:** `platform=iOS Simulator,name=ios-finch2`; use `-derivedDataPath /tmp/dd-cat` (iOS) / `/tmp/dd-catmac` (mac).
- **Commits:** no `Co-Authored-By` trailer. Conventional `feat(ios): …` subjects.
- **No schema change.** Only SQL `UPDATE`/`DELETE` inside the new action. Do not edit `Storage/Schema.swift`.
- **Engine facts (verbatim, do not re-derive):**
  - `Apply.apply(dbQueue:action:args:)` wraps the handler in a single `dbQueue.write { db in … }` — the whole handler is one atomic transaction.
  - Category FK delete rules: `postings.category_id` and `scheduled_templates.category_id` are `ON DELETE SET NULL`; `categories.parent_id` is `ON DELETE SET NULL`; **`scheduled_splits.category_id` is `ON DELETE RESTRICT`** (a plain delete of a category used there fails — merge must repoint it first).
  - Depth helpers in `Categories` (private static, callable from the merge handler in the same enum): `categoryDepth(db, id)` is 1-based (top-level = 1); `subtreeDepth(db, id)` is subtree height (leaf = 1); the cap is `categoryDepth(newParent) + subtreeDepth(moving) > 3` ⇒ too deep. `isInSubtreeOf(db, candidate, ancestor)` returns true if candidate == ancestor or a descendant.
  - `ArgsTests.test_actionCount` asserts `ActionName.allCases.count == 77` (hardcoded) — a new action makes it 78.
  - `ApplyTests` asserts every `ActionName` has a registered handler and `registry.count == ActionName.allCases.count` (dynamic) — the new action MUST be registered in `Categories.handlers`.
- **Copy strings (verbatim; en source == key):** `"Merge…"`, `"Keep which name after merge?"`, `Keep "%@"` (Swift: `Text("Keep \"\(name)\"")`), `"%lld transactions will be combined"`, `"1 transaction will be combined"`, `"Merge \(name) with…"`. New keys join the tracked zh-Hans batch.

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` | 1 | add `case mergeCategory` |
| `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift` | 1 | `merge` handler + register in `handlers` |
| `ios/FinchCore/Tests/FinchCoreTests/CategoryMergeTests.swift` | 1 (create) | engine tests |
| `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift:8` | 1 | bump action count 77 → 78 |
| `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryMergeImpact.swift` | 2 (create) | `mergeImpactMessage(txCount:)` |
| `ios/FinchApp/Tests/FinchAppTests/CategoryMergeImpactTests.swift` | 2 (create) | helper tests |
| `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift` | 3 | Merge action, target picker, keep-name alert |

Consumed (already present, unchanged): `Selectors.categoryTransactions` (Phase 1), `flattenCategories`/`categoryForest`/`FlatCategory`, `store.apply`, `Args`, `JSONValue`, `i18nMessage`, `errorAlert`.

---

### Task 1: `mergeCategory` engine action

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` (add case), `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift` (handler + registration), `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift:8` (count)
- Create: `ios/FinchCore/Tests/FinchCoreTests/CategoryMergeTests.swift`

**Interfaces:**
- Consumes: `Apply.apply`, GRDB `Database`, the private `categoryDepth`/`subtreeDepth`/`isInSubtreeOf` in `Categories`.
- Produces: `ActionName.mergeCategory`; the `Categories.merge(_ db:_ args:)` handler dispatched as action `"mergeCategory"` with args `{ sourceId: String, targetId: String }` (source absorbed, target survives). Task 3 calls it via `store.apply(.mergeCategory, …)`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/CategoryMergeTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class CategoryMergeTests: XCTestCase {
    /// Ledger, two cash accounts, and two same-kind (expense) categories:
    /// cSource (absorbed) and cTarget (survivor).
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            for a in ["a1", "a2"] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash','USD',0,0,1,1,datetime('now'),datetime('now'))", arguments: [a, a])
            }
            for c in ["cSource", "cTarget"] {
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }

    private func merge(_ q: DatabaseQueue, _ source: String, _ target: String) throws {
        try Apply.apply(dbQueue: q, action: "mergeCategory", args: Args(["sourceId": .string(source), "targetId": .string(target)]))
    }

    func test_transaction_and_split_legs_repoint_to_target() throws {
        let q = try seeded()
        // A plain expense categorized to cSource…
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string("x"), "categoryId": .string("cSource"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        // …and a split with one leg on cSource.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-10),
            "merchant": .string("y"), "date": .string("2026-05-02"), "skipRules": .bool(true),
            "splits": .array([
                .object(["categoryId": .string("cSource"), "amount": .double(-4)]),
                .object(["categoryId": .string("cTarget"), "amount": .double(-6)]),
            ])]))
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cTarget'"), 3) // 1 plain + 2 split legs
        }
    }

    func test_scheduled_split_repoints_and_delete_succeeds() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO scheduled_templates (id,ledger_id,kind,account_id,frequency,start_date,created_at,updated_at) VALUES ('st1','l1','expense','a1','monthly','2026-05-01',datetime('now'),datetime('now'))")
            // scheduled_splits.category_id is ON DELETE RESTRICT — a plain delete of cSource would fail.
            try db.execute(sql: "INSERT INTO scheduled_splits (id,template_id,account_id,amount_abs,category_id,sort_order) VALUES ('ss1','st1','a1',10,'cSource',0)")
        }
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM scheduled_splits WHERE id = 'ss1'"), "cTarget")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cSource'"), 0) // RESTRICT cleared → delete OK
        }
    }

    func test_budget_category_ids_rewritten_and_deduped() throws {
        let q = try seeded()
        try q.write { db in
            // one budget listing cSource + cOther, one already listing both cSource + cTarget (dedup case)
            try db.execute(sql: "INSERT INTO budgets (id,ledger_id,kind,amount,frequency,start_date,category_ids,created_at,updated_at) VALUES ('b1','l1','expense',100,'monthly','2026-05-01','[\"cSource\",\"cOther\"]',datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO budgets (id,ledger_id,kind,amount,frequency,start_date,category_ids,created_at,updated_at) VALUES ('b2','l1','expense',100,'monthly','2026-05-01','[\"cSource\",\"cTarget\"]',datetime('now'),datetime('now'))")
        }
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_ids FROM budgets WHERE id = 'b1'"), "[\"cTarget\",\"cOther\"]")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_ids FROM budgets WHERE id = 'b2'"), "[\"cTarget\"]") // deduped
        }
    }

    func test_child_reparents_under_target() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cSource','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = 'cKid'"), "cTarget")
        }
    }

    func test_child_falls_back_to_top_level_when_depth_would_exceed_cap() throws {
        let q = try seeded()
        try q.write { db in
            // target is a depth-2 category (level 3): parent p1(1) → p2(2) → cTarget2(3-ish).
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('p1','l1',NULL,'P1','expense',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('deepTarget','l1','p1','DT','expense',0,datetime('now'),datetime('now'))")
            // source has a child that itself has a child (subtreeDepth 2) — cannot fit under a depth-2 target.
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cSource','Kid','expense',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cGrandkid','l1','cKid','GK','expense',0,datetime('now'),datetime('now'))")
        }
        try merge(q, "cSource", "deepTarget")
        try q.read { db in
            // categoryDepth(deepTarget)=2, subtreeDepth(cKid)=2 → 4 > 3 ⇒ cKid goes to top level.
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = 'cKid'"))
        }
    }

    func test_source_row_is_deleted() throws {
        let q = try seeded()
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cTarget'"), 1)
        }
    }

    func test_merge_into_self_is_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try merge(q, "cSource", "cSource"))
    }

    func test_merge_into_own_descendant_is_rejected() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cSource','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try merge(q, "cSource", "cKid"))  // target is a descendant of source
    }

    func test_cross_kind_merge_is_rejected() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cIncome','l1',NULL,'Salary','income',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try merge(q, "cSource", "cIncome"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/CategoryMergeTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `Apply.apply` throws for the unknown action `"mergeCategory"` (every test errors).

- [ ] **Step 3: Add the `ActionName` case**

In `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift`, in the `// --- categories (3) ---` block (after `case deleteCategory`), add:

```swift
    case mergeCategory
```

- [ ] **Step 4: Implement the handler + register it**

In `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift`, add `mergeCategory` to the `handlers` map:

```swift
    public static let handlers: [ActionName: Apply.Handler] = [
        .createCategory: create,
        .updateCategory: update,
        .deleteCategory: delete,
        .mergeCategory: merge,
    ]
```

Then add the `merge` handler (place it right after `delete(_:_:)`):

```swift
    /// Combine `sourceId` into `targetId`: repoint every reference source holds
    /// (transaction legs incl. splits, scheduled templates + splits, budget id
    /// lists), re-parent source's children under target (top-level fallback past
    /// the 3-level cap), then delete source. One atomic transaction (Apply wraps).
    static func merge(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceId: String; let targetId: String }
        let a = try args.to(A.self)
        let source = a.sourceId, target = a.targetId

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

        // 1. transaction legs (covers split legs too)
        try db.execute(sql: "UPDATE postings SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        // 2. scheduled references (the scheduled_splits one clears the ON DELETE RESTRICT)
        try db.execute(sql: "UPDATE scheduled_templates SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        try db.execute(sql: "UPDATE scheduled_splits SET category_id = ? WHERE category_id = ?", arguments: [target, source])
        // 3. budgets: rewrite category_ids JSON (source→target, de-duplicated, order-preserving)
        for row in try Row.fetchAll(db, sql: "SELECT id, category_ids FROM budgets WHERE category_ids LIKE ?", arguments: ["%\(source)%"]) {
            guard let raw = row["category_ids"] as String?, let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: data), parsed.contains(source) else { continue }
            var seen = Set<String>()
            let rewritten = parsed.map { $0 == source ? target : $0 }.filter { seen.insert($0).inserted }
            let json = (try? JSONEncoder().encode(rewritten)).flatMap { String(data: $0, encoding: .utf8) }
            try db.execute(sql: "UPDATE budgets SET category_ids = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [json, row["id"] as String])
        }
        // 4. re-parent source's children under target, or to top level past the cap
        let children = try String.fetchAll(db, sql: "SELECT id FROM categories WHERE parent_id = ?", arguments: [source])
        for child in children {
            let fits = try categoryDepth(db, target) + subtreeDepth(db, child) <= 3
            try db.execute(sql: "UPDATE categories SET parent_id = ?, updated_at = datetime('now') WHERE id = ?",
                           arguments: [fits ? target : nil, child])
        }
        // 5. remove the absorbed category
        try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [source])
    }
```

- [ ] **Step 5: Run the merge tests to verify they pass**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/CategoryMergeTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (9 tests).

- [ ] **Step 6: Bump the action-count assertion**

In `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift:8`, change:

```swift
        XCTAssertEqual(ActionName.allCases.count, 77)
```
to:
```swift
        XCTAssertEqual(ActionName.allCases.count, 78)
```

- [ ] **Step 7: Run ArgsTests + ApplyTests (handler-registration coverage) to verify green**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/ArgsTests -only-testing:FinchCoreTests/ApplyTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (ApplyTests confirms `mergeCategory` is registered; ArgsTests confirms the count).

- [ ] **Step 8: Commit**

```bash
cd /tmp/finch-cat && git add ios/FinchCore/Sources/FinchCore/Store/ActionName.swift ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift ios/FinchCore/Tests/FinchCoreTests/CategoryMergeTests.swift ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift && git commit -m "feat(ios): mergeCategory engine action (repoint refs + reparent children + delete)"
```

---

### Task 2: `mergeImpactMessage` pure helper

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryMergeImpact.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/CategoryMergeImpactTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `func mergeImpactMessage(txCount: Int) -> String?` — `nil` when 0; singular for 1; plural otherwise. Task 3 renders it in the keep-name alert.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/CategoryMergeImpactTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class CategoryMergeImpactTests: XCTestCase {
    func test_zero_returns_nil() {
        XCTAssertNil(mergeImpactMessage(txCount: 0))
    }
    func test_one_is_singular() {
        XCTAssertEqual(mergeImpactMessage(txCount: 1), "1 transaction will be combined")
    }
    func test_many_is_plural() {
        XCTAssertEqual(mergeImpactMessage(txCount: 8), "8 transactions will be combined")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryMergeImpactTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `cannot find 'mergeImpactMessage' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryMergeImpact.swift`:

```swift
import Foundation

/// Impact line for the merge confirmation, or `nil` when nothing combines. The
/// count is the choice-independent union of transactions referencing either
/// category, so the message is identical whichever name wins.
func mergeImpactMessage(txCount: Int) -> String? {
    guard txCount > 0 else { return nil }
    return txCount == 1
        ? String(localized: "1 transaction will be combined")
        : String(localized: "\(txCount) transactions will be combined")
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/CategoryMergeImpactTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-cat && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryMergeImpact.swift ios/FinchApp/Tests/FinchAppTests/CategoryMergeImpactTests.swift && git commit -m "feat(ios): mergeImpactMessage helper for the merge prompt"
```

---

### Task 3: Merge UI on the Categories page

Add a "Merge…" action (trailing swipe + context menu) that opens a same-kind target picker, then a "Keep which name?" alert whose two name buttons map to the survivor.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`

**Interfaces:**
- Consumes: `ActionName.mergeCategory` (Task 1), `mergeImpactMessage` (Task 2), `Selectors.categoryTransactions` (Phase 1), `rows`/`byId`, `flattenCategories`/`categoryForest`/`FlatCategory`, `effectiveColor`/`effectiveIcon`, `CategoryIcon`, `store.apply`, `i18nMessage`, `errorAlert`.
- Produces: nothing downstream.

- [ ] **Step 1: Add merge state + the `MergePair` type**

In `CategoriesView`, after `@State private var selectedCategoryId: String?`, add:

```swift
    @State private var mergingFrom: CategoryRow?   // → target picker sheet
    @State private var mergeChoice: MergePair?     // → keep-which-name alert
```

Add this type just above `struct CategoriesView` (below the `CategoryKind` enum):

```swift
/// A chosen (initiating A, target B) pair for a merge; the alert picks which survives.
private struct MergePair: Identifiable {
    let a: CategoryRow   // the row the merge was started from
    let b: CategoryRow   // the picked other category
    var id: String { a.id + "|" + b.id }
}
```

- [ ] **Step 2: Add "Merge…" to the row swipe + context menu**

In `row(_:_:)`, in the **browse** branch, extend the existing `.swipeActions` and `.contextMenu` so each also offers Merge. Replace the browse branch's modifiers:

```swift
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
                    Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
                }
```

- [ ] **Step 3: Add the target-picker sheet + keep-name alert to `body`**

In `body`, immediately after the existing `.navigationDestination(item: $selectedCategoryId) { … }` block, add the target-picker sheet and the keep-name alert:

```swift
        .sheet(item: $mergingFrom) { a in
            NavigationStack {
                List {
                    if mergeTargets(excluding: a).isEmpty {
                        ContentUnavailableView("No other categories", systemImage: "arrow.triangle.merge",
                                               description: Text("There's nothing to merge \(a.name) with yet."))
                    } else {
                        ForEach(mergeTargets(excluding: a)) { f in
                            Button {
                                let b = f.row
                                mergingFrom = nil
                                mergeChoice = MergePair(a: a, b: b)
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
```

- [ ] **Step 4: Add the helper methods**

In `CategoriesView`, add these near `delete(_:)`:

```swift
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
```

- [ ] **Step 5: Build FinchApp**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Build FinchMac (cross-platform check)**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-catmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Run the full category test set (engine + app)**

```bash
cd /tmp/finch-cat/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchCoreTests/CategoryMergeTests -only-testing:FinchAppTests/CategoryMergeImpactTests -only-testing:FinchAppTests/CategoryReorderTests -only-testing:FinchAppTests/CategoryForestTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd /tmp/finch-cat && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift && git commit -m "feat(ios): Categories merge UI — Merge… action, target picker, keep-name prompt"
```

---

## Manual sim verification (controller / human, after Task 3)

Build, install to `ios-finch2`, open Settings › Categories, and confirm:
1. Swipe a category row → a **Merge…** action (orange) appears alongside Edit/Delete; long-press → **Merge…** in the context menu.
2. Tapping Merge… opens **"Merge \<name\> with…"** listing the other same-kind categories (not the row itself or its subcategories).
3. Picking one shows the **"Keep which name after merge?"** alert with both name buttons + the "N transactions will be combined" line.
4. Keeping either name: the two categories become one under the chosen name; the other disappears; its transactions now show under the survivor (tap the survivor → its transaction list includes the absorbed one's).

## Out of scope (Phase 2)

Archive / hide (Phase 3), web parity for `mergeCategory`, spending-per-category, consolidating duplicate legs beyond de-dup, and any schema change. New error keys (`error.category.mergeSelf` / `.mergeKind` / `.mergeDescendant`) and the new UI strings are tracked for the zh-Hans batch (translated separately; they fall back to their English source until then).

## Self-Review

**Spec coverage** — every design decision maps to a task:
- Same-kind-only + self/descendant guards: **Task 1** (`test_cross_kind_merge_is_rejected`, `test_merge_into_self_is_rejected`, `test_merge_into_own_descendant_is_rejected`).
- Repoint all references (transactions incl. splits, scheduled templates + the RESTRICT scheduled-splits, budgets dedup): **Task 1** (repoint/scheduled/budget tests).
- Children move under survivor with top-level fallback: **Task 1** (`test_child_reparents_under_target`, `test_child_falls_back_to_top_level_when_depth_would_exceed_cap`).
- Name is the only choice; survivor keeps its own attributes: **Task 3** (the alert maps Keep-A → survivor A / Keep-B → survivor B; the engine never renames).
- Deletion-style keep-which-name prompt with impact count: **Task 2** (helper) + **Task 3** (alert).
- Entry via swipe + context menu; same-kind target picker excluding self+descendants: **Task 3**.
- Atomic, no schema change: **Task 1** (single `Apply.apply` write transaction; only UPDATE/DELETE).
- Action-count/coverage test updates (the #494 class of breakage): **Task 1** Steps 6–7.

**Placeholder scan:** none — every code step has complete code and exact commands.

**Type consistency:** `mergeCategory` action + args `{sourceId, targetId}` defined in Task 1 and called with those exact keys in Task 3's `merge(source:target:)`. `mergeImpactMessage(txCount:) -> String?` defined in Task 2, called in Task 3. `MergePair {a, b}`, `mergingFrom`, `mergeChoice`, `mergeTargets(excluding:)`, `mergeTxCount(_:_:)` are consistent within Task 3. `Selectors.categoryTransactions(_:_:_:)` matches its Phase 1 signature. The keep-name mapping (Keep A ⇒ `merge(source: b, target: a)`) is consistent with the engine's "source absorbed, target survives" contract.