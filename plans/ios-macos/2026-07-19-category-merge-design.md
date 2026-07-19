# Category merge — design (Phase 2 of the Categories work)

**Date:** 2026-07-19
**Status:** Design approved in discussion; plan follows.
**Scope:** Native iOS only — a new **`FinchCore` engine action `mergeCategory`** plus
**`FinchApp` UI** on the Categories page. No schema change. No web change (web can get
parity later). This is **Phase 2** of the Categories effort; **archive/hide remains
Phase 3**.

## Purpose

Combine two duplicate categories into one. Today the engine has only
create / update / delete for categories — there is no merge. Users who end up with
two categories that mean the same thing ("Food" and "Dining") have no way to fold one
into the other; deleting one just uncategorizes its transactions.

## Model

Merge combines **two same-kind categories into one**. One category **survives**; the
other is **absorbed and removed**. Every reference the absorbed category held repoints
to the survivor. The survivor keeps its own icon / color / parent — **the only choice
the user makes is which name to keep**, which is equivalent to choosing which of the
two survives.

- "Keep A's name" → survivor = A, absorbed = B.
- "Keep B's name" → survivor = B, absorbed = A.

The engine action always merges an **absorbed (`source`) into a survivor (`target`)**;
the UI decides which is which from the name choice.

## Decisions

1. **Same-kind only.** You can only merge an expense category with another expense
   category (and income with income). The picker offers only same-kind targets; the
   engine backstops it.
2. **Name is the only choice.** The survivor keeps its own icon, color, and parent.
   The name-choice simply selects which category survives — no attribute-by-attribute
   merge, no rename step.
3. **Absorbed category's subcategories move _under the survivor_**, falling back to
   **top level** for any child that would break the 3-level nesting cap (reusing the
   existing `categoryDepth` / `subtreeDepth` guards).
4. **Deletion-style confirmation prompt** with the two name choices (see UI Flow).
5. **All references repoint** to the survivor in one atomic transaction: transaction
   legs (including split legs), scheduled templates and scheduled splits, and budget
   category-id lists.

## UI flow (FinchApp — `CategoriesView`)

1. **Entry point:** a **"Merge…"** action in each category row's **context menu**
   (long-press) and **trailing swipe** (alongside Edit / Delete).
2. Choosing "Merge…" for category **A** opens a **target picker** — a sheet/menu listing
   the current kind's other categories, **excluding A itself and A's descendants**
   (reusing the parent-picker's self+descendant exclusion, but **not** its `depth < 2`
   filter — a merge target may be at any depth, including an ancestor of A). The user
   picks the other category **B**.
3. A centered **`.alert`** (the #500 window-level pattern) appears:

   > **Keep which name after merge?**
   > *N transactions will be combined into one category.*
   > `[ Keep "A" ]`  `[ Keep "B" ]`  `[ Cancel ]`

   The count line comes from a pure helper `mergeImpactMessage(txCount:)` where
   `txCount` is the **choice-independent union** of transactions referencing either
   category (so the message is the same regardless of which name wins). Pluralized
   ("1 transaction will be combined…"); omitted when 0.
4. Tapping **Keep "A"** calls `merge(source: B, target: A)`; **Keep "B"** calls
   `merge(source: A, target: B)`. Errors surface through the existing
   `errorAlert(i18nMessage(error))`.

## Engine action `mergeCategory` (FinchCore — `Store/Domain/Categories.swift`)

New action `mergeCategory` with args `{ sourceId: String, targetId: String }` (source is
absorbed, target survives). Registered in `ActionName` and the Categories `handlers`
map. In a **single DB transaction**:

1. Repoint transaction legs: `UPDATE postings SET category_id = target WHERE
   category_id = source` (covers split legs too).
2. Repoint scheduled references: `UPDATE scheduled_templates SET category_id = target
   WHERE category_id = source` and `UPDATE scheduled_splits SET category_id = target
   WHERE category_id = source` — the latter clears the `ON DELETE RESTRICT` reference
   that would otherwise block the delete.
3. Rewrite budgets: for each budget whose `category_ids` JSON contains `source`, replace
   `source` with `target` and **de-duplicate** the list.
4. Re-parent the source's children: for each `child WHERE parent_id = source`, set
   `parent_id = target` when the resulting subtree stays within the 3-level cap;
   otherwise set `parent_id = NULL` (top level).
5. `DELETE FROM categories WHERE id = source`.

**Guards (throw a localized error):** `source == target`; `target` is a descendant of
`source` (would create a cycle when children re-parent); `source.kind != target.kind`;
either id missing.

**Accepted edge case:** a transaction (or budget) that already referenced **both**
source and target ends up with two legs / a de-duplicated id pointing at target — legs
sum correctly and the id list is de-duplicated; no special consolidation beyond dedup.

## Components / files

- **`FinchCore/Store/ActionName.swift`** — add `case mergeCategory`.
- **`FinchCore/Store/Domain/Categories.swift`** — `mergeCategory` handler + register it;
  reuse `categoryDepth` / `subtreeDepth` for the child-reparent depth check.
- **`FinchCore/Tests/FinchCoreTests/CategoryMergeTests.swift`** — engine tests (below).
- **`FinchCore/Tests/FinchCoreTests/ArgsTests.swift` + `ActionCoverageTests.swift`** —
  the new action changes the action count and coverage set; update both (this is the
  same class of change that broke CI in #494 — do not skip).
- **`FinchApp/PowerTools/CategoriesView.swift`** — "Merge…" swipe + context action,
  the target picker, the keep-which-name `.alert`, and the `merge(source:target:)` call
  through `store.apply(.mergeCategory, …)`.
- **`FinchApp/PowerTools/CategoryMergeImpact.swift`** — pure
  `mergeImpactMessage(txCount:)` (mirrors `deleteImpactMessage`).
- **`FinchApp/Tests/FinchAppTests/CategoryMergeImpactTests.swift`** — helper tests.

## Copy (new strings → zh-Hans batch)

"Merge…", "Keep which name after merge?", `Keep "%@"`,
"%lld transactions will be combined", "1 transaction will be combined". New keys join
the tracked batch (translated separately).

## Error handling

- Same-kind, self, and descendant violations throw localized engine errors surfaced by
  `errorAlert`.
- The whole merge is one transaction: any failure rolls back — no half-merged state.

## Testing

- **FinchCore (`CategoryMergeTests`):** transaction legs repoint (including a split leg);
  scheduled template **and** scheduled-split repoint so the `RESTRICT` no longer blocks
  the delete; budget `category_ids` rewrite + dedup; child re-parent under target;
  child re-parent depth-fallback to top level; self-merge rejected; descendant-target
  rejected; cross-kind rejected; source row is gone afterward.
- **FinchApp (`CategoryMergeImpactTests`):** `mergeImpactMessage` singular/plural/zero.
- **Builds:** FinchApp + FinchMac.
- **Sim (ios-finch2):** merge two expense categories via swipe → pick target → keep-name
  prompt → the absorbed category disappears and its transactions show under the survivor.

## Out of scope (Phase 2)

Archive / hide (Phase 3), web parity for `mergeCategory`, spending-per-category figures,
consolidating duplicate legs beyond de-dup, and any schema change. Localization is
tracked but translated separately.
