# Tag merge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tag merge (single + multi-select) to the Settings → Tags page, mirroring the existing category merge.

**Architecture:** Two native-only engine actions (`mergeTag` / `mergeTags`) in `FinchCore` — no web/parity impact, exactly like `mergeCategory` / `mergeCategories` — plus merge UI added to `TagsView` mirroring `CategoriesView`. The tag-specific wrinkle is that `entry_tags` is many-to-many, so the join repoint dedups via the composite-PK `INSERT OR IGNORE`; rule `actions` JSON referencing a merged-away tag is repointed too.

**Tech Stack:** Swift / SwiftUI, GRDB, FinchCore engine, XCTest.

## Global Constraints

- Engine actions are **iOS-only / native-ahead** — do **not** touch `frontend/` or the parity fixtures (mirrors `mergeCategory`).
- All writes go through `store.apply` (app) / the `Apply` chokepoint (engine); each action runs in the single transaction `Apply` already wraps.
- Survivor keeps its **own name and color**; the other tag(s) are deleted.
- No hierarchy, kind, icon, reorder, or color-merge for tags (flat/color-only).
- Design doc: `plans/ios-macos/2026-07-19-tag-merge-design.md`.

---

### Task 1: Engine — `mergeTag` / `mergeTags` actions + tests

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` (add two cases)
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Tags.swift` (handlers + merge logic)
- Test: `ios/FinchCore/Tests/FinchCoreTests/TagMergeTests.swift` (new)

**Interfaces:**
- Produces: action `mergeTag { sourceId: String, targetId: String }` and `mergeTags { sourceIds: [String], targetId: String }`, dispatched via `Apply.apply(dbQueue:action:args:)`.
- Consumes: existing `entry_tags (entry_id, tag_id)` join (composite PK, `tag_id … ON DELETE CASCADE`), `tags` table, `rules.actions` TEXT (JSON array of `{ type, … }` action objects; `add_tag`/`remove_tag` carry a `tagId`).

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/TagMergeTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

