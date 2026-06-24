# Tag & Category usage counts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a live `N×` usage count on each tag (TagAdminView) and category (CategoryAdminView) row — non-pending transactions referencing that tag/category — mirroring the merchant `N×` (#274).

**Architecture:** Two pure FinchCore selectors (`tagTxCounts`, `categoryTxCounts`) keyed by id, plus a `N×` row display in each view (counts computed once per render). Category count is **direct** (no descendant rollup); split txns are attributed to their leg categories. No engine/schema/model/projection change.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest. FinchCore via `swift test`; FinchApp via `xcodebuild … -only-testing:FinchAppTests/…`.

## Global Constraints

- **No engine/schema/model/projection change** — derived live from `store.txns`.
- **Count = all non-pending** txns (consistent with merchants). **Direct** category count (no descendant rollup).
- **Splits:** a txn with split legs is attributed to its legs' `categoryId`s; otherwise to `tx.category`. Count each txn once per distinct category (Set per txn). Tags: increment each `tagId` in `tx.tags` (ids; unique per txn).
- Row `N×`: muted, monospaced, **hidden when 0**; counts computed **once per render**.
- **Must build iOS AND macOS (FinchMac).** Sim: `iPhone 17 Pro Max`. New test files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit messages; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):**
- `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` — add `tagTxCounts` + `categoryTxCounts` (after `counterpartyTxCounts`, ~line 143).

**Create (tests):**
- `ios/FinchCore/Tests/FinchCoreTests/TagCategoryCountsTests.swift`

