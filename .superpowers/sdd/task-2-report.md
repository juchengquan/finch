# Task 2 report — BudgetsTab Reorder editor + modal ✕/✓ chrome (both tabs)

**Status:** DONE
**Commit:** `f329d47` — `feat(ios): Budgets Reorder editor (blocks/expand/cross-group) + modal ✕/✓ reorder chrome on both tabs` (2 files only: `Tabs/BudgetsTab.swift`, `Tabs/AccountsTab.swift`; no Co-Authored-By)

## Builds / tests
- iOS `FinchApp` (iPhone 17 Pro Max sim): `** BUILD SUCCEEDED **`
- macOS `FinchMac` (`CODE_SIGNING_ALLOWED=NO`): `** BUILD SUCCEEDED **`
- `-only-testing:FinchAppTests/BudgetReorderTests`: 12/12 passed, `** TEST SUCCEEDED **`

## What was done

### A. BudgetsTab — Reorder editor (mirrors AccountsTab section-by-section)
1. State: `#if os(iOS)`-gated block exactly like AccountsTab — `editMode: EditMode = .inactive`, `reorderRows: [BudgetReorderRow] = []`, `expandedReorderGroups: Set<String> = []`.
2. ⋯ menu: iOS-only `secondaryAction` "Reorder" item after Manage Groups (`withAnimation { editMode = .active }`, `arrow.up.arrow.down`, `.disabled(store.budgets.isEmpty)` — mirroring AccountsTab's `.disabled(store.accounts.isEmpty)`).
3. `.environment(\.editMode, $editMode)` + `.onChange(of: editMode)` at the end of the NavigationStack content (same position as AccountsTab), inside `#if os(iOS)`. Entering: `BudgetReorder.buildRows(groups: store.budgetGroups, budgets: store.budgets)` + `expandedReorderGroups = []`; leaving: `persistReorder(); reorderRows = []` (per plan — BudgetsTab's persistReorder does NOT self-clear, unlike Accounts').
4. `listContent`: extracted the two existing List layouts into a new `contentList` var (so the swap mirrors AccountsTab's `if editMode.isEditing { reorderList } else { contentList }` inside `#if os(iOS)`, `#else contentList`). EmptyState check unchanged.
5. `reorderList` (iOS-only): collapsed = all group ids minus expanded; ForEach `BudgetReorder.visibleRows`; real-group rows = chevron toggle Button + name + `Text("· \(BudgetReorder.itemCount(of: gid, in: reorderRows)) budgets")`; Ungrouped header = plain secondary Text; `.item` rows = `BudgetRowView(budget:)`; `.onMove` → `applyVisibleMove`; `.environment(\.editMode, .constant(.active))`.
6. `persistReorder()` — verbatim from the plan (diff-aware `updateBudgetGroup sortOrder` / `updateBudget groupId` incl. `.null`, one `setBudgetOrder` with flat ids, `guard !reorderRows.isEmpty`, errors → `errorMessage = i18nMessage(error)`).

### B. Modal ✕/✓ toolbar chrome (both tabs)
Each tab's `.toolbar` is now:
```swift
#if os(iOS)
if editMode.isEditing {
    ToolbarItem(.topBarLeading)  { ✕  reorderRows = []; editMode = .inactive }  // a11y "Cancel"
    ToolbarItem(.primaryAction)  { ✓  editMode = .inactive }                    // semibold, a11y "Done"
} else {
    standardToolbar
}
#else
standardToolbar
#endif
```
AccountsTab's old inline "+ becomes ✓ while editing" special case was removed (its `+` item is now a single unconditional button — the iOS/macOS duplication collapsed since the branches became identical).

## Adaptations (deviations from the literal prompt template)
- **editMode platform gating:** AccountsTab's `editMode` (and `reorderRows`) live inside `#if os(iOS)`, so a bare `if editMode.isEditing` at ToolbarContentBuilder level cannot compile on macOS. Per the plan's "gate the branch the same way", the whole if/else is wrapped in `#if os(iOS)` with a macOS `#else` fallthrough. To keep the existing item set byte-identical WITHOUT duplicating ~50 lines per platform branch, the entire pre-existing item set was extracted (unchanged) into a `@ToolbarContentBuilder private var standardToolbar: some ToolbarContent` on each tab, referenced from both the iOS `else` and the macOS `#else`. macOS chrome is unchanged (standardToolbar keeps its internal `#if os(iOS)` items: LedgerBarButton, Reorder).
- The ✕/✓ items themselves need no inner `#if os(iOS)` since the whole branch is already iOS-only (the prompt's inner `#if` around topBarLeading would be redundant).
- `"· %lld budgets"` is not in `Localizable.xcstrings` — but neither is Accounts' `"· %lld accounts"`; mirrored exactly (English fallback, same as the shipped Accounts editor). No catalog edits (commit restricted to the 2 tab files).

## Untouched (as required)
Engine/FinchCore, `BudgetReorder`/`AccountReorder`, Manage Groups (`BudgetGroupsView`/`GroupAdminView`), the #479 in-list `moveBudgets` drag, all swipe actions.

## Blockers
None.
