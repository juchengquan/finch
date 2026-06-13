# 3-level categories — plan

Status: **shipped** (2026-06-06). This doc is kept as the design record.
The implementation followed the §7 commit split (backend + UI Select
sweep + admin page) and the §9 file touch list.
Scope: `frontend/` (server-backed SQLite app)

> Relaxes the existing 2-level category constraint to **3 levels** (e.g.
> `Food › Restaurants › Japanese`). The cap is currently enforced in the
> mutation layer (`lib/db/mutations.ts::assertCanBeParent`), not in SQL —
> so this is a behaviour change, not a schema change. Existing 2-level
> data carries forward untouched; the *capability* opens at 3.
>
> Cross-app: native (per `IOS_MACOS_PLAN.md`) inherits the same mutation
> guard; the schema convention is unchanged so `.finch` packs continue to
> round-trip cleanly.

The taxonomy has been "exactly 2 levels deep" since the categories table
shipped (`lib/db/schema.ts` ~line 96, schema comment: *"a non-NULL value
must itself reference a top-level row — no grandchildren — enforced in
the mutation layer"*). In practice users want more structure:
`Transport › Car › Fuel` or `Food › Restaurants › Japanese`. This plan
relaxes the cap to 3 without giving up the cap altogether (the picker
becomes unusable on mobile beyond that, and roll-up reporting gets
incomprehensible).

---

## 0. Confirmed product decisions

Decided going in; anything else is an open question (§11).

1. **Hard cap at depth 3.** A category chain (root → leaf) MUST be ≤ 3
   nodes. Beyond that the UI suffers and reports become opaque. Three
   covers the realistic taxonomy cases.
2. **Recursive matching for budgets.** A budget with `category_ids =
   ['food']` matches direct `food` transactions AND every descendant
   (`food › restaurants`, `food › restaurants › japanese`, …). Matches
   user intuition. The behaviour change for existing 2-level budgets is
   benign (a parent budget now also catches its child rows — which is
   what the user usually already wanted).
3. **Category Select widget: flat list with separators.** Render labels as
   `Food › Restaurants › Japanese`. The picker stays a flat searchable
   list — no two-step navigation, no tree expansion. Lowest-friction on
   mobile; supports keyboard search; scales to depth 3 cleanly. The
   existing `<Select>` everywhere it appears just gets the new label
   format.
4. **No SQL trigger to enforce the depth cap** (mutation layer only).
   Same posture as the current 2-level rule. See §12 for the future-
   work note describing the trigger if we ever decide we need a hard
   SQL invariant.
5. **No schema change. No `SCHEMA_VERSION` bump.** Only a doc comment
   update on the `categories` table. Existing 2-level rows are valid in
   the new world; future 3-level rows are valid; packs round-trip.
6. **Seed data stays 2-level.** Don't fabricate sample 3-level
   categories. Users add as needed.

---

## 1. Current state

### Schema (`lib/db/schema.ts`)

```sql
CREATE TABLE categories (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  parent_id  TEXT REFERENCES categories(id) ON DELETE SET NULL,
  -- ... kind / icon / color / sort_order / timestamps ...
);
```

`parent_id` is just an FK with no depth enforcement. The 2-level cap
lives in `lib/db/mutations.ts::assertCanBeParent` which throws when the
parent itself has a parent.

### What already works (keep, don't rebuild)

- **Schema**: no change needed. FK + cascade behaviour (SET NULL on
  parent delete → promotes children up one level) continues to apply at
  every level.
- **Mutations**: `createCategory` / `updateCategory` / `deleteCategory`
  all unchanged in shape — only the guard semantics change.
- **Splits**: `transaction_splits.category_id` references any category at
  any depth; no change.
- **Rules**: `set_category` actions point at a category id; depth-blind.
- **Tags**: orthogonal to categories; no change.

### Gaps that 3-level surfaces

| Layer | What changes |
|---|---|
| `assertCanBeParent` | Becomes a depth check (chain ≤ 3) instead of "parent has no parent" |
| `rollupCategorySpend` | Walks the tree recursively, folds grandchild → child → parent |
| Budget category filter | Expands the configured id set to include all descendants before matching |
| `<Select>` Category options | Labels render as `Parent › Child › Leaf`; sorted by path |
| `/categories` admin page | Sub-subcategory rows + create/edit/delete affordance |
| Cross-app schema doc | `categories.parent_id` comment updated from "2-level" to "≤ 3-level" |

---

## 2. What changes vs. what doesn't

| Layer | Changes? |
|---|---|
| Database schema | No (comment update only) |
| Migrations | No |
| `.finch` pack format | No |
| Database routes | No |
| `createCategory` / `updateCategory` / `deleteCategory` mutation shapes | No |
| `lib/db/mutations.ts::assertCanBeParent` | Replaced — depth check |
| `lib/select.ts::rollupCategorySpend` | Recurse the tree |
| `lib/select.ts::budgetProgress` matcher | Expand `categoryIds` to include descendants (recursive) |
| Category `<Select>` usages | New `categoryPath()` helper for labels; sort by path |
| `/categories` page UI | Render the third level + affordance to add it |
| Existing 2-level data | Stays valid; nothing migrates |
| Seed data | Stays 2-level |
| Tests | New unit tests for depth-3 guard, recursive rollup, recursive budget match |

---

## 3. Depth enforcement (the mutation guard)

Replace `assertCanBeParent` with a depth check. A new category whose
`parent_id = X` becomes part of the chain rooted at X; the resulting
depth = depth(X) + 1. For depth ≤ 3, we need depth(X) ≤ 2.

```ts
// Compute the depth of a category by walking parent_id chain to the root.
// Top-level = depth 1.
async function categoryDepth(exec: Exec, id: string): Promise<number> {
  let cur: string | null = id;
  let depth = 0;
  // Bounded walk: with a depth-3 cap we never traverse more than 3 hops.
  // Add a small safety bound to defend against a malformed cycle in a
  // future hand-edited DB.
  while (cur != null && depth < 10) {
    const rows = await exec('SELECT parent_id FROM categories WHERE id = ?', [cur]);
    if (!rows.length) throw new Error('Category does not exist');
    depth++;
    cur = rows[0].parent_id == null ? null : String(rows[0].parent_id);
  }
  return depth;
}

/** A new child of `parentId` is allowed only when the chain from the root
 *  to parentId is ≤ 2 (so the child becomes at most depth 3). Also called
 *  on `updateCategory` if `parent_id` is moving. */
async function assertCanBeParent(exec: Exec, parentId: string): Promise<void> {
  const d = await categoryDepth(exec, parentId);
  if (d >= 3) throw new Error('Categories nest at most three levels deep');
}
```

`updateCategory` already calls `assertCanBeParent` when `parentId` is
changing; the new guard automatically catches "moving a level-3 node
under another level-3 node would create depth 4."

**Cycle defense**: a malformed DB with a cycle would loop forever. The
`depth < 10` bound is a safety net (the real cap is 3; 10 is just "way
more than possible"); cycles can't arise from the mutation layer because
every CREATE specifies a parent id that already exists.

---

## 4. Roll-up behavior (selectors + budgets)

### 4.1 `rollupCategorySpend`

Currently folds direct children's totals into their parents (one level).
For 3 levels, do a tree walk: each parent's total = own direct spend +
sum of each child's *rolled-up* total. Memoise per call.

Sketch:

```ts
function rollupCategorySpend(
  byCat: Record<string, number>,
  categories: CategoryRow[],
): Record<string, number> {
  const childrenOf = new Map<string, string[]>();
  for (const c of categories) {
    if (c.parentId) {
      (childrenOf.get(c.parentId) ?? childrenOf.set(c.parentId, []).get(c.parentId)!)
        .push(c.id);
    }
  }
  const memo = new Map<string, number>();
  function totalOf(id: string): number {
    if (memo.has(id)) return memo.get(id)!;
    let t = byCat[id] ?? 0;
    for (const child of childrenOf.get(id) ?? []) t += totalOf(child);
    memo.set(id, t);
    return t;
  }
  const out: Record<string, number> = {};
  for (const c of categories) out[c.id] = totalOf(c.id);
  return out;
}
```

### 4.2 Budget category-id matching

Budgets store `category_ids: string[]`. Today the matcher checks
`set.has(t.category)`. Change: **expand the configured ids to include
all descendants** before the matcher runs, once per budget calc (not
per transaction).

Where: `budgetProgress(budget, txns, today)` signature gains a
`categories: CategoryRow[]` parameter. It builds the descendant set,
then runs the existing matcher unchanged.

Callers of `budgetProgress` already have `categories` in scope (it's
projected on every page that uses budgets), so the threading is local.

```ts
function expandDescendants(
  ids: string[],
  categories: CategoryRow[],
): Set<string> {
  const out = new Set(ids);
  const childrenOf = new Map<string, string[]>();
  for (const c of categories) {
    if (c.parentId) {
      (childrenOf.get(c.parentId) ?? childrenOf.set(c.parentId, []).get(c.parentId)!)
        .push(c.id);
    }
  }
  const stack = [...ids];
  while (stack.length) {
    const cur = stack.pop()!;
    for (const child of childrenOf.get(cur) ?? []) {
      if (!out.has(child)) {
        out.add(child);
        stack.push(child);
      }
    }
  }
  return out;
}
```

**Behaviour change for existing budgets**: a 2-level budget on `food`
now also catches transactions categorised as `food › restaurants` —
which is what most users intended. Surface this in the release notes
of the implementation PR.

---

## 5. UI surfaces

### 5.1 Category `<Select>` widget — flat with separators

Every place that lists categories for selection (Add transaction, Edit
transaction, Transaction Detail recategorize, Split editor, Budget form
filter, Rule builder) renders the option label as the **path from root**
joined with ` › `:

```
Food
Food › Restaurants
Food › Restaurants › Japanese
Food › Restaurants › Thai
Food › Groceries
Transport
Transport › Car
Transport › Car › Fuel
```

Sorted by path so siblings cluster, and a parent always appears
immediately before its children.

A small helper:

```ts
// New helper in lib/data.ts or lib/select.ts.
function categoryPath(c: CategoryRow, byId: Map<string, CategoryRow>): string {
  const parts: string[] = [c.name];
  let cur = c.parentId;
  while (cur) {
    const p = byId.get(cur);
    if (!p) break;
    parts.unshift(p.name);
    cur = p.parentId;
  }
  return parts.join(' › ');
}
```

Every existing usage of `<SelectItem>{c.name}</SelectItem>` becomes
`<SelectItem>{categoryPath(c, byId)}</SelectItem>`. Mechanical sweep.

### 5.2 `/categories` admin page

Currently: top-level cards, with subcategory rows inline beneath each.
For 3 levels, subcategory rows gain a chevron / expand affordance; the
expanded state shows level-3 rows indented + a "New sub-subcategory"
button.

UI shape:

```
Food                                        [edit] [delete] [new sub]
├ Restaurants                       ▾  [edit] [delete]
│  ├ Japanese                           [edit] [delete]
│  ├ Thai                                [edit] [delete]
│  └ + New sub-subcategory
├ Groceries                         ▸  [edit] [delete]
└ + New subcategory
```

shadcn `Accordion` or `DisclosureGroup` handles the expand state. Color
inheritance: when level-3 has no color, fall back to its parent's color
(same fallback level-2 uses today).

The existing "create category" dialog gains a `parent` Select that
accepts any depth-≤2 category (the mutation guard rejects depth-3
parents anyway, but we should disable them in the UI for a better hint).

---

## 6. Edge cases

- **Moving a subtree**: `updateCategory({ parentId: X })` re-runs
  `assertCanBeParent`. If the subtree being moved already has depth
  > 1, the resulting chain might exceed 3 even if X is currently a
  valid parent. The guard must consider the **subtree's own depth**
  too — not just the parent's depth. New helper:

  ```ts
  // Depth of the subtree rooted at `id`, walking children downward.
  async function subtreeDepth(exec: Exec, id: string): Promise<number> { … }

  // When moving id under parentId: total = depth(parentId) + subtreeDepth(id) ≤ 3.
  ```

  Tests must cover: moving a level-2 node (with level-3 children) under
  another level-1 node fails — that would make the children level-4.

- **Splits across depths**: a transaction split between `Food › Restaurants`
  and `Food › Groceries` is now a normal pattern; existing split editor
  handles any category id, no UI work.

- **Cascade behaviour on parent delete**: `parent_id` is `ON DELETE SET NULL`
  — deleting `Food` promotes `Restaurants` and `Groceries` to top-level,
  AND promotes `Japanese` from level-3 to level-2 (because its parent
  `Restaurants` moves up). No data loss. Same semantics as today, just
  applied recursively.

- **Color inheritance with three levels**: a level-3 node without a
  color falls back to its parent's color (which itself may fall back to
  the grandparent's). Today's resolver only walks one level; sweep to
  walk to the root.

- **Recursive rollup performance**: at ledger scale (≤ a few hundred
  categories, ≤ tens of thousands of transactions), the memoised tree
  walk is O(category_count) once per call. Negligible.

- **Rule engine actions**: `set_category` already accepts any id; no
  change. A rule that sets a level-3 category implicitly contributes to
  the level-1 and level-2 rolled-up totals — which is correct.

---

## 7. Implementation order (suggested commit split)

Each step ends with the validation gate green
(`bun run typecheck`, `bun run lint`, `bun test lib`, `bun run build`).

1. **Backend: depth enforcement + recursive selectors + tests.**
   - Rewrite `assertCanBeParent` as a depth check + `subtreeDepth` for the
     move case.
   - Recursive `rollupCategorySpend`.
   - `expandDescendants` helper; `budgetProgress` signature gains
     `categories`.
   - Color resolver walks to the root.
   - Schema comment update on `categories.parent_id` (2-level → ≤ 3-level).
   - Tests cover: create level-3 OK; create level-4 rejected; move
     subtree that would exceed depth 3 rejected; rollup folds grandchild
     into parent; budget `['food']` catches `food › restaurants ›
     japanese` row.
2. **UI: Category `<Select>` widget — flat-with-separators sweep.**
   - `categoryPath()` helper.
   - Every `<SelectItem>{c.name}</SelectItem>` for categories swept to
     `categoryPath(c, byId)`. Sorted by path.
   - Add/Edit transaction, Transaction Detail recategorize, Split editor,
     Budget form filter, Rule builder. Mechanical.
3. **UI: `/categories` admin page — third-level rendering + add affordance.**
   - Subcategory rows gain expand/collapse.
   - "New sub-subcategory" button per subcategory.
   - Edit dialog's `parent` Select disables depth-3 categories.
   - Visual polish for the deeper nesting.
4. **Housekeeping**: move plan to `plans/done/`, update `MASTER_PLAN.md`,
   `IOS_MACOS_PLAN.md §3` row 29.

Total: 3 code commits + 1 docs commit. Roughly a small-to-medium PR.

---

## 8. Tests

- **Depth guard**:
  - Create category with `parent_id = null` → success (level 1).
  - Create category under a level-1 parent → success (level 2).
  - Create category under a level-2 parent → success (level 3).
  - Create category under a level-3 parent → rejected with "Categories
    nest at most three levels deep".
- **Subtree move**:
  - Move a level-2 node (with a level-3 child) under another level-1 node
    → success (result: levels 2 and 3 of the new chain).
  - Move a level-2 node (with a level-3 child) under another level-2 node
    → rejected (would create level-4).
- **Recursive rollup**:
  - Sum of grandchild's direct spend + child's direct spend + parent's
    direct spend appears as the parent's rolled-up total.
- **Recursive budget matching**:
  - Budget with `category_ids = ['food']` matches a transaction in
    `food › restaurants › japanese`. Existing 2-level matcher tests
    continue to pass.
- **Color inheritance**:
  - Level-3 without color → resolver returns level-2's color; if level-2
    also has no color, returns level-1's color.
- **Parent delete cascade**:
  - Delete a level-1 parent → level-2 children become level-1 (parent_id
    null); level-3 grandchildren become level-2.

---

## 9. File touch list

| Path | Change |
|---|---|
| `lib/db/schema.ts` | Update comment on `categories.parent_id` from "2-level" to "≤ 3-level"; keep MIGRATIONS empty (no schema change). |
| `lib/db/mutations.ts` | Replace `assertCanBeParent` with depth check + `subtreeDepth` for move case. |
| `lib/select.ts` | Recursive `rollupCategorySpend`; `expandDescendants` helper; `budgetProgress` signature gains `categories`. |
| `lib/data.ts` or `lib/select.ts` | New `categoryPath(c, byId)` helper. |
| `lib/db/queries/categories.ts` | If color resolver lives here, walk to root. |
| `lib/db/mutations.test.ts` | New tests (see §8). |
| `components/transaction-detail.tsx` | Recategorize Select uses `categoryPath`. |
| `components/add-expense-form.tsx` | Category Select uses `categoryPath`. |
| `components/edit-transaction-form.tsx` | Category Select uses `categoryPath`. |
| `components/budget-form-dialog.tsx` | Category filter Select uses `categoryPath`. |
| `components/rule-builder-sheet.tsx` | Category Select uses `categoryPath`. |
| Split editor (in `transaction-detail.tsx` or its own file) | Category Select uses `categoryPath`. |
| `app/(main)/categories/page.tsx` | Sub-subcategory rendering + "New sub-subcategory" + parent-Select depth-3 disable. |
| `plans/MASTER_PLAN.md` | Strike "3-level categories" once shipped. |
| `plans/ios-macos/IOS_MACOS_PLAN.md` §3 row 29 | Update "2-level" to "≤ 3-level". |

---

## 10. Out of scope

- ❌ **Arbitrary nesting depth** — hard cap at 3 by decision (§0.1).
- ❌ **Tree-style picker** (two-step / indented expand) — flat-with-
  separators by decision (§0.3).
- ❌ **SQL trigger / CHECK constraint enforcing depth ≤ 3** — see §12.
- ❌ **Insights / Reports drill-down UI** — current flat list of
  categories continues to work (with longer label strings); a real
  drill-down view is a separate plan if needed.
- ❌ **Auto-categorisation suggestions for 3-level** — the existing
  per-merchant suggestion (`suggestCategory`) returns whatever category
  the user has historically picked, so it works at depth 3 unchanged.
- ❌ **Bulk move / merge between subtrees** — single-node edits only.
- ❌ **Per-user "preferred default depth"** — pick the level you want
  per transaction.
- ❌ **Renaming the separator** (` › `). Hardcoded.

---

## 11. Open questions

1. **Color inheritance walking**: today the resolver is implicit (color
   stored or null). Should we make the inheritance behaviour explicit
   in a helper, or keep the existing "render falls back to parent"
   pattern? Recommendation: explicit helper for predictability.
2. **Empty parent in Edit dialog**: if a user changes a category from
   level-3 to top-level (clears `parent_id`), the level-3 child of THIS
   node has to come along. Today that's a no-op (depth becomes 2 — fine).
   Confirm this in tests.
3. **Sort order within a level**: do we sort by `sort_order` first then
   by name, or by full path? Recommendation: sort by `sort_order` per
   level (matches today's per-row column), with name as the tiebreaker.

---

## 12. Future: optional SQL trigger for depth invariant

The mutation guard above is the live enforcement. The SQL itself does
not constrain depth — a raw `INSERT` bypassing the mutation layer (e.g.
a hand-edited DB, a future import path that doesn't go through
`applyMutation`) could create deeper trees.

If we ever want SQL-level safety, a `BEFORE INSERT` trigger can express
the rule. Cycle-safe variant:

```sql
CREATE TRIGGER tr_categories_depth_insert
BEFORE INSERT ON categories
FOR EACH ROW
WHEN NEW.parent_id IS NOT NULL AND (
  SELECT COUNT(*) FROM (
    WITH RECURSIVE ancestry(id, parent_id) AS (
      SELECT id, parent_id FROM categories WHERE id = NEW.parent_id
      UNION ALL
      SELECT c.id, c.parent_id FROM categories c
        JOIN ancestry a ON c.id = a.parent_id
    )
    SELECT 1 FROM ancestry
  ) >= 3
)
BEGIN
  SELECT RAISE(ABORT, 'Categories nest at most three levels deep');
END;
```

And a matching `BEFORE UPDATE OF parent_id` trigger. Trade-off: adds two
triggers and a recursive CTE on every category insert/update — small
cost, large defence-in-depth payoff. **Not in v1**; revisit if a real
bypass case surfaces (likely never, given the only writer is
`applyMutation`).

---

## 13. Cross-references to `IOS_MACOS_PLAN.md` and `MASTER_PLAN.md`

- `IOS_MACOS_PLAN.md §3` capability matrix **row 29** (Categories admin):
  the "2-level" annotation updates to "≤ 3-level" once this ships. The
  schema convention is unchanged (parent_id stays just an FK), so the
  iOS port inherits the same mutation guard discipline.
- `MASTER_PLAN.md` Plans index: this plan listed under "Active planning"
  while in flight, then moves to `plans/done/` with a "shipped" preamble
  in the housekeeping commit.
- The category tree comment in the existing screen-status table for
  `MASTER_PLAN.md §1` updates from "2-level" to "≤ 3-level" once
  shipped.
