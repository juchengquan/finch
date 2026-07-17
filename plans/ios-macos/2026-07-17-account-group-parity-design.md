# Accounts page: group parity with Budgets (Add-Group sheet, colors, empty groups)

**Date:** 2026-07-17
**Status:** Design + plan written first (user-requested); pending review.
**Scope:** Bring the #481/#485 Budgets group UX to the Accounts page. **No schema change
needed** — #485 deliberately added `color` to *both* group tables (schema + migrations + domain +
web queries), so this is **UI-only**. Verified: `Groups.create` decodes `color` for both tables;
`updateAccount {groupId}` exists (already used by the Accounts reorder editor's persist).

## What Accounts already has (unchanged)
⋯ → **Reorder** (the flat editor) + modal ✕/✓ chrome (#463/#481); group-header long-press
Edit/Delete; header subtotals. The "reorder button changes" half of the ask is already shipped —
this feature covers the remaining Add-Group/Manage-Groups half plus the #485 niceties.

## Changes (mirroring the shipped Budgets implementations)

1. **⋯ → Add Group replaces Manage Groups** (`folder.badge.plus`). Opens `AddAccountGroupSheet`
   — a full-height sheet mirroring Budgets' `AddGroupSheet`: name field · Color swatch row
   (`TagPalette.hexes`, tap-to-toggle) · footer prompt *"Select accounts below to move them into
   this new group (optional)."* (10pt top pad) · an **account picker mirroring the page
   structure** (ungrouped accounts first headerless, then groups in display order; name +
   checkmark rows, 4pt row insets; `.listSectionSpacing(10)` iOS) · standard **✕/✓** toolbar
   icons. On ✓: `createAccountGroup` with explicit id `ag-<uuid8>` + color, then
   `updateAccount {groupId}` for each selected account.
2. **Empty account groups render.** `accountGroupsOrdered` currently derives from the accounts
   list (empty groups can never appear). Switch to `accountGroups.map(\.name)` — mirroring the
   Budgets fix; a new group shows immediately. (`subtotalDisplay` yields $0.00 for an empty
   group — fine; `accounts(in:)` unchanged.)
3. **Color dots**: on the Accounts group headers (before the name, 8pt circle, only when set)
   and on the Accounts reorder editor's collapsed group rows — same as Budgets.
4. **Dead-code removal:** `AccountGroupsView` (AccountManagementViews.swift) loses its only
   presenter; delete it, and with it `Common/GroupAdminView.swift` becomes fully unused
   (Budgets' reference is a comment only — verify, update the comment) — delete both. Group
   rename/delete remain on the header long-press; group reorder remains in the Reorder editor.

## Out of scope
Engine/web changes (none needed); Budgets page (done); GroupAdminView tests (none exist — the
reorder-model tests are separate and untouched).

## Testing
Builds both platforms; sim (ios-finch2): ⋯ shows Add Group (no Manage Groups); sheet creates a
colored group with selected accounts moved in; empty group renders immediately with $0.00
subtotal + dot; reorder editor shows the dot. DB spot-check `account_groups.color`. Human pass
for the sheet/gesture feel.