/// Tag merge repoints the entry_tags join (dedup on the composite PK), repoints
/// rule actions, and deletes the source tag(s). iOS-only — no web parity.
final class TagMergeTests: XCTestCase {
    private func freshDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(q)
        return q
    }

    /// Seed a ledger, an account, two tags (t1, t2), and a category.
    private func seed(_ q: DatabaseQueue) throws {
        try Apply.apply(dbQueue: q, action: "createLedger", args: Args([
            "id": .string("l1"), "name": .string("L"), "baseCurrency": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "ledgerId": .string("l1"), "id": .string("a1"), "name": .string("A"), "type": .string("cash"), "currency": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("Food")]))
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t2"), "ledgerId": .string("l1"), "name": .string("food")]))
    }

    /// Add a transaction with the given tag ids.
    private func addTx(_ q: DatabaseQueue, id: String, tags: [String]) throws {
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string(id), "date": .string("2026-05-01"), "skipRules": .bool(true),
            "tagIds": .array(tags.map { .string($0) })]))
        XCTAssertNotNil(eid)
    }

    private func tagIds(_ q: DatabaseQueue, entryMerchant: String) throws -> [String] {
        try q.read { db in
            try String.fetchAll(db, sql: """
                SELECT et.tag_id FROM entry_tags et
                JOIN entries e ON e.id = et.entry_id
                WHERE e.description = ? ORDER BY et.tag_id
                """, arguments: [entryMerchant])
        }
    }

    func test_mergeTag_repointsJoin_andDeletesSource() throws {
        let q = try freshDB(); try seed(q)
        try addTx(q, id: "x", tags: ["t2"])   // tagged with the source only
        try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t2"), "targetId": .string("t1")]))
        XCTAssertEqual(try tagIds(q, entryMerchant: "x"), ["t1"])   // repointed
        try q.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM tags WHERE id = 't2'"))   // source gone
        }
    }

    func test_mergeTag_dedups_whenEntryHasBoth() throws {
        let q = try freshDB(); try seed(q)
        try addTx(q, id: "both", tags: ["t1", "t2"])   // has BOTH source and target
        try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t2"), "targetId": .string("t1")]))
        XCTAssertEqual(try tagIds(q, entryMerchant: "both"), ["t1"])   // exactly one row, no dup
    }

    func test_mergeTag_repointsRuleActions() throws {
        let q = try freshDB(); try seed(q)
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "ledgerId": .string("l1"), "id": .string("r1"), "name": .string("R"),
            "conditions": .array([.object(["field": .string("merchant"), "op": .string("contains"), "value": .string("z")])]),
            "actions": .array([.object(["type": .string("add_tag"), "tagId": .string("t2")])])]))
        try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t2"), "targetId": .string("t1")]))
        try q.read { db in
            let actions = try String.fetchOne(db, sql: "SELECT actions FROM rules WHERE id = 'r1'") ?? ""
            XCTAssertTrue(actions.contains("t1"))
            XCTAssertFalse(actions.contains("t2"))
        }
    }

    func test_mergeTags_manyIntoOne() throws {
        let q = try freshDB(); try seed(q)
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t3"), "ledgerId": .string("l1"), "name": .string("FOOD")]))
        try addTx(q, id: "a", tags: ["t2"]); try addTx(q, id: "b", tags: ["t3"])
        try Apply.apply(dbQueue: q, action: "mergeTags", args: Args([
            "sourceIds": .array([.string("t2"), .string("t3")]), "targetId": .string("t1")]))
        XCTAssertEqual(try tagIds(q, entryMerchant: "a"), ["t1"])
        XCTAssertEqual(try tagIds(q, entryMerchant: "b"), ["t1"])
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE id IN ('t2','t3')"), 0)
        }
    }

    func test_validation() throws {
        let q = try freshDB(); try seed(q)
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t1"), "targetId": .string("t1")])))   // self
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("nope"), "targetId": .string("t1")])))   // missing
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTags", args: Args(["sourceIds": .array([]), "targetId": .string("t1")])))   // empty
        // one bad id in a batch aborts the whole batch — t2 must survive
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTags", args: Args([
            "sourceIds": .array([.string("t2"), .string("nope")]), "targetId": .string("t1")])))
        try q.read { db in XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT id FROM tags WHERE id = 't2'")) }
    }
}
```

> Verify the seed helpers against the repo's existing test seeds (`TestSeed` / `ApplyTests`) — reuse their exact `createLedger` / `createAccount` / `createRule` arg shapes if they differ from the above; the assertions are what matter.

- [ ] **Step 2: Run the tests — verify they fail**

Run: `cd ios && swift test --filter TagMergeTests`
Expected: FAIL (`mergeTag` / `mergeTags` are unknown actions).

- [ ] **Step 3: Add the `ActionName` cases**

In `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift`, under the tags group:

```swift
    // --- tags (5) ---
    case createTag
    case updateTag
    case deleteTag
    case mergeTag
    case mergeTags
