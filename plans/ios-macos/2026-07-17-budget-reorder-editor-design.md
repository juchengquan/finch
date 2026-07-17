# Budgets: the Accounts-style Reorder editor + modal reorder chrome (both tabs)

**Date:** 2026-07-17
**Status:** Design approved, pending implementation
**Scope:** (1) Budgets gets the full **⋯ → Reorder** in-place editor Accounts has — collapsed
groups drag as blocks, expand to drag budgets within/**across** groups, persisted on ✓.
(2) Both tabs' reorder mode gets **modal chrome**: top-left **✕ = cancel (discard)**, top-right
**✓ = save**, everything else (ledger button, privacy eye, +, ⋯) hidden. Today there is no
cancel at all and all chrome stays live mid-reorder.

## Prerequisites shipped
`setBudgetOrder` (#479, order), `updateBudget groupId` (membership), `updateBudgetGroup
sortOrder` (group order) — the editor persists all three on Done.

## Part 1 — `Common/BudgetReorder.swift` (+ tests)

Mirror of the proven `AccountReorder` (12 tests) typed to `BudgetRow` — deliberate parallel
rather than genericizing tested Accounts code; the persistence halves genuinely differ.
Same model + rules: `BudgetReorderRow` (`.group(id:String?,name:)` / `.item(BudgetRow)`),
`buildRows(groups:budgets:)` (real groups in order + their budgets via `groupId`, then pinned
Ungrouped + nil-group budgets), `applyMove` (items free-place; real-group header drag rebuilds
as a block; Ungrouped pinned; no item above the first header), `visibleRows(collapsed:)`,
`itemCount(of:in:)`, `applyVisibleMove`, and `plan(_:) -> (groups:[(id,order)],
items:[(id:String, groupId:String?, order:Int)])`.
**Tests:** `BudgetReorderTests.swift` mirroring the Account suite's cases (build order,
plan, cross-group re-parent, no-item-above-first-header, block move, pinned Ungrouped, clamp,
visibleRows, itemCount, collapsed block move, drop-below-collapsed-joins-end, no-collapse ≡).

## Part 2 — BudgetsTab editor (mirrors AccountsTab structurally)

- State: `editMode` (mirror AccountsTab's exact `#if os(iOS)` gating for `EditMode`),
  `reorderRows: [BudgetReorderRow] = []`, `expandedReorderGroups: Set<String> = []`.
- **⋯ → Reorder** item (iOS-only) after Manage Groups → `withAnimation { editMode = .active }`.
- `.environment(\.editMode, $editMode)` + `.onChange(of: editMode)`: entering → `reorderRows =
  BudgetReorder.buildRows(groups: store.budgetGroups, budgets: store.budgets)`,
  `expandedReorderGroups = []`; leaving → `persistReorder()` then `reorderRows = []`.
- `listContent` swaps to `reorderList` while editing (like AccountsTab): visible rows with
  collapsed-group Button rows (chevron + name + `· N budgets`) and `BudgetRowView` item rows;
  `.onMove` → `applyVisibleMove`; inner `.environment(\.editMode, .constant(.active))`.
- `persistReorder()` (diff-aware, mirrors Accounts'):
  - `plan.groups` → `updateBudgetGroup {sortOrder}` where order changed;
  - `plan.items` → `updateBudget {groupId}` patch where membership changed (`.null` to clear);
  - `setBudgetOrder` with the flat item ids (single call, always).
  - Guarded by `!reorderRows.isEmpty` → the cancel path skips it.

## Part 3 — Modal reorder chrome (AccountsTab + BudgetsTab)

Toolbar becomes two branches:
```swift
.toolbar {
    if editMode.isEditing {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button { reorderRows = []; withAnimation { editMode = .inactive } }
                label: { Image(systemName: "xmark") }
                .accessibilityLabel("Cancel")
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            Button { withAnimation { editMode = .inactive } } label: { Image(systemName: "checkmark") }
                .accessibilityLabel("Done").fontWeight(.semibold)
        }
    } else {
        …the entire existing item set, unchanged…
    }
}
```
- **✕ discards** (clears `reorderRows` first — the persist guard then no-ops), **✓ saves**.
- Ledger button, PrivacyToggle, +, and every ⋯ item are hidden while editing — reorder is modal.
- AccountsTab's existing "+ becomes ✓" special case is replaced by this cleaner split.

## Out of scope
- macOS editor (editMode is iOS-only — unchanged from Accounts); genericizing `AccountReorder`;
  removing the #479 in-list drag (Accounts keeps both, so do Budgets); Manage Groups (stays for
  CRUD).

## Testing
- **Unit:** the mirrored `BudgetReorderTests` suite must pass (plus existing suites).
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim, finch-fresh-6):** ⋯ → Reorder on Budgets → collapsed group rows with counts;
  toolbar shows only ✕/✓ (both tabs); ✕ discards (order unchanged after relaunch), ✓ persists
  (DB: `budget_groups.sort_order`, `app_state.budgetOrderByLedger`). Drag itself = human pass.
