# Task 3 report — iOS UI: Add-Group sheet + color dots

**Status:** Complete. Commit `84d53ca` on `feat/ios-group-color` (only `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift`, no Co-Authored-By).

## What was done
1. Removed the #481 Add-Group alert: `newGroupName` state, the `.alert("Add group"...)` block (including its explanatory message text), and `addGroup()`. Kept `addingGroup`; the overflow-menu button is now just `addingGroup = true`. Presentation: `.sheet(isPresented: $addingGroup) { AddGroupSheet().presentationDetents([.medium]) }` (detents attached to the sheet content, per plan).
2. Added the `AddGroupSheet` private struct at file end, exactly as specified in the plan — no adaptations needed.
3. Color dots (8×8 `Circle`, only when color non-nil and hex parses):
   - `groupedSections` group-header Button label, between the chevron and `Text(groupName)`, resolved via `store.budgetGroups.first(where: { $0.name == groupName })?.color`.
   - `reorderList` real-group chevron Button label (gid non-nil branch), resolved via `store.budgetGroups.first(where: { $0.id == gid })?.color`. Ungrouped pseudo-header gets no dot.

## Helper verification (plan assumptions vs. reality)
- `TagPalette.hexes` — exists exactly as assumed in `ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift` (8 hexes + `defaultHex`).
- `Color(hex:)` failable init — exists as assumed (same file).
- `i18nMessage`, `Args`, `JSONValue`, `store.apply(.createBudgetGroup, …)` — established patterns already in BudgetsTab.swift.

## Build / test results
- `xcodegen generate` — OK (fresh worktree project).
- FinchApp (iOS sim, ios-finch2): `** BUILD SUCCEEDED **`
- FinchMac (macOS, `CODE_SIGNING_ALLOWED=NO`): `** BUILD SUCCEEDED **`
- `xcodebuild test -only-testing:FinchAppTests/BudgetReorderTests`: **12/12 passed**, `** TEST SUCCEEDED **`

## Blockers / notes
- None. Zero deviations from the plan's Task 3 code.