```

- [ ] **Step 4: Implement the merge handlers**

In `ios/FinchCore/Sources/FinchCore/Store/Domain/Tags.swift`, register the handlers and add the logic:

```swift
    public static let handlers: [ActionName: Apply.Handler] = [
        .createTag: createTag,
        .updateTag: updateTag,
        .deleteTag: deleteTag,
        .mergeTag: mergeTag,
        .mergeTags: mergeTags,
    ]

    // MARK: merge

    /// Combine `sourceId` into `targetId`: repoint the entry_tags join (dedup on
    /// the composite PK) and any rule actions, then delete the source tag (its
    /// leftover join rows cascade away). One atomic transaction (Apply wraps).
    static func mergeTag(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceId: String; let targetId: String }
        let a = try args.to(A.self)
        try validateMerge(db, source: a.sourceId, target: a.targetId)
        try mergeOne(db, source: a.sourceId, target: a.targetId)
        try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [a.sourceId])
    }

    /// Combine many `sourceIds` into `targetId` in one transaction. All sources
    /// are validated up-front, so a bad one aborts the whole set with nothing merged.
    static func mergeTags(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceIds: [String]; let targetId: String }
        let a = try args.to(A.self)
        if a.sourceIds.isEmpty {
            throw I18nError("error.invalidArgs", [:], "mergeTags requires at least one source")
        }
        for source in a.sourceIds { try validateMerge(db, source: source, target: a.targetId) }
        for source in a.sourceIds { try mergeOne(db, source: source, target: a.targetId) }
        for source in a.sourceIds {
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [source])
        }
    }

    /// Guards for a single source→target merge (self, existence). Read-only.
    private static func validateMerge(_ db: Database, source: String, target: String) throws {
        if source == target {
            throw I18nError("error.tag.mergeSelf", [:], "Cannot merge a tag into itself")
        }
        for id in [source, target] where try Int.fetchOne(db, sql: "SELECT 1 FROM tags WHERE id = ?", arguments: [id]) == nil {
            throw I18nError("error.notFound.tag", [:], "Tag does not exist")
        }
    }

    /// Repoint the join + rule actions from `source` to `target`. No validation,
    /// no delete. Runs inside the caller's transaction.
    private static func mergeOne(_ db: Database, source: String, target: String) throws {
        // 1) Repoint the join, dedup via the composite PK (entry with both → target once).
        try db.execute(sql: """
            INSERT OR IGNORE INTO entry_tags (entry_id, tag_id)
            SELECT entry_id, ? FROM entry_tags WHERE tag_id = ?
            """, arguments: [target, source])
        // (Source join rows remain; the caller's DELETE of the tag cascades them away.)

        // 2) Repoint rule actions that add/remove the source tag.
        for row in try Row.fetchAll(db, sql: "SELECT id, actions FROM rules WHERE actions LIKE ?", arguments: ["%\(source)%"]) {
            guard let raw = row["actions"] as String?, let data = raw.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            var changed = false
            var seenTagActions = Set<String>()   // "type|tagId" — drop duplicate add/remove of the same tag
            var rewritten: [[String: Any]] = []
            for var act in parsed {
                let type = act["type"] as? String
                if type == "add_tag" || type == "remove_tag", let tid = act["tagId"] as? String {
                    if tid == source { act["tagId"] = target; changed = true }
                    let key = "\(type ?? "")|\(act["tagId"] as? String ?? "")"
                    if !seenTagActions.insert(key).inserted { changed = true; continue }   // duplicate — drop
                }
                rewritten.append(act)
            }
            if changed,
               let out = try? JSONSerialization.data(withJSONObject: rewritten),
               let json = String(data: out, encoding: .utf8),
               let id = row["id"] as String? {
                try db.execute(sql: "UPDATE rules SET actions = ?, updated_at = datetime('now') WHERE id = ?", arguments: [json, id])
            }
        }
    }
```

> If `Tags.swift` doesn't already `import Foundation` (for `JSONSerialization`), add it.

- [ ] **Step 5: Run the tests — verify they pass**

Run: `cd ios && swift test --filter TagMergeTests`
Expected: PASS (all cases). Then run the full suite to catch regressions:
Run: `cd ios && swift test`
Expected: PASS (parity gates unaffected — the new actions aren't in `WRITE_SEQUENCE`).

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/ActionName.swift \
        ios/FinchCore/Sources/FinchCore/Store/Domain/Tags.swift \
        ios/FinchCore/Tests/FinchCoreTests/TagMergeTests.swift
git commit -m "feat(ios): mergeTag/mergeTags engine actions (dedup join + repoint rules)"
```

---

### Task 2: UI — Tag merge in `TagsView` (single + multi-select)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift`

