# Move Reorder into the ⋯ overflow menu (Accounts + Budgets)

**Date:** 2026-07-17
**Status:** Approved (move, not add — user decision), implemented inline.
**Scope:** The Reorder entry point moves from the group-header long-press context menu into the
top-right **⋯** (`.secondaryAction`) overflow, where group/archive management already lives
("moved off the + into the ⋯ overflow menu" precedent). The context menu keeps only its
*contextual* actions (Edit / Delete Group). UI-only; no engine change.

## Changes

### AccountsTab
- **Add** (after the "Manage Groups" ⋯ item), iOS-only — the flat reorder editor is
  editMode-based, which macOS doesn't have (unchanged from today):
  ```swift
                #if os(iOS)
                ToolbarItem(placement: .secondaryAction) {
                    Button { withAnimation { editMode = .active } } label: {
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(store.accounts.isEmpty)
                }
                #endif
  ```
- **Remove** the context-menu Reorder block (the `#if os(iOS) Button { editMode = .active } … #endif`
  inside the group-header `.contextMenu`); Edit/Delete Group stay.

### BudgetsTab
- **Add** (after "Manage Groups"), cross-platform (the sheet drags fine on macOS):
  ```swift
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        let used = Set(store.budgets.compactMap(\.groupId))
                        reorderGroupsDraft = store.budgetGroups.filter { used.contains($0.id) }
                        reorderingGroups = true
                    } label: { Label("Reorder Groups", systemImage: "arrow.up.arrow.down") }
                    .disabled(!store.budgets.contains { $0.groupId != nil })
                }
  ```
- **Remove** the context-menu Reorder button; Edit/Delete Group stay.

Labels differ deliberately: Accounts' editor reorders groups *and* accounts ("Reorder");
Budgets' sheet is groups-only ("Reorder Groups").

## Testing
Build iOS + macOS; sim: ⋯ menu on both tabs shows the new item (screenshot if the menu is
AX-tappable); long-press menu no longer shows Reorder (code assertion); entering reorder from the
menu works — human pass post-merge as usual for touch flows.
