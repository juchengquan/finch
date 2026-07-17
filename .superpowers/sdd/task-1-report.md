# Task 1 report — AccountsTab Add Group sheet + empty groups + dots

**Status:** DONE. Commit `7f45b4f` on `feat/ios-account-group-parity` (no Co-Authored-By; 2 files only).

**Build:** iOS `** BUILD SUCCEEDED **` (xcodegen generate + FinchApp scheme, iPhone 17 Pro sim).

## Changes
1. `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift` — `accountGroupsOrdered` now `accountGroups.map(\.name)` with a doc comment mirroring `budgetGroupsOrdered` (includes EMPTY groups — a freshly added group shows immediately). `accounts(in:)`, `subtotalDisplay`, `ungroupedAccounts` untouched.
2. `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`:
   - ⋯ Manage Groups item → Add Group (`folder.badge.plus`, `addingGroup = true`), mirroring BudgetsTab's.
   - State `showingGroups` → `addingGroup = false`; `.sheet(isPresented: $addingGroup) { AddAccountGroupSheet() }` replaces the AccountGroupsView presentation.
   - `AddAccountGroupSheet` (private) appended — faithful adaptation of BudgetsTab's `AddGroupSheet`: "Group name" TextField · Color section (TagPalette.hexes swatches, tap-toggle, header "Color", footer "Select accounts below to move them into this new group (optional)." with 10pt top pad) · picker mirroring the page (ungrouped headerless first via `store.ungroupedAccounts`, then `store.accountGroupsOrdered` sections with `store.accounts(in: g)`, empties skipped) · Button rows `a.name ?? "—"` + trailing checkmark, insets 4/20 · `.listSectionSpacing(10)` in the iOS block · ✕/✓ toolbar (✓ disabled on empty name, a11y "Cancel"/"Add") · `add()`: `ag-<uuid8>` via `.createAccountGroup` (+color when set), then `.updateAccount` groupId patch per selected account, errors → `i18nMessage`.
   - Color dots: 8pt circle before the group name in `groupedSections`' header (resolved by name via `store.accountGroups ... ?.color` + `Color(hex:)`) and in `reorderList`'s real-group rows (resolved by gid) — both mirror BudgetsTab's two dot sites exactly.

## Adaptations beyond the letter of the plan
- Updated the file-top doc comment ("manage groups" → "add group") so it no longer states a removed menu item.
- Footer string "Select accounts below to move them into this new group (optional)." is new to the catalog → zh batch note (already flagged in the plan's self-review).
- `AccountGroupsView` / `GroupAdminView` NOT touched (Task 2's scope).

## Blockers
None.

---

*Note: this file previously held the Task 1 report of the group-color plan (commit 5af3264); superseded by the account-group-parity plan's Task 1.*