**Interfaces:**
- Consumes: `store.apply(.mergeTag, …)` / `store.apply(.mergeTags, …)` (Task 1); `Selectors.tagTransactions(_:_:_:)` and `Selectors.tagTxCounts(_:_:)`; the free `mergeImpactMessage(txCount:)` (`PowerTools/CategoryMergeImpact.swift`); `TagRow`, `Color(hex:)`.
- Mirrors: `CategoriesView`'s merge (`mergingFrom` / `pendingMerge` / `mergeChoice` single flow; `isSelecting` / `selected` / `mergeManySurvivorChoice` multi flow), minus the tree/kind/hierarchy parts.

> **Note (branch reconciliation):** if PR #522 (tags modularize) has already merged into the base, the tag rows use `TagSwatch(hex:)`; otherwise they use the inline `Circle().fill(Color(hex: tag.color ?? "") ?? .secondary).frame(width: 26, height: 26)` currently in `TagsView.row`. Use whichever the base has for the merge target-picker swatch — both render identically. The steps below use the inline `Circle` form; swap to `TagSwatch(hex:)` if present.

- [ ] **Step 1: Add merge state + the `MergePair` type**

At the top of `TagsView.swift` (after the imports), add:

```swift
/// A chosen (initiating A, target B) pair for a merge; the alert picks which survives.
private struct TagMergePair: Identifiable {
    let a: TagRow   // the row the merge was started from
    let b: TagRow   // the picked other tag
    var id: String { a.id + "|" + b.id }
}
```

In `struct TagsView`, add these `@State` properties alongside the existing ones:

```swift
    @State private var mergingFrom: TagRow?              // → target-picker sheet
    @State private var pendingMerge: TagMergePair?       // staged in the sheet, promoted on its dismiss
    @State private var mergeChoice: TagMergePair?        // → keep-which-name alert
    @State private var isSelecting = false               // ⋯ → Merge multi-select mode
    @State private var selected: Set<String> = []        // ids ticked in select mode
    @State private var mergeManySurvivorChoice: [TagRow]? // → keep-which-name dialog
```

- [ ] **Step 2: Replace the toolbar with a merge-aware one**

Replace the current `.toolbar { ToolbarItem(placement: .primaryAction) { Button { creating = true } … } }` with:

```swift
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge (\(selected.count))") {
                        mergeManySurvivorChoice = selected.compactMap { id in store.tags.first { $0.id == id } }
                            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    }
                    .disabled(selected.count < 2)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { isSelecting = false; selected = [] } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New tag")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { isSelecting = true; selected = [] } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
                }
            }
        }
```

- [ ] **Step 3: Add the tick + "Merge…" affordances to the row**

In `row(_ tag:_ counts:)`, wrap the leading swatch/name/count `Button` in an `HStack` that shows a selection tick in select mode, and make the tap toggle selection while selecting. Replace the row body's outer `Button { selectedTagId = tag.id } label: { HStack(spacing: 10) { … } }` with:

```swift
        HStack(spacing: 8) {
            if isSelecting {
                Image(systemName: selected.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected.contains(tag.id) ? Color.accentColor : .secondary)
            }
            Button {
                if isSelecting {
                    if selected.contains(tag.id) { selected.remove(tag.id) } else { selected.insert(tag.id) }
                } else {
                    selectedTagId = tag.id
                }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: tag.color ?? "") ?? .secondary).frame(width: 26, height: 26)
                    Text(tag.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let n = counts[tag.id], n > 0 {
                        Text("\(n)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                            .accessibilityLabel("\(n) transactions")
                    }
                    if !isSelecting {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityAddTraits(isSelecting && selected.contains(tag.id) ? [.isSelected] : [])
```

Add **"Merge…"** to the row's existing `.swipeActions` (between Edit and Delete) and `.contextMenu`:

