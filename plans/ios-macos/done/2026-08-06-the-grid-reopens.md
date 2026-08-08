# The Grid Reopens — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the grid a page of its own, and make a grid purchase editable — tap any row of one and the whole thing reopens.

**Architecture:** The grid moves out of the bottom of page 1 into a pushed page 2, in both sheets. Page 1 selects cards and categories; page 2 divides the money and owns ✓. The Edit sheet detects `groupId` itself and rebuilds the whole grid from the saved rows, so none of the fourteen call sites that construct it change.

**Tech Stack:** Swift 5.9 / SwiftUI (`NavigationStack` + `navigationDestination`) / GRDB, XCTest. Package `ios/FinchCore`, app target `ios/FinchApp`.

## Global Constraints

- **Branch:** `feat/grid-reopen`, stacked on `fix/typed-amounts` (PR #736). **PR #736 must merge first** — this plan reads the per-cell `TxSplit.origAmount` it introduces. If #736 is rewritten, rebase before continuing.
- **PRs target `feat/frontend`.** Never `main`.
- **No `Co-Authored-By` trailer in commits.**
- **iOS only.** No changes under `frontend/`.
- **Do not regenerate the parity fixture.**
- **Build:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` **and** `PATH="$DEVELOPER_DIR/usr/bin:$PATH"`.
- **Simulator:** `ios-finch-splits`. Never touch a sim with another name.
- **The gate has fast and full modes.** `./scripts/ci-local.sh --all` runs FAST and skips the 33 UI tests and the watch build. Before pushing, run `./scripts/ci-local.sh --full --all` and require `all checks passed`.
- **The generated project goes stale across branches.** `FinchApp.xcodeproj` is gitignored; run `xcodegen generate` after any branch switch or a build fails on unrelated missing types.
- **This plan adds exactly two user-facing strings** (`"Next"` and the dropped-receipt warning). Adding a string is a defined procedure — see "Adding a UI string" below. Do not add a third without following it.
- After any `xcodebuild` run that is not part of the l10n procedure, discard catalog churn:
  `git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings`

### Adding a UI string

The catalog is BUILT, not edited. `ios/scripts/build-xcstrings.ts` composes it from
`scripts/extracted-keys.json` (what the compiler found) and `scripts/zh-manual.json`
(hand-authored zh). The i18n guard diffs the catalog against HEAD, so an
intentional change fails the gate until it is committed. Full procedure, run from
`ios/`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
LOC=$(mktemp -d)                     # a FRESH directory every time — a reused one
                                     # lets a failed export leave a stale xliff
xcodebuild -exportLocalizations -project FinchApp.xcodeproj -scheme FinchApp \
  -localizationPath "$LOC" -exportLanguage zh-Hans
bun run scripts/xliff-keys.ts "$LOC" > scripts/extracted-keys.json
# add the zh-Hans value to scripts/zh-manual.json BY HAND, in place — do not
# re-serialise the file (`json.dump(sort_keys=True)` rewrites all 739 lines)
bun run scripts/build-xcstrings.ts
```

Then commit `extracted-keys.json`, `zh-manual.json` and the rebuilt
`Localizable.xcstrings` **together**.

---

## Background: what exists, and what is actually missing

### The grid already works — it is just buried

`PurchaseGridSection` is built, tested and wired. Split the account across 2+
cards **and** the category across 2+ categories in the Add sheet and it appears —
as extra `Section`s at the bottom of the same long form
(`AddTransactionSheet.swift:390`), under the date, note, tags and receipt rows.
Its own doc comment already calls it *"Page 2's grid"*. The page was never built.

`PurchaseFlow.page2(accounts:categories:)` returns `.notNeeded` / `.list` /
`.grid` and is used only as a *decision*, never as navigation.

### The Edit sheet has no grid at all

No `PurchaseGridSection`, no `gridAlloc`. Tap any row of a grid purchase and you
see that one card, as though the rest of the purchase did not exist.

### Routing is free

All fourteen call sites construct `EditTransactionSheet(txn:)` and nothing else:

```
ActivityTab, AccountDetailView, BudgetDetailView, AdaptiveShell,
TransactionDetailView, TagDetailView, CategoryDetailView, CounterpartyDetailView,
TabChromeVC, RootTabBarController, TxListDetailVC, AccountDetailVC,
ActivityFeedVC, BudgetDetailVC
```

So if the sheet detects `txn.groupId != nil` itself, **no call site changes.**
This was the part expected to be expensive; it is not.

### The decisions this plan implements (settled — do not relitigate)

1. **Two pages.** Page 1 selects; page 2 divides. Grid only — a one-axis split
   already has its own screen (`SearchablePickerRow.swift:92` presents a picker
   sheet with the split editor inside), so lists are served.
2. **✓ lives on page 2** while a grid is active; page 1 shows "Next ›".
3. **Page 2 opens pre-filled from both margins** (card share × category share ÷
   total), so it is balanced on arrival and both sets of numbers the user already
   typed are honoured. It is a starting point, not an inference the app commits
   to — every cell is editable and any cell can be crossed out.
4. **Going back and adding a card leaves typed cells alone.** New cells float and
   take the remainder.
5. **Edit self-detects `groupId`** and rebuilds the whole grid.
6. **Page 1 shows the TAPPED row's** merchant, date, note, tags and status.
   Saving normalises every card in the purchase — they are one purchase, so they
   should agree. This falls out of `saveTransaction` writing one header to every
   row it touches; no extra work.
7. **Save targets the group id**, so rows match by card and keep their ids,
   receipts and reconcile marks (`SaveTransaction.swift:167-186`).
8. **Dropping a card deletes its transaction.** If it has a receipt, warn at save
   naming what goes, then unlink the file.

### One decision derived while planning, not from the interview

**A reopened grid shows its Amount field.** Today `isSplit` hides Amount, because
a category split's total *is* the amount. A grid cannot do that: the settled rule
is "the amount is the target and ✓ is blocked until the cells reach it", and with
no Amount field there is no target and no way out of a blocked state — the user
could never raise a purchase's total. So a grid gets its Amount row back, and one
rule holds in both sheets. The cost is one more layout branch in a form that
already has three.

---

## File structure

| File | Responsibility after this plan |
|---|---|
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseCells.swift` | Gains `seedGrid(accounts:categories:total:)`, `reseedGrid(_:accounts:categories:total:)`, `seedGrid(from:)` and `GridSeed` — every grid decision, pure and testable without a view. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseGridPage.swift` (new) | Page 2: the existing `PurchaseGridSection` in a `Form`, with ✓ gated on balance. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` | Routes to page 2 instead of appending sections. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` | Detects a group, rebuilds the grid, saves against the group id, warns about dropped receipts. |
| `ios/FinchApp/Sources/FinchShared/FinchStore+ViewHelpers.swift` | `unlinkOrphanedAttachments(relPaths:)` — the app layer is the only one that can remove files. |
| `ios/FinchApp/Tests/FinchAppTests/GridSeedTests.swift` (new) | Seeding, re-seeding and reopening. |
| `ios/FinchApp/Tests/FinchAppTests/GridReopenTests.swift` (new) | Reopening a saved group end to end, through the engine. |

---

## Task 1: Page 2 opens filled in

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseCells.swift` — append to `enum PurchaseFlow`
- Test: `ios/FinchApp/Tests/FinchAppTests/GridSeedTests.swift` (new)

**Interfaces:**
- Consumes: `SplitAllocation` (`tick`, `setAmount`, `rows`, `allocated`, `round2`), `PurchaseFlow.cellKey(account:category:)`, `PurchaseFlow.isBalanced(_:)`.
- Produces:
  - `PurchaseFlow.seedGrid(accounts:categories:total:) -> SplitAllocation`
  - `PurchaseFlow.reseedGrid(_:accounts:categories:total:) -> SplitAllocation`
  - Both take `[(id: String?, amount: Double)]` — the exact shape `SplitAllocation.payload` returns, so a caller passes `accountAlloc.payload` straight in.

- [ ] **Step 1: Write the failing tests.** Create `ios/FinchApp/Tests/FinchAppTests/GridSeedTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

/// What page 2 shows when you arrive, and what it keeps when you come back.
final class GridSeedTests: XCTestCase {

    private func amount(_ a: SplitAllocation, _ key: String) -> Double {
        a.rows.first { $0.id == key }?.amount ?? .nan
    }

    private let cards: [(id: String?, amount: Double)] = [(id: "a1", amount: 60), (id: "a2", amount: 40)]
    private let cats: [(id: String?, amount: Double)] = [(id: "c1", amount: 70), (id: "c2", amount: 30)]

    /// Both sets of numbers the user already typed are honoured, so the grid
    /// opens balanced and ✓ is live at once. Starting empty would throw the
    /// margins away and demand four more entries for a 2×2 — twelve for a 3×4.
    func test_pageTwoOpensFilledFromBothMargins() {
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 100)
        XCTAssertEqual(g.rows.count, 4)
        XCTAssertEqual(amount(g, "a1|c1"), 42, accuracy: 0.001)   // 60 × 70 / 100
        XCTAssertEqual(amount(g, "a1|c2"), 18, accuracy: 0.001)
        XCTAssertEqual(amount(g, "a2|c1"), 28, accuracy: 0.001)
        XCTAssertEqual(amount(g, "a2|c2"), 12, accuracy: 0.001)
        XCTAssertTrue(PurchaseFlow.isBalanced(g))
    }

    /// N independent roundings do not generally sum to the total, so the last
    /// cell absorbs the residue — the same trick `redistribute` uses on its final
    /// floating row and the engine on its final leg.
    func test_anAwkwardSplitStillSumsExactly() {
        let thirds: [(id: String?, amount: Double)] = [
            (id: "a1", amount: 33.33), (id: "a2", amount: 33.33), (id: "a3", amount: 33.34),
        ]
        let halves: [(id: String?, amount: Double)] = [(id: "c1", amount: 50), (id: "c2", amount: 50)]
        let g = PurchaseFlow.seedGrid(accounts: thirds, categories: halves, total: 100)
        XCTAssertEqual(g.rows.count, 6)
        XCTAssertEqual(g.allocated, 100, accuracy: 0.001)
        XCTAssertTrue(PurchaseFlow.isBalanced(g))
    }

    /// Uncategorised is a real column: a nil category is a nil leg, not an
    /// absent one, and its key must round-trip.
    func test_anUncategorisedColumnIsSeededLikeAnyOther() {
        let withNil: [(id: String?, amount: Double)] = [(id: "c1", amount: 70), (id: nil, amount: 30)]
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: withNil, total: 100)
        XCTAssertEqual(amount(g, PurchaseFlow.cellKey(account: "a1", category: nil)), 18, accuracy: 0.001)
    }

    /// Going back to page 1 and adding a card must not disturb what was typed.
    /// The new cells float, so they take the remainder rather than fighting the
    /// figures the user set.
    func test_addingACardLeavesTypedCellsAlone() {
        var g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 100)
        g.setAmount("a1|c1", 50)          // the user corrects one cell
        g.setAmount("a1|c2", 10)

        let three = cards + [(id: "a3", amount: 0)]
        let back = PurchaseFlow.reseedGrid(g, accounts: three, categories: cats, total: 100)

        XCTAssertEqual(amount(back, "a1|c1"), 50, accuracy: 0.001, "what the user typed still stands")
        XCTAssertEqual(amount(back, "a1|c2"), 10, accuracy: 0.001)
        XCTAssertEqual(back.rows.count, 6, "the new card brought two cells")
        XCTAssertEqual(back.allocated, 100, accuracy: 0.001, "and they absorbed the rest")
    }

    /// Removing a category on page 1 takes its cells with it.
    func test_removingACategoryDropsItsCells() {
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 100)
        let back = PurchaseFlow.reseedGrid(g, accounts: cards,
                                           categories: [(id: "c1", amount: 100)], total: 100)
        XCTAssertEqual(back.rows.count, 2)
        XCTAssertFalse(back.isTicked("a1|c2"))
    }

    /// An empty grid seeds from the margins rather than merging with nothing.
    func test_reseedingAnEmptyGridIsJustSeeding() {
        let back = PurchaseFlow.reseedGrid(SplitAllocation(total: 0),
                                           accounts: cards, categories: cats, total: 100)
        XCTAssertEqual(amount(back, "a1|c1"), 42, accuracy: 0.001)
        XCTAssertTrue(PurchaseFlow.isBalanced(back))
    }

    /// No amount yet means nothing to divide — seeding must not divide by zero.
    func test_seedingWithNoTotalProducesEmptyCells() {
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 0)
        XCTAssertTrue(g.rows.isEmpty)
    }
}
```

- [ ] **Step 2: Run them and record the failure.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests/GridSeedTests test 2>&1 | grep -E "error:|passed|Executed"
```
Expected: does not compile — `seedGrid` and `reseedGrid` do not exist.

