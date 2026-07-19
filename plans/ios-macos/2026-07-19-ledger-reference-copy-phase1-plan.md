# Phase 1 — Categories & Tags copy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let Categories & Tags be copied between ledgers — clone-on-create, whole-domain import, and single-item copy — without changing the per-ledger model.

**Architecture:** Two native-first copy actions (`copyCategories`, `copyTags`) that bulk-INSERT copies carrying the *target* ledger's `ledger_id` (additive, dedup by name, category tree preserved, system rows skipped). A reusable ledger-picker sheet wires them into the Categories/Tags pages and the new-ledger flow. No schema/web/parity change.

**Reference spec:** `plans/ios-macos/2026-07-19-ledger-reference-copy-phase1-design.md`

## Global Constraints

- **Native-first**: add exactly two `ActionName` cases (`copyCategories`, `copyTags`) + handlers. No `frontend/` change, no parity fixtures. `ArgsTests.test_actionCount()` bumps **83 → 85** (+ comment).
- **Additive + dedup by name** (case-insensitive); never modify/delete existing rows; idempotent. **Skip system categories** (`categories.system IS NOT NULL`). Copies get **new ids** + the **target `ledger_id`**; preserve category `kind`/`icon`/`color`/tree (remapped `parent_id`) and tag `color`.
- SwiftUI-first; iOS 17 / macOS 14. **XcodeGen** regen after adding files; **`DEVELOPER_DIR`** for `xcodebuild` (run from `ios/`); don't stage `ios/FinchApp.xcodeproj`; build both iOS + macOS before PR.
- Commits: conventional prefixes, **no `Co-Authored-By` trailer**. Commands run from the worktree root; `swift test`/`xcodegen` from `ios/`.

**App-build gate:** `cd ios && xcodegen generate && cd .. && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -scheme FinchApp -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/finchios-refcopy -quiet` (run xcodebuild from `ios/`).

---

