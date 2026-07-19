# Merchants page — Settings top-level + Merge (Categories-style)

**Date:** 2026-07-19
**Status:** Design approved in discussion; plan follows.
**Scope:** FinchApp UI + **native-first FinchCore merge actions**. Move the Merchants
(counterparties) admin out of Settings › Power Tools to a Settings top-level row,
restyle it to match the Categories/Tags pages, and add **merge** (single +
multi-select). Combines the **Tags move+restyle** pattern
(`2026-07-19-tags-settings-page-design.md`) with the **Categories merge** pattern.

Merchants already has most of the target shape — a detail view
(`CounterpartyDetailView` with stats + transactions), search, count badges, and an
add/rename sheet with the ✕/✓ toolbar — and all needed read selectors already exist
(`counterpartyTxCounts`, `merchantTransactions`). So the net-new work is: the nav
move, a row restyle, and the merge engine + UI.

**Merge is native-first** — exactly like `mergeCategory`/`mergeCategories`, which exist
only on iOS (not in `frontend/lib/db`, not in the parity `WRITE_SEQUENCE`). So:
**no web change, no parity fixtures**; merge is covered by Swift-only unit tests.

`Counterparty` is `{ id, ledgerId, name, isVerified }` — no color, no icon, no order
(name-ordered). Only `entries.counterparty_id` FK-references a counterparty
(`ON DELETE SET NULL`).

**Explicitly out of scope:** drag-reorder (name-ordered list; low value), dissolving
Power Tools (it will hold only Rules after this — a separate call), and rewriting
free-text/name-matched transactions during merge (see Decision 5).

## Decisions

1. **Move out of Power Tools → Settings top-level.** Rename `CounterpartyAdminView` →
   `MerchantsView` (file + struct), matching `CategoriesView`/`TagsView`.
   `SettingsRootList` gains
   `NavigationLink { MerchantsView() } label: { Label("Merchants", systemImage: "storefront") }`
   right after the **Tags** row. `SettingsPowerToolsView` drops its Merchants link →
   **Power Tools = Rules only.** The shared `SettingsRootList` surfaces the row in the
   macOS Preferences window automatically.

2. **Row restyle — name-only** (merchants have no color; per the chosen option). Keep
   the large title and switch search to the shared `SearchableModifier` (used by
   Categories/Tags). Each row: `Text(name)` + the **verified seal** (kept — merchant-only)
   + a trailing **transaction-count pill** (`.quaternary` capsule, `.caption.monospacedDigit()`,
   replacing the `"N×"` text) + a trailing disclosure chevron. Tapping a row navigates to
   `CounterpartyDetailView` (via `.navigationDestination(item:)`, so it can coexist with
   multi-select mode).

3. **Edit/Delete/Merge affordances** (mirror `CategoriesView`). Trailing swipe: **Rename**
   first (accent, full-swipe default) → **Delete** (red) → **Merge…** (orange) — Rename
   outermost so a careless full-swipe never deletes. Context menu: **Rename**,
   **Verify/Unverify** (kept), **Merge…**, **Delete**. Toolbar: `+` (add) and a `⋯` menu →
   **Merge…** (enter multi-select mode). No Reorder. Reuse the existing `CounterpartyNameSheet`
   (name-only add/rename, ✕/✓) unchanged.

4. **Merge — single + multi** (mirror the Categories merge flow):
   - **Single:** swipe/menu **Merge…** → a flat searchable **target-picker sheet** (simpler
     than the category tree picker) → a centered **"Keep which name?"** alert (choose which
     of the two names survives) → `mergeCounterparty`.
   - **Multi:** `⋯` → Merge enters a **select mode** (checkmarks); pick ≥2 → toolbar
     **"Merge (N)"** → a **keep-which-name** dialog listing the picks → `mergeCounterparties`.
   - The keep-which-name choice decides which id is the target (survivor); the other(s) are
     the source(s).