- [ ] **Step 3: Implement both.** Append inside `enum PurchaseFlow` in `PurchaseCells.swift`, before its closing brace:

```swift
    /// Page 2's starting point: every cell filled from both margins,
    /// `cell(card, category) = card's share × category's share ÷ total`.
    ///
    /// **This does not contradict the reason the grid exists.** Two sets of
    /// margins genuinely do NOT determine the cells — 60/0/10/30 and
    /// 42/18/28/12 share the same margins — which is why every cell here stays
    /// editable and any of them can be crossed out. What the margins DO give is
    /// a starting point that is balanced on arrival, so ✓ is live immediately
    /// and the numbers already typed on page 1 are honoured rather than thrown
    /// away. Opening empty would demand four more entries for a 2×2 and twelve
    /// for a 3×4.
    static func seedGrid(accounts: [(id: String?, amount: Double)],
                         categories: [(id: String?, amount: Double)],
                         total: Double) -> SplitAllocation {
        var out = SplitAllocation(total: total)
        guard total > 0, !accounts.isEmpty, !categories.isEmpty else { return out }

        var cells: [(key: String, amount: Double)] = []
        for a in accounts {
            for c in categories {
                cells.append((cellKey(account: a.id ?? "", category: c.id),
                              SplitAllocation.round2(a.amount * c.amount / total)))
            }
        }
        // N independent roundings will not generally sum to the total, so the
        // last cell absorbs the residue — the same trick `redistribute` uses on
        // its final floating row, and the engine on its final leg.
        if let last = cells.indices.last {
            let others = cells.dropLast().reduce(0) { $0 + $1.amount }
            cells[last].amount = SplitAllocation.round2(total - others)
        }
        for cell in cells {
            out.tick(cell.key)
            out.setAmount(cell.key, cell.amount)
        }
        return out
    }

    /// Coming back to page 2 after changing the selection on page 1.
    ///
    /// Cells that survive keep exactly what the user typed. Cells that are new
    /// arrive UNPINNED, so `redistribute` hands them whatever is left instead of
    /// them fighting the figures already set. Cells whose card or category left
    /// the selection simply are not rebuilt.
    static func reseedGrid(_ current: SplitAllocation,
                           accounts: [(id: String?, amount: Double)],
                           categories: [(id: String?, amount: Double)],
                           total: Double) -> SplitAllocation {
        guard !current.rows.isEmpty else {
            return seedGrid(accounts: accounts, categories: categories, total: total)
        }
        var out = SplitAllocation(total: total)
        for a in accounts {
            for c in categories {
                let key = cellKey(account: a.id ?? "", category: c.id)
                out.tick(key)                                   // unpinned — floats
                if let prior = current.rows.first(where: { $0.id == key }) {
                    out.setAmount(key, prior.amount)            // typed before — hold it
                }
            }
        }
        return out
    }
```

