# Add/Edit Budget sheet — transaction-style pickers + top type control

**Date:** 2026-07-20
**Status:** Design agreed in a brainstorming session; plan follows.
**Scope:** FinchApp `BudgetSheet` + two picker components + a shared category-tree-row
extraction. **No** FinchCore/engine/schema change, **no** web change.

## Purpose

The Add/Edit Budget sheet lists categories and accounts as **two big inline sections** —
a checkmark row for *every* category and *every* account, dumped into the form. On a real
ledger that's a long scroll of checkboxes. The transaction sheets solve the same problem
with a single row that opens a **full-height bottom sheet** (`SearchablePickerRow` /
`CategoryPickerRow`). This design brings that pattern to budgets, and — matching the
transaction sheet — moves the **Expense | Income** control to the top toolbar.

## Decisions (from the brainstorm)

1. **Categories → hierarchy-tree multi-select.** The bottom sheet is the same expand/collapse
   category tree the transaction Category picker uses (`CategoryPickerSheet`), but its checkmark
   toggles a **set** instead of staging one id.
2. **Accounts → flat multi-select.** Accounts have no hierarchy, so a flat searchable
   multi-select sheet (a multi-select sibling of `SearchablePickerRow`).
3. **"Add them" = assign existing.** The pickers select which existing categories/accounts a
   budget tracks. Creating brand-new categories/accounts stays in Settings (unchanged).
4. **Type control moves to the top.** The inline "Expense | Income" segmented picker moves to the
   toolbar `.principal` slot, mirroring `AddTransactionSheet` (segmented, icons via the shared
   `TxnKindIcon`); the first form section drops that row.
5. **Selection state + `save()` unchanged.** `selectedCategories` / `selectedAccounts` stay
   `Set<String>`; `save()` already emits `categoryIds` / `accountIds` arrays. The engine already
   `expandDescendants` a selected parent, so checking a parent category covers its children — no
   cascade logic in the UI.

## Visual

**Toolbar (top):** the centered title is replaced by the segmented type control, exactly like the
transaction sheet: `[ⓔ Expense | ⓘ Income]`.

**Tracking section** — the two long checklists collapse to two rows:
```
Categories                     Groceries, Dining, +2   ›   (taps → tree sheet)
Accounts                       All accounts            ›   (taps → flat sheet)
```
Row value: **"All categories" / "All accounts"** when empty (matches "leave empty = track all"),
else the selected names joined and truncated.

**Category sheet (tree, multi-select):**
```
✕   Categories                 ✓
🔍 Search
▾ Food                         ✓
    Groceries                  ✓
    Dining                     ✓
▸ Transport
```
**Account sheet (flat, multi-select):** searchable list, checkmark toggles.

Both are `.large` bottom sheets with stage-then-Confirm (Cancel discards).

## Components

### 1. `MultiSelectPickerRow` + `MultiSelectPickerSheet` (new — flat)
`WriteScreens/MultiSelectPickerRow.swift`. A multi-select sibling of `SearchablePickerRow`,
reusing its `PickerOption`.
```swift
struct MultiSelectPickerRow: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: Set<String>
    let emptyLabel: String            // e.g. "All accounts"
}
```
Row shows `title` + summary (`multiSelectSummary`, below); opens a `.large` sheet with a searchable
`List`, a **staged `Set<String>`**, tap-to-toggle checkmarks, Confirm commits / Cancel discards
(same contract as `SearchablePickerSheet`). Used for **Accounts**.

### 2. Shared `CategoryTreeRow` + `CategoryMultiPickerRow`/`Sheet` (tree)
The tree-row rendering in `CategoryPickerSheet.row(_:)` (swatch + icon + indented name + trailing
accessory + expand chevron) is **extracted** into a shared `CategoryTreeRow` view in
`WriteScreens/CategoryPickerRow.swift`, parameterized by selection state + actions:
```swift
struct CategoryTreeRow: View {
    let item: FlatCategory
    let byId: [String: CategoryRow]
    let isSelected: Bool
    let expanded: Bool
    let searchActive: Bool
    let onTap: () -> Void
    let onToggleExpand: () -> Void
}
```
- The existing single-select `CategoryPickerSheet` is refactored to use it (`isSelected: c.id == staged`, `onTap: { staged = c.id }`) — no behavior change for transactions.
- A new `WriteScreens/CategoryMultiPickerRow.swift` holds `CategoryMultiPickerRow` (row) +
  `CategoryMultiPickerSheet` (the tree with `@Binding var selection: Set<String>`, a staged
  `Set<String>`, `isSelected: staged.contains(c.id)`, `onTap:` toggles). Used for **Categories**.

### 3. `multiSelectSummary` (pure helper)
In `WriteScreens/MultiSelectPickerRow.swift`, mirroring `splitSummaryText`:
```swift
func multiSelectSummary(names: [String], emptyLabel: String) -> String
// names empty → emptyLabel; else names.joined(separator: ", ")
```

### 4. `BudgetSheet` (rewire)
- Move the `Picker("Type", …)` from the first `Section` (currently `.pickerStyle(.segmented)`) to
  a `ToolbarItem(placement: .principal)` segmented `Picker` with `Image(systemName: TxnKindIcon.icon(for: k.rawValue)).accessibilityLabel(k.label)` per case + `.frame(width: 100)` — mirroring `AddTransactionSheet`. Keep `.navigationTitle` for accessibility (the principal item overrides the visible center).
- Replace the two inline `Section { ForEach(categories/accounts) { Button … checkmark } }` blocks
  with a single **Tracking** section holding a `CategoryMultiPickerRow` and a `MultiSelectPickerRow`;
  keep the "Leave empty to track all …" text as the section footer.

## Data flow & error handling

Read-only selection into `Set<String>` bindings; `save()` is untouched (already sorts the sets into
`categoryIds`/`accountIds` arrays). No new failure modes. The category list is still kind-filtered
(`store.pickableCategories` by `kind`), so switching Expense↔Income repopulates the category tree.

## Testing

- **Unit (`FinchAppTests`):** `multiSelectSummary` — empty→emptyLabel, one name, several names joined.
- **Builds:** FinchApp + FinchMac.
- **Manual sim:** open Add Budget — type control centered in the toolbar; Categories row opens the
  tree (multi-check across parents/children, search), Accounts row opens the flat multi-select; row
  summaries update; save persists the same sets as before.
- No UI snapshot tests (conventional SwiftUI).

## Out of scope

Creating new categories/accounts from the pickers; a parent→child auto-check cascade in the UI
(the engine already expands parents); any change to `save()`/the engine; a search box on the account
sheet is included, but reordering/grouping accounts in the sheet is not; zh-Hans strings for new copy
follow the standard localization pass.
