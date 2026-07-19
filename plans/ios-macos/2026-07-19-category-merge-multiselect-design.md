# Multi-select category merge — design

**Date:** 2026-07-19
**Status:** Design approved in discussion; plan follows.
**Scope:** Native iOS only — a new **`FinchCore` action `mergeCategories`** (atomic, multi-source) plus a **multi-select "Merge" mode** on the Categories page. Builds on the pairwise merge (#511). No schema change. No web change (web parity later).

## Purpose

The pairwise merge (#511) combines two categories at a time. When several duplicates exist ("Food", "Dining", "Meals"), folding them together means repeating the pairwise flow. Multi-select lets the user pick many at once and combine them into one in a single, atomic action.

## Model

Enter a **select mode** from the ⋯ menu, tick **two or more** same-kind categories, then choose **which name survives**; every other selected category is absorbed into the survivor. It's the pairwise merge generalized to N sources and one target — the survivor keeps its own icon / color / parent, and only the name choice picks which selected category survives.

## Decisions

1. **Survivor chosen at the end.** Selection uses plain checkmarks; after tapping "Merge (N)" a prompt lists the **selected names** (single-choice) and you pick which to keep. (Confirmed over marking a "primary" during selection.)
2. **Selections must be mutually unrelated.** Selecting a category **disables its ancestors and descendants** in the list. You combine unrelated peers, never a category together with its own parent/child — that is subtree-flattening (out of scope) and is exactly the case the engine's "can't merge into a descendant" guard would trip.
3. **Atomic engine action `mergeCategories(sourceIds, targetId)`** — repoints **all** sources → target in **one transaction** (all-or-nothing), rather than looping the pairwise action from the UI (which would not be atomic across the set and could leave a half-merged state on a mid-way failure).
4. **Keep both entry points.** The per-row swipe / context "Merge…" (fast pairwise, #511) stays; ⋯ → "Merge…" is the new multi-select path for combining 3+.
5. **Same-kind only.** The page is already kind-filtered, so all selectable rows share the current kind; the engine backstops it.

## UI flow (FinchApp — `CategoriesView`)

1. **Enter select mode:** ⋯ → **"Merge…"** sets an `isSelecting` flag (mirrors the existing reorder-mode toolbar collapse). Each browse row shows a leading **selection circle**; tapping a row toggles its membership in a `selected: Set<String>`. Rows that are an **ancestor or descendant of any selected row are disabled** (dimmed, non-tappable). Tap-to-transactions, swipe, and drag are suppressed in this mode.
2. **Toolbar (select mode):** a **"Merge (N)"** confirmation button (enabled only when `selected.count >= 2`) and a **Cancel** (✕) that clears the selection and exits.
3. **Survivor prompt:** "Merge (N)" opens a prompt titled **"Keep which name?"** listing the selected categories' names as single-choice options, with the combined **"X transactions will be combined"** line (`mergeImpactMessage` over the union of the selected categories' `categoryTransactions`). Picking a name → **Merge**; Cancel dismisses.
4. **Execute:** call `mergeCategories(sourceIds: selected − survivor, targetId: survivor)` via `store.apply`. On success, clear selection and exit select mode. Failures surface through the existing `errorAlert(i18nMessage(error))`.

## Engine action `mergeCategories` (FinchCore — `Store/Domain/Categories.swift`)

New action `mergeCategories` with args `{ sourceIds: [String], targetId: String }`. **Refactor** the existing pairwise `mergeCategory` handler by extracting its per-source body (repoint postings, scheduled templates, scheduled splits, budget id-lists; re-parent children under target with the depth-cap fallback) into a private helper `mergeOne(_ db:, source:, target:)`. Then:

- `mergeCategory` (unchanged behavior) calls `mergeOne` once, then deletes the one source.
- `mergeCategories` validates, then in the single `Apply.apply` write transaction calls `mergeOne` for **each** source and deletes **all** sources at the end.

**Guards (throw → whole transaction rolls back):** `sourceIds` non-empty; `targetId` not among `sourceIds`; every source and the target share one kind; for each source, `target` is not a descendant of it (`isInSubtreeOf` backstop — normally prevented by the unrelated-selection rule). Because guards run before any write and the action is one transaction, a rejection leaves the data untouched (atomic).

## Copy (new strings → zh-Hans batch)

`"Merge…"` (exists), `"Keep which name?"` (from #511's "Keep which name after merge?" — reuse or a short variant), `"Merge (%lld)"`, and the existing `"%lld transactions will be combined"` / singular. New keys join the tracked batch.

## Error handling

- Guard violations throw localized engine errors surfaced by `errorAlert`; the atomic transaction means no partial merge.
- The unrelated-selection UI rule keeps the descendant guard from tripping in normal use; the engine guard is the backstop.

## Testing

- **FinchCore (`CategoryMergeMultiTests`):** two-plus sources all repoint to target (transactions, incl. a split leg); children re-parent under target; a guard failure (e.g. cross-kind, or target in sourceIds) rolls back with **nothing** merged (atomicity); the refactor leaves the existing `CategoryMergeTests` (pairwise) green.
- **FinchApp:** the survivor prompt reuses the already-tested `mergeImpactMessage`; the selection-disable predicate (ancestor/descendant of a selected row) is a small pure helper worth a unit test.
- **Builds:** FinchApp + FinchMac.
- **Sim (ios-finch2):** ⋯ → Merge → tick three expense categories → "Merge (3)" → keep one name → the other two disappear and their transactions show under the survivor.

## Action-count note

`mergeCategories` is a new native-only action → bump `ArgsTests.test_actionCount` (78 → 79 once #511 has merged) and register the handler in `Categories.handlers` (`ApplyTests` covers registration dynamically). Same class of change that broke CI in #494 — do not skip.

## Out of scope

Subtree flattening (merging a category with its own parent/child), web parity for `mergeCategories`, archive/hide (Phase 3), spending-per-category, and any schema change. Localization is tracked but translated separately.
