# Categories page redesign — Phase 1 (Settings top-level + UI upgrades)

**Date:** 2026-07-19
**Status:** Design approved in discussion; plan follows.
**Scope:** FinchApp UI only — no FinchCore/engine/schema/web change. Rework the
Categories admin page (`CategoryAdminView`), move it out of Power Tools to a
Settings top-level row, and upgrade it (expense/income split, polished
create/edit sheet, dedicated reorder editor, delete polish, cleaner browsing).

This is **Phase 1** of a 3-phase effort (user-approved decomposition). Deferred to
later, separate specs/PRs:
- **Phase 2 — Merge categories** (new engine `mergeCategory` + reassign; no schema change).
- **Phase 3 — Archive / hide** (shared web+iOS schema migration adding `archived` +
  hide-from-pickers everywhere).
- Also deferred (from the original ask): **spending-per-category** figures.

## Decisions

1. **Move out of Power Tools → Settings top-level.** Rename `CategoryAdminView` →
   `CategoriesView` (file + struct), matching `CurrenciesView`. Settings root gains
   `NavigationLink { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }`
   right after Currencies. `SettingsPowerToolsView` drops its Categories link.
2. **Expense / Income split** via a segmented control at the top (default Expense).
   The tree, search, toolbar, and empty state operate on the selected `kind` only.
3. **Create / Edit** = polished **full-height bottom sheet** with ✕/✓ (the Add-Group
   pattern): Name, icon grid (`CategoryIcon`), color swatches (`TagPalette.hexes`),
   footer prompt. New categories inherit the current tab's kind (no kind picker);
   parent preset for subcategory creates. **Kind is fixed on edit** (no expense↔income
   switch — avoids moving a category with transactions across kinds).
4. **Reorder editor** entered via ⋯ → Reorder. Toolbar collapses to a **single ✓
   (Done)** — no ✕ (drags apply immediately, so there is nothing to cancel/revert) —
   and the ledger button is hidden. The tree becomes drag-enabled (the existing
   drag-to-reparent: drop-middle = nest, top/bottom quarter = before/after, "Top level"
   zone un-nests) **only** in this mode; browse mode is tap/swipe only.
5. **Delete polish** = a centered alert (the #500 delete-confirmation style) that spells
   out impact: "Delete \<name\>?" · "N transactions will become uncategorized"
   (+ " · M subcategories move to top level" when the category has children). Allow the
   delete (Merge/Archive don't exist yet). **N = the deleted category's own direct
   transaction count** (`categoryTxCounts[id]`); its subcategories move to top level and
   keep their own transactions, so only direct transactions go uncategorized. M = number
   of direct children. Omit each clause when its count is 0 (a leaf with no transactions
   deletes with a plain "Delete \<name\>?").
6. **Cleaner browsing:** per-kind **empty state**; ⋯ → **Expand all** / **Collapse all**;
   `.searchable` on the current kind (force-expands matches, as today).

## Components (all FinchApp; no engine change)

### `PowerTools/CategoriesView.swift` (renamed from `CategoryAdminView.swift`)
- `@State kind: CategoryKind = .expense` (a small local enum `expense`/`income`; maps
  to the `CategoryRow.kind` string).
- Body: segmented `Picker` (Expense/Income) pinned at top, then the kind-filtered tree
  `List`. `visible` derives from `flattenCategories(categoryForest(rows.filter { $0.kind == kind.rawValue }), …)`.
- Browse row (unchanged structure, minus always-on drag): chevron, icon+color swatch,
  name, `"\(n)×"` count badge, inline `+` (subcategory, depth < 2), tap → edit sheet;
  swipe/context → Edit + Delete.
- `@State editMode`/`isReordering` gates the drag modifiers (`.draggable`/`.dropDestination`)
  and the "Top level" drop zone — present only while reordering.
- Toolbar: browse mode → `+` (add top-level in current kind) + `⋯` (Reorder /
  Expand all / Collapse all); reorder mode → single ✓ done (ledger button hidden).
- Delete via a centered `.alert` (not the row-anchored dialog) with the impact message.
- Empty state when the current kind has no categories.

### `CategoryEditSheet` (rework in the same file)
- Full-height `NavigationStack` sheet, ✕/✓ toolbar (`cancellationAction`/`confirmationAction`
  icons). Sections: Name; Icon (grid); Color (`TagPalette.hexes` swatches + `Color(hex:)`);
  footer prompt. `init` takes `category:` (edit) or `parent:`/`kind:` (create). On create,
  kind = current tab; on edit, kind is read-only. Save via `createCategory`/`updateCategory`
  (unchanged chokepoints).

### Settings wiring
- `SettingsTab.swift`: add the Categories root row; remove `NavigationLink("Categories") { … }`
  from `SettingsPowerToolsView`.

## Copy (new strings → zh-Hans batch)
- "Categories" (Settings row + nav title — already localized), "Expense"/"Income"
  (segment labels — already localized), "Expand all", "Collapse all", "Reorder",
  "No expense categories yet", "No income categories yet",
  "%lld transactions will become uncategorized", "%lld subcategories move to top level",
  "Add subcategory" (exists). New ones join the accumulated batch.

## Error handling
- Create/edit/delete failures surface via the existing `errorAlert(i18nMessage(error))`.
- Reorder moves reuse `applyMoves` (already stops on first engine error).
- Kind fixed on edit removes the cross-kind reparent hazard.

## Testing
- **Unit (FinchAppTests):** existing `CategoryReorder` tests unchanged; new pure helper
  `deleteImpactMessage(txCount:subcatCount:)` (builds the warning string) unit-tested;
  kind-filter is a one-line `filter`, covered by the reorder/forest tests indirectly.
- **Builds:** FinchApp + FinchMac.
- **Sim (ios-finch2):** Settings root shows Categories (Power Tools doesn't); segmented
  toggle switches the tree; `+`/inline-`+` create via the full-height sheet; ⋯ → Reorder
  enters drag mode with only ✓; ⋯ → Expand/Collapse all; delete shows the impact warning.

## Out of scope (Phase 1)
Merge (P2), archive/hide (P3), spending-per-category, web changes, engine/schema changes,
localization batch (strings tracked, translated separately).