### Task 1: Engine — `copyCategories` + `copyTags` (FinchCore)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` (categories/tags sections)
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift`, `.../Domain/Tags.swift`
- Modify: `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift` (83 → 85)
- Test: `ios/FinchCore/Tests/FinchCoreTests/ReferenceCopyTests.swift` (create)

**Interfaces produced:**
- `copyCategories` args `{ fromLedgerId, toLedgerId, ids?: [String] }` — copies user categories (all, or `ids` + their ancestors), tree preserved, dedup by `(kind, targetParent, name)`, skips system rows.
- `copyTags` args `{ fromLedgerId, toLedgerId, ids?: [String] }` — copies tags (all, or `ids`), dedup by name.

- [ ] **Step 1: Write the failing test** — create `ios/FinchCore/Tests/FinchCoreTests/ReferenceCopyTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class ReferenceCopyTests: XCTestCase {
    /// Two ledgers l1 (source) + l2 (target). No system rows (not needed for copy logic).
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            for l in ["l1", "l2"] {
                try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES (?,?,'USD',0,datetime('now'),datetime('now'))", arguments: [l, l])
            }
        }
        return q
    }
    private func cat(_ q: DatabaseQueue, _ id: String, _ ledger: String, _ name: String, kind: String = "expense", parent: String? = nil, system: String? = nil) throws {
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,system,created_at,updated_at) VALUES (?,?,?,?,?,0,?,datetime('now'),datetime('now'))",
                           arguments: [id, ledger, parent, name, kind, system])
        }
    }
    private func tag(_ q: DatabaseQueue, _ id: String, _ ledger: String, _ name: String) throws {
        try q.write { db in try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,created_at,updated_at) VALUES (?,?,?,datetime('now'),datetime('now'))", arguments: [id, ledger, name]) }
    }
    private func names(_ q: DatabaseQueue, _ table: String, _ ledger: String) throws -> [String] {
        try q.read { db in try String.fetchAll(db, sql: "SELECT name FROM \(table) WHERE ledger_id = ? ORDER BY name", arguments: [ledger]) }
    }

    func test_copyTags_additive_dedup_idempotent() throws {
        let q = try seeded()
        try tag(q, "t1", "l1", "food"); try tag(q, "t2", "l1", "travel")
        try tag(q, "t3", "l2", "Travel")   // already present (case-insensitive dup)
        try Apply.apply(dbQueue: q, action: "copyTags", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")]))
        XCTAssertEqual(try names(q, "tags", "l2"), ["food", "Travel"])   // food added, Travel not duplicated
        // idempotent
        try Apply.apply(dbQueue: q, action: "copyTags", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")]))
        XCTAssertEqual(try names(q, "tags", "l2").count, 2)
    }

    func test_copyTags_ids_scopes_to_named() throws {
        let q = try seeded()
        try tag(q, "t1", "l1", "food"); try tag(q, "t2", "l1", "travel")
        try Apply.apply(dbQueue: q, action: "copyTags", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2"), "ids": .array([.string("t1")])]))
        XCTAssertEqual(try names(q, "tags", "l2"), ["food"])
    }

    func test_copyCategories_preserves_tree_and_dedups() throws {
        let q = try seeded()
        try cat(q, "cFood", "l1", "Food"); try cat(q, "cCoffee", "l1", "Coffee", parent: "cFood")
        try cat(q, "cSys", "l1", "Opening", kind: "equity", system: "opening")  // system → must be skipped
        try cat(q, "cFoodT", "l2", "Food")   // dup at top level → child should attach under it
        try Apply.apply(dbQueue: q, action: "copyCategories", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")]))
        try q.read { db in
            // "Food" not duplicated; "Coffee" added under the existing "Food"; system skipped.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE ledger_id='l2' AND name='Food'"), 1)
            let coffeeParent = try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE ledger_id='l2' AND name='Coffee'")
            XCTAssertEqual(coffeeParent, "cFoodT")
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM categories WHERE ledger_id='l2' AND name='Opening'"))
        }
    }

    func test_copyCategories_ids_includes_ancestors() throws {
        let q = try seeded()
        try cat(q, "cFood", "l1", "Food"); try cat(q, "cCoffee", "l1", "Coffee", parent: "cFood")
        try Apply.apply(dbQueue: q, action: "copyCategories", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2"), "ids": .array([.string("cCoffee")])]))
        // Coffee copied + its ancestor Food, tree intact.
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE ledger_id='l2'"), 2)
            let cp = try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE ledger_id='l2' AND name='Coffee'")
            let foodId = try String.fetchOne(db, sql: "SELECT id FROM categories WHERE ledger_id='l2' AND name='Food'")
            XCTAssertEqual(cp, foodId)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `cd ios && swift test --filter ReferenceCopyTests` → FAIL (unknown actions `copyCategories`/`copyTags`).

- [ ] **Step 3: Implement.**

In `ActionName.swift`, add to the categories block (comment `(5)`→`(6)`): `case copyCategories`; and to the tags block (`(5)`→`(6)`): `case copyTags`.

In `Store/Domain/Tags.swift`, register `.copyTags: copyTags` in `handlers` and add:

```swift
    /// Additively copy tags from one ledger to another, dedup by name
    /// (case-insensitive). `ids` (optional) restricts to those source tags.
    static func copyTags(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let fromLedgerId: String; let toLedgerId: String; let ids: [String]? }
        let a = try args.to(A.self)
        let want = a.ids.map(Set.init)
        let existing = Set(try String.fetchAll(db, sql: "SELECT lower(name) FROM tags WHERE ledger_id = ?", arguments: [a.toLedgerId]))
        for row in try Row.fetchAll(db, sql: "SELECT id, name, color FROM tags WHERE ledger_id = ?", arguments: [a.fromLedgerId]) {
            let id = row["id"] as String
            guard want?.contains(id) ?? true else { continue }
            let name = (row["name"] as String).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || existing.contains(name.lowercased()) { continue }
            try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES (?,?,?,?,datetime('now'),datetime('now'))",
                           arguments: [Entries.newId("tag"), a.toLedgerId, name, row["color"] as String?])
        }
    }
```

In `Store/Domain/Categories.swift`, register `.copyCategories: copyCategories` in `handlers` and add:

```swift
    /// Additively copy user categories from one ledger to another, preserving the
    /// tree and dedup by (kind, target-parent, name). System rows are skipped.
    /// `ids` (optional) restricts to those categories plus their ancestors.
    static func copyCategories(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let fromLedgerId: String; let toLedgerId: String; let ids: [String]? }
        let a = try args.to(A.self)
        // Source user categories (skip system equity rows).
        var byId: [String: Row] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, parent_id, name, kind, icon, color FROM categories WHERE ledger_id = ? AND system IS NULL", arguments: [a.fromLedgerId]) {
            byId[r["id"] as String] = r
        }
        // Wanted set: all, or the ids + their ancestors.
        var wanted = Set(byId.keys)
        if let ids = a.ids {
            wanted = []
            for start in ids {
                var cur: String? = start
                while let c = cur, byId[c] != nil, wanted.insert(c).inserted { cur = byId[c]?["parent_id"] as String? }
            }
        }
        // Target dedup map: (kind|parentTargetId|lowerName) -> target id, over ALL target rows.
        var dedup: [String: String] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, parent_id, name, kind FROM categories WHERE ledger_id = ?", arguments: [a.toLedgerId]) {
            let key = "\(r["kind"] as String)|\(r["parent_id"] as String? ?? "")|\((r["name"] as String).lowercased())"
            dedup[key] = r["id"] as String
        }
        var nextOrder = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM categories WHERE ledger_id = ?", arguments: [a.toLedgerId])) ?? 0
        var idMap: [String: String] = [:]   // source id -> target id (existing or new)
        // Process parents before children.
        var pending = wanted
        while !pending.isEmpty {
            let ready = pending.filter { id in
                let p = byId[id]?["parent_id"] as String?
                return p == nil || !wanted.contains(p!) || idMap[p!] != nil
            }
            if ready.isEmpty { break }   // safety against cycles (schema prevents them)
            for src in ready.sorted() {
                let r = byId[src]!
                let srcParent = r["parent_id"] as String?
                let targetParent: String? = (srcParent != nil && wanted.contains(srcParent!)) ? idMap[srcParent!] : nil
                let name = (r["name"] as String)
                let kind = r["kind"] as String
                let key = "\(kind)|\(targetParent ?? "")|\(name.lowercased())"
                if let existing = dedup[key] { idMap[src] = existing }
                else {
                    let newId = Entries.newId("cat")
                    try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))",
                                   arguments: [newId, a.toLedgerId, targetParent, name, kind, r["icon"] as String?, r["color"] as String?, nextOrder])
                    nextOrder += 1
                    idMap[src] = newId; dedup[key] = newId
                }
                pending.remove(src)
            }
        }
    }
```

In `ArgsTests.swift`, update the count doc + `XCTAssertEqual(ActionName.allCases.count, 85)`.

- [ ] **Step 4: Run to verify pass** — `cd ios && swift test --filter ReferenceCopyTests && swift test --filter ArgsTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/ActionName.swift ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift ios/FinchCore/Sources/FinchCore/Store/Domain/Tags.swift ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift ios/FinchCore/Tests/FinchCoreTests/ReferenceCopyTests.swift
git commit -m "feat(ios): copyCategories + copyTags — additive cross-ledger copy (native-first)"
```

---

### Task 2: Copy UI on Categories & Tags pages

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerPickerSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift`, `.../PowerTools/TagsView.swift`

**Interfaces consumed:** `copyCategories`/`copyTags` (Task 1), `store.ledgers`, `store.activeLedgerId`, `Args`, `i18nMessage`.

- [ ] **Step 1: Create the reusable picker** — `ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerPickerSheet.swift`:

```swift
import SwiftUI
import FinchCore

/// Pick another ledger (excludes the active one). Used by "Import from…" and
/// "Copy to…". Calls `onPick(ledgerId)` then dismisses.
struct LedgerPickerSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                let others = store.ledgers.filter { $0.id != store.activeLedgerId }
                if others.isEmpty {
                    ContentUnavailableView("No other ledgers", systemImage: "books.vertical",
                                           description: Text("Create another ledger first."))
                } else {
                    ForEach(others) { l in
                        Button { onPick(l.id); dismiss() } label: {
                            HStack { Text(l.name).foregroundStyle(.primary); Spacer(); Text(l.base).font(.caption).foregroundStyle(.secondary) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") } }
        }
    }
}
```

- [ ] **Step 2: Wire into `TagsView`.** Add state `@State private var importing = false` and `@State private var copyingTag: TagRow?`. In the `⋯`/toolbar area add a menu (or extend the existing toolbar) with **"Import from another ledger…"** → `importing = true`; add a row context/swipe action **"Copy to another ledger…"** → `copyingTag = tag`. Present:

```swift
        .sheet(isPresented: $importing) {
            LedgerPickerSheet(title: "Import tags from…") { from in
                do { try store.apply(.copyTags, Args(["fromLedgerId": .string(from), "toLedgerId": .string(store.activeLedgerId)])) }
                catch { errorMessage = i18nMessage(error) }
            }
        }
        .sheet(item: $copyingTag) { t in
            LedgerPickerSheet(title: "Copy \(t.name) to…") { to in
                do { try store.apply(.copyTags, Args(["fromLedgerId": .string(store.activeLedgerId), "toLedgerId": .string(to), "ids": .array([.string(t.id)])])) }
                catch { errorMessage = i18nMessage(error) }
            }
        }
```

- [ ] **Step 3: Wire into `CategoriesView`.** Same pattern: a `⋯`-menu **"Import from another ledger…"** (whole domain, `copyCategories` from picked → active) and a row context action **"Copy to another ledger…"** (`copyCategories` active → picked, `ids: [row.id]`). Reuse `LedgerPickerSheet`; surface errors via the existing `errorMessage`.

- [ ] **Step 4: Build** — run the app-build gate. Expect **BUILD SUCCEEDED**.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerPickerSheet.swift ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift ios/FinchApp.xcodeproj
git commit -m "feat(ios): Import-from / Copy-to-ledger actions on Categories & Tags"
```
*(Note: `.xcodeproj` is git-ignored — the `git add` is a no-op; stage only the source files.)*

---

### Task 3: Clone-on-create ("Start from" in the new-ledger sheet)

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerManagementView.swift` (`AddLedgerSheet`).

- [ ] **Step 1: Add a "Start from" picker.** In `AddLedgerSheet` add `@State private var startFrom: String? = nil` and a `Picker` in the `Form`:

```swift
                Picker("Start from", selection: $startFrom) {
                    Text("Blank").tag(String?.none)
                    ForEach(store.ledgers) { l in Text(l.name).tag(Optional(l.id)) }
                }
```

- [ ] **Step 2: Seed on create.** In `create()`, after the successful `createLedger`, before `dismiss()`:

```swift
            if let from = startFrom {
                try? store.apply(.copyCategories, Args(["fromLedgerId": .string(from), "toLedgerId": .string(id)]))
                try? store.apply(.copyTags, Args(["fromLedgerId": .string(from), "toLedgerId": .string(id)]))
            }
```
*(best-effort `try?` — a copy failure must not abort ledger creation; the ledger already exists.)*

- [ ] **Step 3: Build** — app-build gate → **BUILD SUCCEEDED**.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerManagementView.swift
git commit -m "feat(ios): clone-on-create — seed a new ledger's Categories & Tags from an existing one"
```

---

### Task 4: Localization + full verification

**Files:** `ios/FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings`, `ios/scripts/zh-manual.json`.

- [ ] **Step 1: Full test suite** — `cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` → all pass (incl. `ReferenceCopyTests`, `ArgsTests` count 85; parity unaffected).
- [ ] **Step 2: macOS build** — `cd ios && DEVELOPER_DIR=… xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"` → **BUILD SUCCEEDED**.
- [ ] **Step 3: Surgical zh-Hans** for the new UI strings — add to `Localizable.xcstrings` + `zh-manual.json` (mirror existing entry shape; validate JSON with `python3 -m json.tool`; do NOT run the full pipeline). New keys: `"Start from"` (从…开始), `"Blank"` (空白), `"Import from another ledger…"` (从其他账本导入…), `"Copy to another ledger…"` (复制到其他账本…), `"Import tags from…"` (导入标签，来自…), `"Import categories from…"` (导入类别，来自…), `"Copy %@ to…"` (将 %@ 复制到…), `"No other ledgers"` (没有其他账本), `"Create another ledger first."` (请先创建另一个账本。). Skip any already present.
- [ ] **Step 4: Manual sim** (via `ios-build-launch`): new-ledger "Start from" seeds categories/tags; Categories/Tags "Import from…" adds missing; row "Copy to…" copies one; re-import is a no-op.
- [ ] **Step 5: Commit** — `git add …/Localizable.xcstrings ios/scripts/zh-manual.json && git commit -m "i18n(ios): zh-Hans for cross-ledger copy"`.

---

## Self-Review
- **Coverage:** clone-on-create → Task 3; import-from (whole) + copy-to (single) → Task 2; engine `copyCategories`/`copyTags` (additive/dedup/tree/system-skip/ids+ancestors) → Task 1; i18n/tests → Tasks 1 & 4.
- **Placeholders:** none — complete engine + picker code; UI wiring shown with concrete `.sheet` blocks; per-step commands + expected results.
- **Types:** `copyCategories`/`copyTags` args `{fromLedgerId,toLedgerId,ids?}` defined in Task 1 and consumed identically in Tasks 2–3; `LedgerPickerSheet(title:onPick:)` defined in Task 2, reused in Task 3-adjacent flows; `store.ledgers`/`store.activeLedgerId` exist.

## Out of scope
Merchants (Phase 2 → global), Currencies (already global), multi-item selection UI beyond single-row "Copy to", any schema change.