- [ ] **Step 4: Run the tests — all seven must pass.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests/GridSeedTests test 2>&1 | grep -E "error:|Executed [0-9]+ test"
```
Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: page 2 opens filled in from both margins

A grid opened empty, so the card and category amounts just typed on page 1 were
thrown away and a 3x4 wanted twelve fresh entries. It now starts at
card share x category share / total — balanced on arrival, so the save is live
immediately.

This does not contradict why the grid exists: two sets of margins genuinely do
not determine the cells, which is why every cell stays editable and any can be
crossed out. The margins give a starting point, not an inference.

Coming back after adding a card keeps what was typed and lets the new cells
float, so they take the remainder rather than fighting the figures already set."
```

---

## Task 2: A saved grid can be turned back into its cells

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseCells.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/GridSeedTests.swift` (append)

**Interfaces:**
- Consumes: `Tx.account`, `Tx.category`, `Tx.splits`, `Tx.amount`, `Tx.nativeAmount`, `Tx.currency`; `TxSplit.categoryId`, `.amountBase`, `.origAmount`, `.origCurrency` (**from PR #736**).
- Produces:
  - `PurchaseFlow.GridSeed` — `alloc: SplitAllocation`, `accountIds: [String]`, `categoryIds: [String?]`, `currency: String?`
  - `PurchaseFlow.seedGrid(from rows: [Tx]) -> GridSeed`

- [ ] **Step 1: Write the failing tests.** Append inside `GridSeedTests`, before its closing brace:

```swift
    // MARK: reopening a saved group

    private func gridRow(_ id: String, account: String, group: String,
                         cells: [(String?, Double)],
                         origCurrency: String? = nil) -> Tx {
        let total = cells.reduce(0) { $0 + $1.1 }
        return Tx(id: id, merchant: "Market", amount: -total, account: account,
                  date: "2026-06-01", ledgerId: "l1",
                  currency: origCurrency, nativeAmount: origCurrency == nil ? nil : -total,
                  entryId: "e-\(id)", groupId: group,
                  splits: cells.count < 2 ? nil : cells.map {
                      TxSplit(categoryId: $0.0, amount: -$0.1, amountBase: -$0.1,
                              origAmount: origCurrency == nil ? nil : -$0.1,
                              origCurrency: origCurrency)
                  })
    }

    /// The whole purchase comes back, not the row that was tapped.
    func test_aSavedGridReopensAsItsCells() {
        let rows = [
            gridRow("p1", account: "a1", group: "g1", cells: [("c1", 40), ("c2", 20)]),
            gridRow("p2", account: "a2", group: "g1", cells: [("c1", 30), ("c2", 10)]),
        ]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(seed.accountIds, ["a1", "a2"])
        XCTAssertEqual(seed.categoryIds.map { $0 ?? "" }, ["c1", "c2"])
        XCTAssertEqual(amount(seed.alloc, "a1|c1"), 40, accuracy: 0.001)
        XCTAssertEqual(amount(seed.alloc, "a2|c2"), 10, accuracy: 0.001)
        XCTAssertEqual(seed.alloc.total, 100, accuracy: 0.001, "the purchase, not the tapped card")
        XCTAssertTrue(PurchaseFlow.isBalanced(seed.alloc))
    }

    /// A foreign purchase reopens showing the figures the user TYPED. Falling
    /// back to the base amounts would show back-converted ones, which drift by a
    /// cent on awkward rates — and saving would bake the drift in as the truth.
    func test_aForeignGridReopensInThePurchaseCurrency() {
        let rows = [
            gridRow("p1", account: "a1", group: "g1", cells: [("c1", 40), ("c2", 20)], origCurrency: "EUR"),
            gridRow("p2", account: "a2", group: "g1", cells: [("c1", 30), ("c2", 10)], origCurrency: "EUR"),
        ]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(seed.currency, "EUR")
        XCTAssertEqual(amount(seed.alloc, "a1|c1"), 40, accuracy: 0.001, "€40 as typed")
    }

    /// A card that bought exactly one category has no `splits` array — the
    /// projection puts the category on the row itself. It is still a cell.
    func test_aCardWithOneCategoryStillContributesItsCell() {
        var single = gridRow("p2", account: "a2", group: "g1", cells: [("c1", 40)])
        single.category = "c1"
        let rows = [gridRow("p1", account: "a1", group: "g1", cells: [("c1", 40), ("c2", 20)]), single]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(amount(seed.alloc, "a2|c1"), 40, accuracy: 0.001)
        XCTAssertNil(seed.alloc.rows.first { $0.id == "a2|c2" }, "it bought nothing there")
        XCTAssertEqual(seed.alloc.total, 100, accuracy: 0.001)
    }

    /// Reopening must not renumber anything: seeded rows arrive pinned, so
    /// merely opening the sheet cannot re-divide the purchase.
    func test_reopeningDoesNotRedivideThePurchase() {
        let rows = [
            gridRow("p1", account: "a1", group: "g1", cells: [("c1", 99), ("c2", 1)]),
            gridRow("p2", account: "a2", group: "g1", cells: [("c1", 50), ("c2", 50)]),
        ]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(amount(seed.alloc, "a1|c2"), 1, accuracy: 0.001, "a lopsided cell stays lopsided")
        XCTAssertTrue(seed.alloc.rows.allSatisfy(\.pinned))
    }