5. **Merge semantics.** `mergeOne(source, target)` reassigns transactions **linked by
   `counterparty_id`** — `UPDATE entries SET counterparty_id = target WHERE counterparty_id
   = source` — then `DELETE` the source counterparty. Because the projection writes the
   canonical counterparty name onto `Tx.merchant`, reassigned transactions immediately show
   the target's name. Transactions that only **name-matched** the source (free-text
   `merchant`, no `counterparty_id`) are **not** rewritten — the predictable choice,
   consistent with `mergeCategory` (which reassigns by id only). The target keeps its own
   `isVerified`; sources are deleted. Only `entries` references a counterparty, and it's
   `ON DELETE SET NULL` (no `RESTRICT` blockers), so no other tables need repointing.

6. **Delete impact.** Keep the centered `.alert`, but add the transaction count via
   `counterpartyTxCounts`: **"Deleting \<name\> — N transactions keep the name but lose the
   merchant link."** (Delete `SET NULL`s `entries.counterparty_id`; the free-text name stays
   on each `Tx`.) Omit the clause when N is 0. Uses the existing `deleteCounterparty`.

7. **Detail view polish.** Keep `CounterpartyDetailView` (stats + transactions). **Drop its
   "See in Activity feed" button** for consistency — the Categories redesign removed the
   equivalent as redundant with the inline transaction list; `TagDetailView` has no such button.

## Components

### `PowerTools/MerchantsView.swift` (renamed from `CounterpartyAdminView.swift`)
- `struct MerchantsView` (was `CounterpartyAdminView`). `@State`: `selectedMerchantId: String?`,
  `showingAdd`, `editing: Counterparty?`, `pendingDelete: Counterparty?`, `search`,
  `errorMessage`, plus merge state mirroring `CategoriesView`: `mergingFrom: Counterparty?`,
  `pendingMerge`, `mergeChoice`, `isSelecting`, `selected: Set<String>`,
  `mergeManySurvivorChoice: [Counterparty]?`.
- `counts = Selectors.counterpartyTxCounts(store.txns, store.merchants, store.activeLedgerId)`.
- `filtered = store.merchants` by name substring (existing logic).
- Row: name + verified seal + count pill + chevron; tap → `selectedMerchantId`; in select
  mode → a leading checkmark toggles `selected`. Swipe/context per Decision 3.
- `.navigationDestination(item: $selectedMerchantId) { id in … CounterpartyDetailView(counterparty:) }`.
- Single-merge target sheet (`sheet(item: $mergingFrom)`) → sets `pendingMerge`; on dismiss →
  `mergeChoice`. Keep-which-name alerts (single + many) mirror `CategoriesView`.
- `merge(source:target:)` → `store.apply(.mergeCounterparty, Args(["sourceId":…, "targetId":…]))`;
  `mergeMany(keeping:from:)` → `store.apply(.mergeCounterparties, Args(["sourceIds": […], "targetId":…]))`.
  Impact counts via `merchantTransactions`/`counterpartyTxCounts` (like `CategoriesView.mergeTxCount`).
- Keep `CounterpartyNameSheet` in this file unchanged. Keep `toggleVerify` / `delete`.

### `PowerTools/CounterpartyDetailView.swift`
- Remove the "See in Activity feed" `Section`/button (Decision 7). No other change.

### `FinchCore/Sources/FinchCore/Store/ActionName.swift`
- Add two **native-first** cases: `mergeCounterparty`, `mergeCounterparties` (near the other
  merge cases). Not added to the web; not in `WRITE_SEQUENCE`.

### `FinchCore/Sources/FinchCore/Store/Domain/Counterparties.swift`
- Register `.mergeCounterparty: merge`, `.mergeCounterparties: mergeMany` in `handlers`.
- `merge(sourceId, targetId)` → `mergeOne`. `mergeMany(sourceIds, targetId)` → loop `mergeOne`
  (throws on empty `sourceIds`).