```swift
            Button { mergingFrom = tag } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }.tint(.orange)
```
(and in the context menu:)
```swift
            Button { mergingFrom = tag } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
```

- [ ] **Step 4: Add the target-picker sheet + keep-which-name alerts**

On the `List` (next to the existing `.sheet`/`.alert` modifiers), add:

```swift
        // Single merge: pick a target, then the keep-which-name alert (staged via
        // onDismiss so chaining dismiss+present doesn't drop the alert).
        .sheet(item: $mergingFrom, onDismiss: {
            if let p = pendingMerge { mergeChoice = p; pendingMerge = nil }
        }) { a in
            NavigationStack {
                List {
                    let others = store.tags.filter { $0.id != a.id }
                    if others.isEmpty {
                        ContentUnavailableView("No other tags", systemImage: "arrow.triangle.merge",
                                               description: Text("There's nothing to merge \(a.name) with yet."))
                    } else {
                        ForEach(others) { b in
                            Button { pendingMerge = TagMergePair(a: a, b: b); mergingFrom = nil } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(hex: b.color ?? "") ?? .secondary).frame(width: 26, height: 26)
                                    Text(b.name).foregroundStyle(.primary)
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
```

- [ ] **Step 5: Add the dispatch + count helpers**

Add these methods to `TagsView` (next to `delete(_:)`):

```swift
    /// Choice-independent union of transactions referencing either tag.
    private func mergeTxCount(_ a: TagRow, _ b: TagRow) -> Int {
        let ledger = store.activeLedgerId
        let ids = Set(Selectors.tagTransactions(store.txns, a.id, ledger).map(\.id))
            .union(Selectors.tagTransactions(store.txns, b.id, ledger).map(\.id))
        return ids.count
    }

    private func merge(source: TagRow, target: TagRow) {
        errorMessage = nil; mergeChoice = nil
        do { try store.apply(.mergeTag, Args(["sourceId": .string(source.id), "targetId": .string(target.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    private func mergeManyTxCount(_ tagRows: [TagRow]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for t in tagRows { ids.formUnion(Selectors.tagTransactions(store.txns, t.id, ledger).map(\.id)) }
        return ids.count
    }

    /// Merge every selected tag except the survivor into it, atomically.
    private func mergeMany(keeping survivor: TagRow, from all: [TagRow]) {
        errorMessage = nil; mergeManySurvivorChoice = nil
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        do {
            try store.apply(.mergeTags, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false; selected = []
        } catch { errorMessage = i18nMessage(error) }
    }
```

- [ ] **Step 6: Build both platforms**

Run: `cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate`
Run: `xcodebuild -project ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.
Run: `xcodebuild -project ios/FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift
git commit -m "feat(ios): Tag merge UI in TagsView (single + multi-select)"
```

---

## Manual verification (for the PR body)

1. Tags page → swipe a tag → **Merge…** → pick a target → keep either name → the source tag is gone and its transactions now carry the target tag.
2. A transaction that had **both** tags shows the target once (no duplicate).
3. ⋯ → **Merge** → tick 3 tags → **Merge (3)** → pick survivor → all combined; select mode exits.
4. **Merge (N)** is disabled below 2 ticked; ✕ exits select mode.
5. A rule that added a merged-away tag now adds the survivor.
6. macOS: single + multi-select merge both work.

## Self-Review

- **Spec coverage:** engine `mergeTag`/`mergeTags` with dedup + rules repoint (Task 1); single + multi-select UI mirroring Categories (Task 2); no web/parity changes (Global Constraints); non-goals respected (no color merge, saved searches untouched). ✓
- **Type consistency:** `TagMergePair`, `merge(source:target:)`, `mergeMany(keeping:from:)`, `mergeTxCount`, `mergeManyTxCount` names are used consistently across steps; action arg keys (`sourceId`/`targetId`/`sourceIds`) match Task 1. ✓
- **Placeholders:** none — all steps carry concrete code. ✓