```

- [ ] **Step 2: Run and record the failure.** Same command as Task 1 Step 2. Expected: does not compile — `seedGrid(from:)` does not exist.

- [ ] **Step 3: Implement.** Append inside `enum PurchaseFlow`:

```swift
    /// Everything page 1 and page 2 need to reopen a saved grid.
    struct GridSeed {
        var alloc: SplitAllocation
        var accountIds: [String]
        var categoryIds: [String?]
        /// The currency the purchase was ENTERED in, when that was not the
        /// ledger base. `nil` means it was.
        var currency: String?
    }

    /// Rebuild the grid a saved group came from.
    ///
    /// A grid purchase is several transactions linked by `groupId` — one per
    /// card, each carrying its own category legs — so reopening means turning
    /// them back into one flat cell allocation.
    ///
    /// **Amounts come back in the PURCHASE's currency**, from the per-cell
    /// `origAmount` the engine records. Falling back to the base figures would
    /// reopen a foreign purchase showing back-converted amounts, which drift by
    /// a cent on awkward rates — and re-saving would bake the drift in as the
    /// new truth.
    ///
    /// Rows arrive PINNED: they are figures the user set before and must not be
    /// re-divided just by opening the sheet.
    static func seedGrid(from rows: [Tx]) -> GridSeed {
        var accountIds: [String] = []
        var categoryIds: [String?] = []
        var cells: [(key: String, amount: Double)] = []
        var currency: String?

        for row in rows {
            if !accountIds.contains(row.account) { accountIds.append(row.account) }
            for leg in categoryLegs(of: row) {
                if !categoryIds.contains(where: { $0 == leg.categoryId }) {
                    categoryIds.append(leg.categoryId)
                }
                cells.append((cellKey(account: row.account, category: leg.categoryId),
                              abs(leg.amount)))
                if currency == nil { currency = leg.currency }
            }
        }

        var alloc = SplitAllocation(total: SplitAllocation.round2(cells.reduce(0) { $0 + $1.amount }))
        for cell in cells {
            alloc.tick(cell.key)
            alloc.setAmount(cell.key, cell.amount)
        }
        return GridSeed(alloc: alloc, accountIds: accountIds,
                        categoryIds: categoryIds, currency: currency)
    }

    /// One card's category legs. A card with several categories carries them in
    /// `splits`; a card with exactly one has no `splits` array at all, because
    /// the projection puts that category on the row itself.
    private static func categoryLegs(of row: Tx) -> [(categoryId: String?, amount: Double, currency: String?)] {
        if let splits = row.splits, !splits.isEmpty {
            return splits.map { ($0.categoryId, $0.origAmount ?? $0.amountBase, $0.origCurrency) }
        }
        return [(row.category, row.nativeAmount ?? row.amount, row.currency)]
    }
```

- [ ] **Step 4: Run — all eleven tests in the file must pass.** Same command as Task 1 Step 4. Expected: 11 tests, 0 failures.

- [ ] **Step 5: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: a saved grid can be turned back into its cells

A grid purchase is several transactions linked by group_id, one per card, each
with its own category legs. seedGrid(from:) turns them back into the one flat
cell allocation the editor uses.

Amounts come back in the purchase's currency, from the per-cell origAmount the
engine records. The base figures would reopen a foreign purchase back-converted,
drifting by a cent on awkward rates — and re-saving would bake that in.

Rows arrive pinned: opening the sheet must not re-divide the purchase. A card
that bought exactly one category has no splits array, and is still a cell."
```

---

## Task 3: Page 2 becomes a page

**Files:**
- Create: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseGridPage.swift`

**Interfaces:**
- Consumes: `PurchaseGridSection(alloc:accountIds:categoryIds:currency:)`, `PurchaseFlow.isBalanced(_:)`, `store.displayNative(_:currency:)`, the `.finchSheetForm()` and `.confirmCheckmarkStyle()` modifiers.
- Produces: `PurchaseGridPage(alloc:accountIds:categoryIds:currency:onSave:)`.

**No new strings.** The navigation title is the running total, rendered with
`Text(verbatim:)` so it is not extracted for localisation — and it is the one
piece of context page 2 needs anyway.

- [ ] **Step 1: Create the page.**

```swift
import SwiftUI
import FinchCore

/// Page 2 of the entry flow: divide the money.
///
/// Page 1 asks WHICH cards and WHICH categories; this asks how much of each.
///
/// **A pushed page, not more sections on page 1.** A 3×4 grid is twelve fields
/// and three headers; sitting below the date, note, tags and receipt rows it was
/// effectively invisible — the grid shipped working and went unnoticed.
///
/// **✓ lives here**, because this is where the numbers that get saved are, and
/// it is disabled until they add up. The footer already said "N unaccounted"
/// while letting the save through.
struct PurchaseGridPage: View {
    @EnvironmentObject private var store: FinchStore
    @Binding var alloc: SplitAllocation
    let accountIds: [String]
    let categoryIds: [String?]
    let currency: String
    let onSave: () -> Void

