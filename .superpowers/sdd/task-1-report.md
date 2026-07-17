# Task 1 report — BudgetReorder model + tests

**Status:** DONE
**Commit:** ae7f456ebe35aeacfe97c8d051299727d158f3af — `feat(ios): BudgetReorder model — grouped reorder rows for budgets (+tests)` (2 files only, no Co-Authored-By)

## Files
- `ios/FinchApp/Sources/FinchApp/Common/BudgetReorder.swift` — `BudgetReorderRow` (`.group(id:String?,name:)` / `.item(BudgetRow)`, ids `"g:…"`/`"i:\(id)"`), `BudgetReorder.buildRows(groups:budgets:)`, `applyMove`, `visibleRows(_:collapsed:)`, `itemCount(of:in:)`, `applyVisibleMove`, private `rebuildWithGroupOrder`, and `plan(_:) -> (groups:[(id,order)], items:[(id, groupId?, order)])`. Line-for-line mirror of `AccountReorder` typed to `BudgetRow`; same movement rules (real-group header = block rebuild via new group order; Ungrouped header pinned; no item above the first header; collapsed-aware visible-index translation).
- `ios/FinchApp/Tests/FinchAppTests/BudgetReorderTests.swift` — all 12 Account-suite cases mirrored. Fixture: `bgt(_ id:,_ gid:)` builds a minimal `BudgetRow` (zeros/empties, `warningPct: 80`); groups `[GroupRow(id:"g1",name:"Bank"), GroupRow(id:"g2",name:"Cards")]`; b1,b2 in g1, b3 in g2, b4 ungrouped.

## Verification
- Tests (iPhone 17 Pro sim, `xcodebuild test … -only-testing:FinchAppTests/BudgetReorderTests -only-testing:FinchAppTests/AccountReorderTests`):
  - `BudgetReorderTests`: Executed 12 tests, with 0 failures (0 unexpected)
  - `AccountReorderTests`: Executed 12 tests, with 0 failures (0 unexpected) — unbroken
  - `** TEST SUCCEEDED **`
- iOS build (`xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`): `** BUILD SUCCEEDED **`

## Adaptations
- None of substance. `AccountReorder.persistencePlan` is named `plan` per spec, returning `items` (not `accounts`); `isAccount` helper mirrored as `isItem`. Group fixture uses `GroupRow` directly (`AccountGroupRow` is a typealias of `GroupRow` in FinchCore `Models.swift`).

## Blockers
- None. AccountReorder, tabs, and engine untouched.
