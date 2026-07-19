# Phase 1 — Categories & Tags copy between ledgers

**Date:** 2026-07-19
**Status:** Design approved (grill-me); plan follows.
**Scope:** FinchApp UI + **native-first copy actions**. Categories and Tags **stay
per-ledger**; add three affordances to remove the "re-create everything in each ledger"
friction — all as additive, dedup-by-name **copies into the target ledger**. **No schema
change, no web/parity impact** (copies get the target's `ledger_id`; isolation intact).
Roadmap: `2026-07-19-ledger-reference-model-roadmap.md`.

**Not in this phase:** Merchants (going global in Phase 2 — copying them now would be
throwaway) and Currencies (already global — nothing to copy).

## The three affordances

1. **Clone-on-create** — the new-ledger flow (`WriteScreens/LedgerManagementView.swift`)
   gains a **"Start from"** picker: *Blank* (default) or an existing ledger. On a non-blank
   choice, seed the new ledger's Categories + Tags from the source.
2. **Import from another ledger** (whole-domain) — a `⋯` → **"Import from [ledger]…"** action
   on `CategoriesView` and `TagsView`: pick a source ledger, additively add its missing items.
3. **Copy to another ledger** (single item) — a swipe/context **"Copy to [ledger]…"** on a
   single category or tag row: copy just that one into a chosen target.

All three call the same primitive (below), differing only in *what set* they pass.

## Semantics (decided)

- **Additive + dedup by name**, case-insensitive. Only items whose name is absent in the
  target are inserted; existing items are never modified or deleted. Idempotent.
- **System categories are never copied** (`categories.system IS NOT NULL` — the per-ledger
  `opening`/`adjustment`/`fx` equity rows are auto-created for every ledger).
- **Category tree preserved:** copy user categories with their `kind`, `sort_order`,
  `icon`, `color`, and re-mapped `parent_id` (new ids in the target; a child whose parent
  was skipped-as-duplicate re-points to the existing target parent of the same name).
- **Tags** copy `name` + `color`.
- Copies get **new ids** and the **target `ledger_id`**; never reuse source ids (they belong
  to the source ledger).

## Engine — native-first copy actions (`FinchCore`)

Mirror the merge precedent (iOS-only, Swift unit tests, no web parity, no fixtures). Add to
`ActionName` + the relevant domain handlers:

- `copyCategories` — args `{ fromLedgerId, toLedgerId, ids?: [String] }`. Without `ids`, copies
  all user categories of `fromLedgerId`; with `ids`, only those (used by single-item "Copy to").
  Resolves the tree in dependency order (parents before children); dedups by
  `(kind, parentName, name)`; skips system rows.
- `copyTags` — args `{ fromLedgerId, toLedgerId, ids?: [String] }`. Dedup by name.

(Two actions, or one `copyLedgerReference { domains, fromLedgerId, toLedgerId, ids? }` — the
plan picks; two focused actions are simpler to test.) Both are pure INSERTs against existing
tables; the cross-ledger audit is unaffected (copies carry the correct `ledger_id`).

## UI

- **`LedgerManagementView`** create-ledger form: a `Picker("Start from")` (Blank + one row
  per other ledger). On save, `createLedger` then (if non-blank) `copyCategories` +
  `copyTags` from the picked source.
- **`CategoriesView` / `TagsView`:** `⋯` menu gains **"Import from…"** → a ledger picker sheet
  → `copyCategories`/`copyTags` (whole domain). Row swipe/context gains **"Copy to…"** →
  ledger picker → same action scoped to `ids: [row.id]`. A toast/confirmation reports "N added".

## Testing

- `FinchCoreTests` (Swift-only, no fixtures): `copyCategories` adds missing user categories
  with the tree preserved and dedups by name; never copies system rows; re-import is a no-op;
  `ids`-scoped copy adds only the named item (and its ancestors, so the tree stays valid).
  `copyTags` adds missing tags, dedups, idempotent. Cross-ledger audit stays clean after copy.
- iOS + macOS build. Manual sim: clone-on-create seeds a new ledger; import/copy on both pages.

## Out of scope
Merchants (Phase 2), Currencies (already global), per-item *selection UI* beyond single-row
"Copy to" (whole-domain import covers the rest), any schema change.