    var body: some View {
        Form {
            PurchaseGridSection(alloc: $alloc, accountIds: accountIds,
                                categoryIds: categoryIds, currency: currency)
        }
        .finchSheetForm()
        // The purchase total, which is the only context this page needs. Rendered
        // verbatim so it is not extracted as a localisable string — it is a
        // number, already formatted for the locale by `displayNative`.
        .navigationTitle(Text(verbatim: store.displayNative(alloc.total, currency: currency)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSave) { Image(systemName: "checkmark") }
                    .accessibilityLabel("Save")
                    .confirmCheckmarkStyle()
                    .disabled(!PurchaseFlow.isBalanced(alloc))
                    .accessibilityIdentifier("grid.save")
            }
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles.** Nothing renders it yet.

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`. If `Save` is reported as an unlocalised string,
stop — it is already a catalog key (`zh: 保存`) and a failure here means the
export is stale, not that a key is missing.

- [ ] **Step 3: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: the grid gets a page of its own

PurchaseGridSection's own doc comment already called it page 2's grid; the page
was never built. Twelve fields and three headers below the date, note, tags and
receipt rows meant the grid shipped working and unnoticed.

The title is the running total — the one piece of context this page needs, and
no new localised string. Save moves here, where the numbers are, and is disabled
until they add up."
```

---

## Task 4: The Add sheet routes to page 2

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` — state block near `:74`; toolbar `confirmationAction` at `:255`; the inline grid at `:390`
- Modify: `ios/scripts/extracted-keys.json`, `ios/scripts/zh-manual.json`, `ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings` — the "Next" string

**Interfaces:**
- Consumes: `PurchaseFlow.reseedGrid`, `PurchaseGridPage`, existing `usesGrid`, `gridAlloc`, `accountAlloc`, `splitAlloc`.
- Produces: nothing later tasks consume.

**One new string:** `"Next"` → `下一步`.

- [ ] **Step 1: Add the navigation state.** After the `gridAlloc` declaration (`:74`):

```swift
    /// Page 2 is pushed, not presented: it is the same purchase being described,
    /// not a separate decision, and Back must return to page 1 with everything
    /// still typed.
    @State private var showingGrid = false
```

- [ ] **Step 2: Replace the inline grid with nothing.** Delete this block from `formPage` (`:388-395`) — the section moves to page 2:

```swift
            if usesGrid {
                PurchaseGridSection(
                    alloc: $gridAlloc,
                    accountIds: accountAlloc.payload.map { $0.id ?? accountId },
                    categoryIds: splitAlloc.payload.map { $0.id },
                    currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode)
            }
```

Leave the comment above it in place but retarget it:

```swift
            // Both axes split: the per-axis editors above each divide ONE axis, and
            // two sets of margins do not determine the cells between them — $60/$0/
            // $10/$30 and $42/$18/$28/$12 give the same card and category totals.
            // So the cells are typed on page 2, and the totals derive from them.
```

- [ ] **Step 3: Send ✓ to page 2 when a grid is in play.** Replace the `confirmationAction` toolbar item's `Button(action: save)` line — keep every modifier attached to it:

```swift
                ToolbarItem(placement: .confirmationAction) {
                    // A grid is described on page 2, so page 1 offers the way there
                    // instead of a save. Everything else still saves from here.
                    Button(action: { usesGrid ? openGrid() : save() }) {
                        if usesGrid { Text("Next") } else { Image(systemName: "checkmark") }
                    }
                        .accessibilityLabel(usesGrid ? Text("Next") : Text("Save"))
                        .confirmCheckmarkStyle()
```

- [ ] **Step 4: Add the destination and the seeding.** Attach to the same view the other `.sheet`/`.onChange` modifiers hang off, immediately after `.onAppear(perform: seedDefaults)`:

```swift
            .navigationDestination(isPresented: $showingGrid) {
                PurchaseGridPage(
                    alloc: $gridAlloc,
                    accountIds: accountAlloc.payload.map { $0.id ?? accountId },
                    categoryIds: splitAlloc.payload.map { $0.id },
                    currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode,
                    onSave: save)
            }
```

and add the helper next to `save()`:

```swift
    /// Open page 2, rebuilding the cells for whatever is selected now.
    ///
    /// `reseedGrid` keeps every cell the user already typed and floats the new
    /// ones, so going back to add a card does not disturb the figures already
    /// set — it just gives the new card whatever is left.
    private func openGrid() {
        let total = abs(DecimalInput.parse(amount) ?? 0)
        gridAlloc = PurchaseFlow.reseedGrid(gridAlloc,
                                            accounts: accountAlloc.payload,
                                            categories: splitAlloc.payload,
                                            total: total)
        showingGrid = true
    }
```

- [ ] **Step 5: Dismiss page 2 when the save succeeds.** `save()` already calls `dismiss()`, which tears the whole sheet down including the pushed page. No change — but verify it in Step 7 rather than assuming.

- [ ] **Step 6: Run the l10n procedure for "Next".** From `ios/`, run the block in **Adding a UI string** above. Add to `scripts/zh-manual.json`, in place, keeping the file's existing formatting:

```json
  "Next": "下一步",
```

- [ ] **Step 7: Build, test, and check the catalog moved as expected.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' test 2>&1 \
  | grep -E "^Test Suite 'All tests'|error:|Executed [0-9]+ tests"
git diff --stat -- ios/scripts/zh-manual.json
```
Expected: 0 failures; `zh-manual.json` shows **1 line changed**, not a whole-file
rewrite. A rewrite means the file was re-serialised — revert and insert by hand.

- [ ] **Step 8: Commit the code and the catalog together.**

```bash
git add ios/FinchApp ios/scripts
git commit -m "feat: the Add sheet sends you to page 2

Splitting both axes used to append the grid's sections to the bottom of the same
form. It now offers Next, and the grid is a page.

Page 2 is pushed rather than presented: it is the same purchase being described,
and Back returns to page 1 with everything still typed. Re-entering rebuilds the
cells for the current selection, keeping what was typed and floating what is new."
```

---

## Task 5: The Edit sheet reopens the whole grid

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` — state near `:48`; computed properties near `:63-70`; the form's `isSplit` branches at `:161` and `:240`; `.onAppear` at `:405`; toolbar at `:384`; `save()` at `:459`
- Test: `ios/FinchApp/Tests/FinchAppTests/GridReopenTests.swift` (new)

**Interfaces:**
- Consumes: `PurchaseFlow.seedGrid(from:)`, `PurchaseFlow.GridSeed`, `PurchaseGridPage`, `saveTransaction`.
- Produces: nothing later tasks consume except the dropped-card set, which Task 6 reads.

**No call site changes.** All fourteen construct `EditTransactionSheet(txn:)`;
the sheet decides for itself.

- [ ] **Step 1: Write the failing test.** Create `ios/FinchApp/Tests/FinchAppTests/GridReopenTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchApp
import FinchCore

/// Reopening a grid purchase, through the real engine.
///
/// `GridSeedTests` covers the arithmetic on hand-built rows. This covers the
/// round trip: write a grid, project it, seed from what came back, and save the
/// result — which is the path that decides whether an edit preserves a purchase
/// or quietly takes it apart.
final class GridReopenTests: XCTestCase {

    private func seed() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    private func writeGrid(_ q: DatabaseQueue) throws {
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-40)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-20)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c1"), "amount": .double(-30)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c2"), "amount": .double(-10)]),
            ]),
        ]))
    }

    /// Tapping ONE card's row must reopen the whole purchase.
    func test_tappingOneCardReopensTheWholePurchase() throws {
        let q = try seed()
        try writeGrid(q)
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")

        let tapped = try XCTUnwrap(txns.first { $0.account == "a1" && $0.groupId != nil })
        let group = txns.filter { $0.groupId != nil && $0.groupId == tapped.groupId }
        XCTAssertEqual(group.count, 2, "two cards, one purchase")

        let seeded = PurchaseFlow.seedGrid(from: group)
        XCTAssertEqual(Set(seeded.accountIds), ["a1", "a2"])
        XCTAssertEqual(Set(seeded.categoryIds.map { $0 ?? "" }), ["c1", "c2"])
        XCTAssertEqual(seeded.alloc.total, 100, accuracy: 0.001,
                       "the purchase, not the 60 on the card that was tapped")
        XCTAssertTrue(PurchaseFlow.isBalanced(seeded.alloc))
    }

    /// Saving the reopened cells back against the GROUP id rewrites the purchase
    /// in place: two transactions still, same group, amounts as edited.
    func test_savingAReopenedGridRewritesItInPlace() throws {
        let q = try seed()
        try writeGrid(q)
        var txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let group = txns.filter { $0.groupId != nil }
        let groupId = try XCTUnwrap(group.first?.groupId)

        var alloc = PurchaseFlow.seedGrid(from: group).alloc
        alloc.setAmount("a1|c1", 50)     // 40 → 50
        alloc.setTotal(110)

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "id": .string(groupId),
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array(PurchaseFlow.cells(from: alloc, kind: .expense)),
        ]))

        txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let after = txns.filter { $0.groupId != nil }
        XCTAssertEqual(Set(after.map(\.account)), ["a1", "a2"], "both cards survive")
        XCTAssertEqual(Set(after.compactMap(\.groupId)).count, 1, "still one purchase")
        XCTAssertEqual(after.reduce(0) { $0 + abs($1.amount) }, 110, accuracy: 0.001)
    }

    /// Dropping a card from the grid removes that card's transaction, and the
    /// survivors stay one purchase.
    func test_droppingACardRemovesItsTransaction() throws {
        let q = try seed()
        try writeGrid(q)
        let group = try Projection.run(dbQueue: q, ledgerId: "l1").filter { $0.groupId != nil }
        let groupId = try XCTUnwrap(group.first?.groupId)

        var alloc = PurchaseFlow.seedGrid(from: group).alloc
        alloc.untick("a2|c1")
        alloc.untick("a2|c2")
        alloc.setTotal(60)

        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "id": .string(groupId),
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array(PurchaseFlow.cells(from: alloc, kind: .expense)),
        ]))

        let after = try Projection.run(dbQueue: q, ledgerId: "l1").filter { $0.merchant == "Market" }
        XCTAssertEqual(after.map(\.account), ["a1"], "the dropped card's transaction is gone")
        XCTAssertNil(after.first?.groupId, "a group of one is not a group")
    }
}
```

- [ ] **Step 2: Run and record.** Expected: all three PASS. They exercise the
engine and the pure seeding, both of which exist — they are written first because
they pin the contract the sheet wiring below depends on, and because they are the
regression net for a purchase being taken apart by an edit.

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests/GridReopenTests test 2>&1 | grep -E "error:|Executed [0-9]+ test"
```