**Modify (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift` — `N×` per tag row.
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` — `N×` per category row.

**Common run commands:**
```bash
cd /Users/blackmount8/_repository/finch/ios
swift test --filter <ClassName>                       # FinchCore
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FinchAppTests/<ClassName>
```

---

### Task 1: `tagTxCounts` + `categoryTxCounts` selectors (pure)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (add two static funcs after `counterpartyTxCounts`, which ends ~line 143, before `// MARK: cycleWindow`; match the file's 4-space indentation)
- Test: `ios/FinchCore/Tests/FinchCoreTests/TagCategoryCountsTests.swift` (create)

**Interfaces:**
- Produces:
  - `static func tagTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int]` — keyed by tag id.
  - `static func categoryTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int]` — keyed by category id; direct; split legs counted.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/TagCategoryCountsTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class TagCategoryCountsTests: XCTestCase {
    private func tx(_ id: String, category: String? = nil, tags: [String]? = nil,
                    splits: [TxSplit]? = nil, pending: Bool = false, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: "m", category: category, amount: -5, account: "a1", date: "2026-05-01",
           pending: pending, ledgerId: ledger, splits: splits, tags: tags)
    }
    private func split(_ categoryId: String?, _ amount: Double = -5) -> TxSplit {
        TxSplit(id: nil, categoryId: categoryId, amount: amount, amountBase: amount, description: nil)
    }

    // MARK: tagTxCounts

    func test_tag_counts_by_id() {
        let r = Selectors.tagTxCounts([tx("t1", tags: ["tagA"]), tx("t2", tags: ["tagA"])], "l1")
        XCTAssertEqual(r, ["tagA": 2])
    }

    func test_tag_multi_tag_txn_increments_each() {
        let r = Selectors.tagTxCounts([tx("t1", tags: ["tagA", "tagB"])], "l1")
        XCTAssertEqual(r, ["tagA": 1, "tagB": 1])
    }

    func test_tag_excludes_pending_and_other_ledger() {
        let r = Selectors.tagTxCounts(
            [tx("t1", tags: ["tagA"]), tx("t2", tags: ["tagA"], pending: true), tx("t3", tags: ["tagA"], ledger: "l2")], "l1")
        XCTAssertEqual(r, ["tagA": 1])
    }

    func test_tag_untagged_absent() {
        XCTAssertTrue(Selectors.tagTxCounts([tx("t1")], "l1").isEmpty)
    }

    // MARK: categoryTxCounts

    func test_category_direct_count() {
        let r = Selectors.categoryTxCounts([tx("t1", category: "cFood"), tx("t2", category: "cFood")], "l1")
        XCTAssertEqual(r, ["cFood": 2])
    }

    func test_category_split_legs_counted() {
        // a 2-leg txn across two categories increments both
        let r = Selectors.categoryTxCounts([tx("t1", splits: [split("cFood"), split("cFun")])], "l1")
        XCTAssertEqual(r, ["cFood": 1, "cFun": 1])
    }

    func test_category_splits_override_tx_category() {
        // when splits present, tx.category is NOT counted
        let r = Selectors.categoryTxCounts([tx("t1", category: "cIgnored", splits: [split("cFood")])], "l1")
        XCTAssertEqual(r, ["cFood": 1])
    }

    func test_category_same_category_twice_counts_once() {
        let r = Selectors.categoryTxCounts([tx("t1", splits: [split("cFood"), split("cFood")])], "l1")
        XCTAssertEqual(r, ["cFood": 1])
    }

    func test_category_excludes_pending_and_other_ledger() {
        let r = Selectors.categoryTxCounts(
            [tx("t1", category: "cFood"), tx("t2", category: "cFood", pending: true), tx("t3", category: "cFood", ledger: "l2")], "l1")
        XCTAssertEqual(r, ["cFood": 1])
    }

    func test_category_no_descendant_rollup() {
        // a child txn does NOT roll up to the parent id; only the child id is counted
        let r = Selectors.categoryTxCounts([tx("t1", category: "cChild")], "l1")
        XCTAssertEqual(r, ["cChild": 1])
        XCTAssertNil(r["cParent"])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter TagCategoryCountsTests`
Expected: FAIL to compile — `tagTxCounts`/`categoryTxCounts` undefined.

- [ ] **Step 3: Implement the selectors**

In `Selectors.swift`, after the `counterpartyTxCounts` function's closing brace (≈ line 143) and before `// MARK: cycleWindow + date helpers`, add (4-space indentation to match the file):

```swift
    /// Per-tag usage count: non-pending txns in `ledgerId` tagged with the tag.
    /// Keyed by tag id (`tx.tags` holds tag ids); absent for unused tags.
    public static func tagTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            for tagId in (t.tags ?? []) { out[tagId, default: 0] += 1 }
        }
        return out
    }

    /// Per-category usage count (DIRECT, no descendant rollup): non-pending txns in
    /// `ledgerId` whose category leg(s) reference the category. A split txn is
    /// attributed to its split legs' categoryIds; otherwise to `tx.category`. Each
    /// txn counts once per distinct category. Keyed by category id; absent for unused.
    public static func categoryTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            var cats = Set<String>()
            if let splits = t.splits, !splits.isEmpty {
                for s in splits { if let c = s.categoryId { cats.insert(c) } }
            } else if let c = t.category {
                cats.insert(c)
            }
            for c in cats { out[c, default: 0] += 1 }
        }
        return out
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter TagCategoryCountsTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Run the full FinchCore suite (no regressions)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/TagCategoryCountsTests.swift
git commit -m "feat(ios): tagTxCounts + categoryTxCounts selectors (usage counts)"
```

---

### Task 2: `N×` on tag + category rows

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift`

**Interfaces:**
- Consumes: `Selectors.tagTxCounts`, `Selectors.categoryTxCounts` (Task 1); `store.txns`, `store.activeLedgerId`.

- [ ] **Step 1: TagAdminView — compute counts once + show `N×`**

In `ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift`, replace this block:

```swift
    var body: some View {
        List {
            if store.tags.isEmpty { Text("No tags yet.").foregroundStyle(.secondary) }
            ForEach(store.tags) { tag in
                Button { renaming = tag } label: {
                    HStack {
                        Circle().fill(Color(hex: tag.color ?? "") ?? .secondary)
                            .frame(width: 12, height: 12)
                        Text(tag.name).foregroundStyle(.primary)
                    }
                }
```

with:

```swift
    var body: some View {
        let counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)
        return List {
            if store.tags.isEmpty { Text("No tags yet.").foregroundStyle(.secondary) }
            ForEach(store.tags) { tag in
                Button { renaming = tag } label: {
                    HStack {
                        Circle().fill(Color(hex: tag.color ?? "") ?? .secondary)
                            .frame(width: 12, height: 12)
                        Text(tag.name).foregroundStyle(.primary)
                        if let n = counts[tag.id], n > 0 {
                            Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityLabel("\(n) transactions")
                        }
                    }
                }
```

(Only the `var body` opening + the row `HStack` change; the rest of the file — `.swipeActions`, `.navigationTitle`, toolbar, sheets, `TagEditSheet` — is unchanged.)

- [ ] **Step 2: CategoryAdminView — compute counts once + pass to `row`**

In `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift`, replace this block:

```swift
    var body: some View {
        List {
            topLevelDropZone
            ForEach(visible) { item in row(item) }
        }
        .modifier(SearchableModifier(text: $search))
```

with:

```swift
    var body: some View {
        let counts = Selectors.categoryTxCounts(store.txns, store.activeLedgerId)
        return List {
            topLevelDropZone
            ForEach(visible) { item in row(item, counts) }
        }
        .modifier(SearchableModifier(text: $search))
```

- [ ] **Step 3: CategoryAdminView — update `row` signature**

Replace:

```swift
    @ViewBuilder private func row(_ item: FlatCategory) -> some View {
```

with:

```swift
    @ViewBuilder private func row(_ item: FlatCategory, _ counts: [String: Int]) -> some View {
```

- [ ] **Step 4: CategoryAdminView — show `N×` in the row**

Replace this block:

```swift
            Button { editing = c } label: {
                Text(c.name).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.depth < 2 {   // engine caps nesting at 3 levels
```

with:

```swift
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
```

- [ ] **Step 5: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Build macOS (FinchMac) — CI gate**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Manual verification on the simulator**

Launch (Settings › Power Tools). In **Tags**, a tag used by transactions shows `N×`; an unused one shows none. In **Categories**, a leaf category used by transactions shows `N×`; a pure grouper parent (no direct txns) shows none.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift
git commit -m "feat(ios): show per-tag and per-category transaction counts (N×)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-24-ios-tag-category-counts-design.md`):
- `tagTxCounts` (by tag id, non-pending) → Task 1. ✓
- `categoryTxCounts` (direct, splits→legs override tx.category, count once per distinct cat, non-pending) → Task 1. ✓
- `N×` on TagAdminView + CategoryAdminView rows (muted/monospaced, hidden when 0, computed once per render) → Task 2. ✓
- No engine/model/projection change; build iOS+macOS; full tests green → Task 2 steps 5-6. ✓
- Direct count / no rollup → covered by `test_category_no_descendant_rollup`. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; the edits are exact before→after blocks; sim step has concrete checks. ✓

**Type consistency:** both selectors return `[String: Int]`; consumed as `counts[id]` (`Int?`) guarded `if let n …, n > 0`. `row(_ item:, _ counts:)` signature change matches its single call site `row(item, counts)`. `TxSplit(id:categoryId:amount:amountBase:description:)` matches the struct. `Tx(... category:, splits:, tags:)` labels match the init. ✓

---

## Out of scope

Descendant rollup; sort-by-usage; tag/category color/icon changes; any non-tag/category screen.