- `mergeOne(source, target)`: `validateMerge` → `UPDATE entries SET counterparty_id = target
  WHERE counterparty_id = source` → `DELETE FROM counterparties WHERE id = source`.
- `validateMerge(source, target)`: reject self-merge (`error.counterparty.mergeSelf`), require
  both exist (`error.notFound.counterparty`) and **share a ledger** (`error.counterparty.mergeLedger`).

### `Tabs/SettingsTab.swift`
- `SettingsRootList`: add the `MerchantsView()` row after Tags. `SettingsPowerToolsView`:
  remove the Merchants row (leaving Rules).

## Data flow / actions
- **Reads:** `store.merchants` (name-ordered projection), `Selectors.counterpartyTxCounts`,
  `Selectors.merchantTransactions` — all existing.
- **Writes:** existing `createCounterparty` / `updateCounterparty` / `deleteCounterparty` /
  `verifyCounterparty` / `unverifyCounterparty`, plus the two **new** native-first actions
  `mergeCounterparty` / `mergeCounterparties`. No web/parity/CloudKit-mutation-sequence changes.

## i18n
Surgical zh-Hans (same approach as Tags, given the stale-`extracted-keys.json` tooling gap):
add only the new merge/impact strings to `Localizable.xcstrings` + `zh-manual.json`
("Merge…", "Merge \<name\> with…", "Keep which name?", "Keep \"%@\"", "Merge (%lld)", the
merge-impact and delete-impact messages). "Merchants" already exists. Terminology: 商户 / 合并.

## macOS parity
No Mac-specific work: `SettingsRootList` (shared) surfaces the row, `SearchableModifier`
branches per platform, `CounterpartyDetailView` reuses the cross-platform `TxRow`. Build
FinchMac before the PR (a macOS-only break can pass the iOS build).

## Testing
- **`FinchCoreTests`** (Swift-only; no parity fixtures): `mergeCounterparty` reassigns
  `entries.counterparty_id` source→target and deletes source; `mergeCounterparties` folds
  multiple sources; self-merge rejected; missing id rejected; cross-ledger rejected; a merged
  merchant's transactions resolve to the target (via `merchantTransactions`).
- **Manual sim pass:** Merchants is a Settings top-level row (Power Tools = Rules only); rows
  show count pill + verified seal; search; tap → detail; swipe Rename/Delete/Merge; single
  merge (target picker → keep-name) folds counts into the survivor; multi-select merge; delete
  shows the impact count.
- **iOS + macOS** both build.

## Files
- Rename `PowerTools/CounterpartyAdminView.swift` → `PowerTools/MerchantsView.swift` (struct
  rename + restyle + merge UI; keep `CounterpartyNameSheet`).
- Edit `PowerTools/CounterpartyDetailView.swift` (drop "See in Activity feed").
- Edit `FinchCore/.../Store/ActionName.swift` (+2 cases).
- Edit `FinchCore/.../Store/Domain/Counterparties.swift` (+merge handlers) (+ `FinchCoreTests`).
- Edit `Tabs/SettingsTab.swift`.
- `Localizable.xcstrings` + `scripts/zh-manual.json` (surgical zh-Hans).
- `xcodegen generate` (rename enters the project).

## Risks / notes
- **Power Tools becomes single-item (Rules).** Flagged; dissolving it is a separate decision.
- **Native-first divergence.** `mergeCounterparty(+es)` exist only on iOS (like the category
  merges); flag for back-port if the web adopts merchant merge later.
- **Name-match vs id linkage.** Merge folds only `counterparty_id`-linked transactions
  (Decision 5); this is deliberate and documented so it isn't read as a bug.
- **Rule JSON refs not rewritten.** A rule whose action-JSON names a merged *source* id is
  left untouched (it would simply stop matching a live merchant) — mirrors `mergeCategory`,
  rare, acceptable.