- [ ] **Step 3: Add the state and the group detection.** After the `accountAlloc` declaration (`:48`):

```swift
    @State private var gridAlloc = SplitAllocation(total: 0)
    @State private var showingGrid = false
    /// The cards that were in this purchase when the sheet opened, so `save()`
    /// can tell which ones an edit is about to drop.
    @State private var openingAccountIds: [String] = []
```

and next to `isSplit` (`:70`):

```swift
    /// A grid purchase: several transactions, one per card, linked by `groupId`.
    ///
    /// Detected HERE rather than by the fourteen screens that open this sheet —
    /// they all construct `EditTransactionSheet(txn:)` and nothing else, so this
    /// is the one place that has to know.
    private var isGrid: Bool { liveTxn.groupId != nil }

    /// Every card's transaction in this purchase, the tapped one included.
    private var groupRows: [Tx] {
        guard let gid = liveTxn.groupId else { return [] }
        return store.txns.filter { $0.groupId == gid }
    }

    /// Both axes split, so the money is divided on page 2.
    private var usesGrid: Bool {
        PurchaseFlow.page2(accounts: accountAlloc.payload.count,
                           categories: splitAlloc.payload.count) == .grid
    }
```

- [ ] **Step 4: Give a grid its Amount field.** The `isSplit` branches hide Amount because a category split's total IS the amount. A grid cannot do that — the amount is the target the cells must reach, and without the field there is no way to raise a purchase's total. Change the two `isSplit` conditions at `:161` and `:240` to `isSplit && !isGrid`, and add above them:

```swift
                // A grid keeps the ordinary Account/Amount/Category layout: the
                // amount is the TARGET its cells must reach (`save()` refuses a
                // mismatch), so hiding the field the way a category split does
                // would leave no target and no way to raise the purchase's total.
```

- [ ] **Step 5: Seed everything on open.** Inside `.onAppear` (`:405`), immediately after the existing `accountAlloc` seeding block, add:

```swift
                // A grid reopens whole: the cells, both margins, and the total.
                // The margins are derived from the cells rather than stored —
                // nothing persists "the card split" separately from the purchase.
                if isGrid {
                    let seeded = PurchaseFlow.seedGrid(from: groupRows)
                    gridAlloc = seeded.alloc
                    openingAccountIds = seeded.accountIds
                    if let ccy = seeded.currency { currencyCode = ccy }
                    amountText = String(format: "%g", seeded.alloc.total)

                    var byAccount: [(id: String?, amount: Double)] = []
                    var byCategory: [(id: String?, amount: Double)] = []
                    for row in seeded.alloc.rows {
                        let parts = PurchaseFlow.splitCellKey(row.id)
                        if let i = byAccount.firstIndex(where: { $0.id == parts.account }) {
                            byAccount[i].amount += row.amount
                        } else { byAccount.append((parts.account, row.amount)) }
                        if let i = byCategory.firstIndex(where: { $0.id == parts.category }) {
                            byCategory[i].amount += row.amount
                        } else { byCategory.append((parts.category, row.amount)) }
                    }
                    accountAlloc = SplitAllocation.merging(byAccount, total: seeded.alloc.total)
                    splitAlloc = SplitAllocation.merging(byCategory, total: seeded.alloc.total)
                }
```

- [ ] **Step 6: Route the toolbar and add the destination.** Replace the `confirmationAction` button (`:384-388`):

```swift
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { usesGrid ? openGrid() : save() }) {
                        if usesGrid { Text("Next") } else { Image(systemName: "checkmark") }
                    }
                        .accessibilityLabel(usesGrid ? Text("Next") : Text("Save"))
                        .confirmCheckmarkStyle()
                }
```

and attach the destination beside the sheet's other modifiers, after `.onAppear`:

```swift
            .navigationDestination(isPresented: $showingGrid) {
                PurchaseGridPage(
                    alloc: $gridAlloc,
                    accountIds: accountAlloc.payload.map { $0.id ?? accountId },
                    categoryIds: splitAlloc.payload.map { $0.id },
                    currency: currencyCode.isEmpty ? accountCurrency : currencyCode,
                    onSave: save)
            }
```

with the helper next to `save()`:

```swift
    /// Open page 2, rebuilding the cells for whatever is selected now — keeping
    /// every cell already typed and floating the new ones.
    private func openGrid() {
        gridAlloc = PurchaseFlow.reseedGrid(gridAlloc,
                                            accounts: accountAlloc.payload,
                                            categories: splitAlloc.payload,
                                            total: abs(DecimalInput.parse(amountText) ?? 0))
        showingGrid = true
    }
```

- [ ] **Step 7: Save the grid against the GROUP.** In `save()`, add a grid branch before the existing `accountAlloc.payload.count >= 2` branch that builds cells:

```swift
        if usesGrid {
            // Cells for the whole purchase, and the id names the GROUP — so the
            // engine matches rows by card and each surviving card keeps its
            // transaction id, its receipt and its reconcile mark. Naming the
            // tapped posting instead would rewrite that one row and leave the
            // rest of the purchase behind.
            cells = PurchaseFlow.cells(from: gridAlloc,
                                       kind: AddTxKind(rawValue: effKind) ?? .expense)
        } else if accountAlloc.payload.count >= 2 {
```

and change the payload's id:

```swift
            "id": .string(isGrid ? (liveTxn.groupId ?? txn.id) : txn.id),
```

Extend the balance gate added in the previous PR so a grid is covered — and
**scope the two margin gates to `!usesGrid`**, or a grid can never be saved after
its amount changes:

```swift
        // For a grid the CELLS are what gets written, so they are what must add
        // up. The margin allocations are seeded from the cells and go stale the
        // moment one is edited on page 2 — and `.onChange(of: amountText)`
        // re-totals them against pinned rows, which is exactly `.sumMismatch`.
        // Gating on them here would refuse every grid whose total was changed,
        // with a message about splits the user never touched.
        if usesGrid {
            if !PurchaseFlow.isBalanced(gridAlloc) {
                errorMessage = String(localized: "Splits must add up to the transaction total.")
                return
            }
        } else {
            if accountAlloc.payload.count >= 2, accountAlloc.problem != nil {
                errorMessage = String(localized: "Splits must add up to the transaction total.")
                return
            }
            if isSplit, splitAlloc.problem != nil {
                errorMessage = String(localized: "Splits must add up to the transaction total.")
                return
            }
        }
```

This replaces the two standalone `if` gates from the previous PR; do not leave
them in place alongside this block.

- [ ] **Step 8: Build and run the full app suite.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' test 2>&1 \
  | grep -E "^Test Suite 'All tests'|error:|Executed [0-9]+ tests"
```
Expected: 0 failures across all three bundles. A UI test failing on a split flow
must be read before it is changed — a save that used to succeed and now asks for
a second page is the feature, not a regression.

- [ ] **Step 9: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: editing any row of a grid reopens the whole purchase

Tapping one card of a grid purchase showed that card alone, as though the rest
did not exist — and saving it rewrote one row of a purchase whose other rows
were never on screen.

The sheet detects groupId itself, so none of the fourteen screens that open it
change. It rebuilds the cells, both margins and the total from the saved rows,
and saves against the GROUP id, so the engine matches by card and every
surviving card keeps its transaction id, its receipt and its reconcile mark.

A grid keeps its Amount field, which a category split hides: the amount is the
target its cells must reach, so without the field there is no target and no way
to raise a purchase's total."
```

---

## Task 6: Dropping a card says what goes with it

**Files:**
- Modify: `ios/FinchApp/Sources/FinchShared/FinchStore+ViewHelpers.swift` — beside `deleteTransaction` at `:110`
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` — `save()`
- Modify: `ios/scripts/extracted-keys.json`, `ios/scripts/zh-manual.json`, the catalog

**Interfaces:**
- Consumes: `store.attachments(for:) -> [AttachmentRow]`, `AttachmentRow.relPath`, `openingAccountIds` from Task 5.
- Produces: `FinchStore.unlinkOrphanedAttachments(relPaths:)`.

**One new string:** `"Removing %@ also deletes its receipt."` → `移除%@时会一并删除其收据。`

**Why the app layer:** the ledger rows cascade-delete with their entry, but the
FILES do not, and the engine is filesystem-agnostic. `deleteTransaction` already
handles this pattern — read the paths before the write, remove them after.

- [ ] **Step 1: Expose file unlinking.** In `FinchStore+ViewHelpers.swift`, after `deleteTransaction`:

```swift
    /// Remove files for attachments a write has just orphaned.
    ///
    /// The ledger rows cascade-delete with their entry; the FILES do not, and
    /// the engine is filesystem-agnostic by design. Callers read the paths
    /// BEFORE the write, while the rows still resolve, then call this after —
    /// the same order `deleteTransaction` uses.
    public func unlinkOrphanedAttachments(relPaths: [String]) {
        unlink(relPaths: relPaths)
    }
```

- [ ] **Step 2: Warn, then unlink.** In `EditTransactionSheet`, add near `save()`:

```swift
    /// Cards this save is about to drop from the purchase, paired with the
    /// receipts that would go with them.
    ///
    /// Only reachable for a grid: dropping a card deletes that card's whole
    /// transaction, and its receipt is not visible from here — the sheet loads
    /// only the tapped row's. Silently destroying a file the user cannot see is
    /// the thing this exists to prevent.
    private var droppedCardsWithReceipts: [(name: String, txId: String, files: [String])] {
        guard isGrid else { return [] }
        let keeping = Set(gridAlloc.payload.map { PurchaseFlow.splitCellKey($0.id ?? "").account })
        return openingAccountIds.filter { !keeping.contains($0) }.compactMap { accountId in
            guard let row = groupRows.first(where: { $0.account == accountId }) else { return nil }
            let files = store.attachments(for: row.id).map(\.relPath)
            guard !files.isEmpty else { return nil }
            return (store.accounts.first { $0.id == accountId }?.name ?? accountId, row.id, files)
        }
    }
```

In `save()`, immediately before the `store.apply(.saveTransaction, …)` call, gate on it:

```swift
        // Saving is the last moment this can be backed out of, so it asks here.
        // Only when a dropped card actually HAS a receipt, so the ordinary path
        // stays silent.
        let dropped = droppedCardsWithReceipts
        if !dropped.isEmpty, !receiptLossConfirmed {
            pendingReceiptLoss = dropped.map(\.name).joined(separator: ", ")
            return
        }
```

with the state and the alert:

```swift
    @State private var pendingReceiptLoss: String?
    @State private var receiptLossConfirmed = false
```

```swift
            .alert("Delete transaction?", isPresented: Binding(
                get: { pendingReceiptLoss != nil }, set: { if !$0 { pendingReceiptLoss = nil } }),
                presenting: pendingReceiptLoss) { _ in
                Button("Delete", role: .destructive) {
                    receiptLossConfirmed = true
                    pendingReceiptLoss = nil
                    save()
                }
                Button("Cancel", role: .cancel) { pendingReceiptLoss = nil }
            } message: { names in
                Text("Removing \(names) also deletes its receipt.")
            }
```

and after the write succeeds, unlink — reading the paths BEFORE the apply:

```swift
        let orphaned = dropped.flatMap(\.files)
        do {
            try store.apply(.saveTransaction, Args(args))
            store.unlinkOrphanedAttachments(relPaths: orphaned)
            Haptics.success()
            dismiss()
        } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
```

- [ ] **Step 3: Run the l10n procedure** for `"Removing %@ also deletes its receipt."`, exactly as in Task 4 Step 6. The extracted key carries the `%@` specifier already.

- [ ] **Step 4: Build and run the full app suite.** Same command as Task 5 Step 8. Expected: 0 failures.

- [ ] **Step 5: Confirm the catalog moved by two keys and nothing else.**

```bash
git diff --stat -- ios/scripts/zh-manual.json ios/scripts/extracted-keys.json
```
Expected: small line counts on both. A whole-file rewrite means re-serialisation
— revert and insert by hand.

- [ ] **Step 6: Commit.**

```bash
git add ios/FinchApp ios/scripts
git commit -m "feat: dropping a card says what goes with it

Removing a card from a grid deletes that card's whole transaction — and its
receipt, which is not visible from the sheet, because the sheet loads only the
tapped row's attachments. Destroying a file the user cannot see is what this
prevents.

Asked at save, the last moment it can be backed out of, and only when a dropped
card actually has a receipt, so the ordinary path stays silent. The ledger rows
cascade-delete with their entry; the files do not, and only the app layer can
remove them — paths read before the write, unlinked after, the same order
deleteTransaction uses."
```

---

## Task 7: Gate and PR

- [ ] **Step 1: Confirm the base.**

```bash
git fetch -q origin && git rev-list --count HEAD..origin/feat/frontend
```
If PR #736 has merged, rebase onto `origin/feat/frontend` and re-run Task 5 Step 8
before continuing. If it has not, the PR opened below must state that it stacks
on #736 and merges after it.

- [ ] **Step 2: Run the FULL gate.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  SIM_NAME=ios-finch-splits ./scripts/ci-local.sh --full --all
```
Expected: `all checks passed`. `--all` alone runs FAST and skips the 33 UI tests
and the watch build; `fast checks passed` is NOT sufficient here, because this
plan changes navigation and the UI tests are the only cover for it.

- [ ] **Step 3: Confirm the tree and the scope.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git status --short
git diff --stat origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/Tests/ParityTests/
```
Expected: `git status` prints nothing; the second diff is empty.

**Careful:** the catalog IS an intended change in this plan. Discarding churn
after the gate must not discard the committed l10n work — if `git status` shows
the catalog modified, check whether the diff is formatting-only churn (discard)
or the two new keys (they should already be committed in Tasks 4 and 6; if they
are not, the l10n procedure was not completed).

- [ ] **Step 4: Push and open the PR.**

```bash
git push -u origin feat/grid-reopen
gh pr create --base feat/frontend --head feat/grid-reopen \
  --title "The grid gets a page, and a grid purchase becomes editable"
```
Body must cover: the two-page flow; pre-filled page 2 and why that does not
contradict the grid's reason for existing; Edit self-detecting `groupId` so no
call site changes; the Amount field decision; save targeting the group id; the
dropped-receipt warning; and — if #736 is unmerged — that this stacks on it.

- [ ] **Step 5: Report the PR number and stop.** Do not merge.

---

## Out of scope

- **A one-axis split moving to page 2.** It already has its own screen.
- **Mixed-currency splits in the editor.** The engine accepts them; the picker
  renders one currency symbol per sheet. Still parked.
- **Changing a grid's kind.**
- **The web.** No grid there, and no `saveTransaction`.
- **Rules.** Frozen, flagged for its own design review.

## Verification checklist

- [ ] `ci-local.sh --full --all` prints `all checks passed`
- [ ] Page 2 opens balanced from both margins; ✓ is live on arrival
- [ ] Going back and adding a card leaves typed cells alone and floats the new ones
- [ ] Tapping any row of a grid reopens all of it, with the purchase's total
- [ ] A foreign-currency grid reopens showing the figures as typed, not back-converted
- [ ] Saving a reopened grid keeps every surviving card's transaction id
- [ ] Dropping a card with a receipt warns first, and the file is unlinked after
- [ ] Dropping a card without a receipt does NOT warn
- [ ] A one-axis split still saves from page 1, with no Next button
- [ ] `zh-manual.json` and `extracted-keys.json` moved by a handful of lines, not wholesale
- [ ] `git diff origin/feat/frontend...HEAD -- frontend/` is empty
