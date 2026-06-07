// DB-backed category interactions: listing and per-category spend.

import type { Exec } from '@/lib/db/repo';

export interface CategoryRow {
  id: string;
  ledgerId: string;
  /** NULL = top-level category. Non-NULL = child whose parent is a top-level row. */
  parentId: string | null;
  name: string;
  /** `expense` / `income` / `transfer`. (DB column is `kind` for historical reasons.) */
  type: string;
  icon: string | null;
  /** Hex `#rrggbb`. Use lib/colors `categoryHex(hue)` to generate from a palette hue. */
  color: string | null;
}

/** List categories; pass a ledgerId to scope, or omit for all ledgers.
 *  Equity system rows (kind='equity') are excluded — they are hidden from
 *  pickers and excluded from spend aggregations (DOUBLE_ENTRY_PLAN §2.3). */
export async function listCategories(exec: Exec, ledgerId?: string): Promise<CategoryRow[]> {
  const rows = await exec(
    ledgerId
      ? "SELECT * FROM categories WHERE ledger_id = ? AND kind != 'equity' ORDER BY sort_order"
      : "SELECT * FROM categories WHERE kind != 'equity' ORDER BY ledger_id, sort_order",
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    parentId: r.parent_id == null ? null : String(r.parent_id),
    name: String(r.name),
    type: String(r.kind),
    icon: r.icon == null ? null : String(r.icon),
    color: r.color == null ? null : String(r.color),
  }));
}

export interface CategoryTreeNode {
  parent: CategoryRow;
  children: CategoryRow[];
}

/** Group categories into a 2-level tree. Top-level rows become parents (with
 *  an empty `children` array when childless); child rows whose parent is also
 *  in `cats` slot under that parent. Orphan children (their parent isn't in
 *  the input) are promoted to top-level so the result is always exhaustive. */
export function buildCategoryTree(cats: CategoryRow[]): CategoryTreeNode[] {
  const byId = new Map(cats.map((c) => [c.id, c]));
  const tops: CategoryRow[] = [];
  const childrenOf = new Map<string, CategoryRow[]>();
  for (const c of cats) {
    if (c.parentId && byId.has(c.parentId)) {
      const list = childrenOf.get(c.parentId) ?? [];
      list.push(c);
      childrenOf.set(c.parentId, list);
    } else {
      tops.push(c);
    }
  }
  return tops.map((p) => ({ parent: p, children: childrenOf.get(p.id) ?? [] }));
}

export interface CategoryPatch {
  name?: string;
  type?: string;
  icon?: string | null;
  color?: string | null;
  parentId?: string | null;
}

/** Update a category's editable fields. */
export async function updateCategory(exec: Exec, id: string, patch: CategoryPatch): Promise<void> {
  const cols: Record<keyof CategoryPatch, string> = {
    name: 'name',
    type: 'kind',
    icon: 'icon',
    color: 'color',
    parentId: 'parent_id',
  };
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof CategoryPatch)[]) {
    if (patch[key] === undefined) continue;
    sets.push(`${cols[key]} = ?`);
    bind.push(patch[key] ?? null);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE categories SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Hard delete a category. Children are promoted to top-level via `parent_id`'s
 *  ON DELETE SET NULL clause; transactions.category_id becomes NULL too. */
export async function deleteCategory(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM categories WHERE id = ?', [id]);
}

export interface CategorySpend {
  id: string;
  name: string;
  spent: number; // positive magnitude of expenses
}

/**
 * Confirmed expense total per category. LEFT-JOINs `transaction_splits` so a
 * tx with splits emits one row per split (its category + its amount), while a
 * tx without splits falls back to the parent's category + amount via COALESCE.
 *
 * The result is **leaf-keyed**: each row's id is the category it was filed
 * against. Parents with children appear here only with their own direct
 * transactions (parents are bookable). Use `rollupCategorySpend` to fold
 * children into their parents for rollup reports.
 */
export async function categorySpend(exec: Exec, ledgerId: string): Promise<Record<string, number>> {
  const rows = await exec(
    `SELECT COALESCE(ts.category_id, t.category_id) AS id,
            SUM(COALESCE(ts.amount_base, t.amount_base) * -1) AS spent
       FROM transactions t
       LEFT JOIN transaction_splits ts ON ts.transaction_id = t.id
      WHERE t.ledger_id = ? AND t.kind IN ('expense','refund')
        AND t.status = 'confirmed' AND COALESCE(ts.category_id, t.category_id) IS NOT NULL
      GROUP BY COALESCE(ts.category_id, t.category_id)`,
    [ledgerId],
  );
  const m: Record<string, number> = {};
  for (const r of rows) m[String(r.id)] = Number(r.spent);
  return m;
}

/**
 * Fold descendant spend into ancestor buckets so each category's value =
 * its own transactions + Σ(descendants' transactions, recursively). Works
 * at any depth (CATEGORIES_LEVEL3_PLAN §4.1) — at 2 levels behaves the same
 * as before; at 3 levels, grandchildren bubble up to grandparents.
 * Children keep their own entries too; callers pick whichever level they
 * want for display.
 */
export function rollupCategorySpend(
  leafTotals: Record<string, number>,
  categories: { id: string; parentId: string | null }[],
): Record<string, number> {
  const childrenOf = new Map<string, string[]>();
  for (const c of categories) {
    if (c.parentId == null) continue;
    const list = childrenOf.get(c.parentId);
    if (list) list.push(c.id);
    else childrenOf.set(c.parentId, [c.id]);
  }
  const memo = new Map<string, number>();
  const totalOf = (id: string): number => {
    const hit = memo.get(id);
    if (hit !== undefined) return hit;
    let t = leafTotals[id] ?? 0;
    for (const child of childrenOf.get(id) ?? []) t += totalOf(child);
    memo.set(id, t);
    return t;
  };
  const out: Record<string, number> = {};
  for (const c of categories) out[c.id] = totalOf(c.id);
  return out;
}

/** Expand a set of category ids to include every descendant (recursive).
 *  Used by `budgetProgress` so a budget on `food` also catches transactions
 *  in `food › restaurants › japanese`. Idempotent: passing already-expanded
 *  ids is a no-op. */
export function expandDescendants(
  ids: Iterable<string>,
  categories: { id: string; parentId: string | null }[],
): Set<string> {
  const out = new Set<string>(ids);
  const childrenOf = new Map<string, string[]>();
  for (const c of categories) {
    if (c.parentId == null) continue;
    const list = childrenOf.get(c.parentId);
    if (list) list.push(c.id);
    else childrenOf.set(c.parentId, [c.id]);
  }
  const stack = [...out];
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

/** Display path for a category: `Food › Restaurants › Japanese`. Walks the
 *  parent chain to the root, joining names with the standard ` › `
 *  separator. Returns just the name when the category is top-level. */
export function categoryPath(
  c: { id: string; name: string; parentId: string | null },
  byId: Map<string, { id: string; name: string; parentId: string | null }>,
): string {
  const parts = [c.name];
  let cur = c.parentId;
  for (let hop = 0; cur != null && hop < 10; hop++) {
    const p = byId.get(cur);
    if (!p) break;
    parts.unshift(p.name);
    cur = p.parentId;
  }
  return parts.join(' › ');
}

/** Resolve a category's effective color, falling back to the nearest
 *  ancestor with a non-null `color` (CATEGORIES_LEVEL3_PLAN §6 color
 *  inheritance). Returns null when the entire chain to the root has no
 *  color — the caller picks a DEFAULT in that case. */
export function resolveCategoryColor(
  c: { id: string; parentId: string | null; color: string | null },
  byId: Map<string, { id: string; parentId: string | null; color: string | null }>,
): string | null {
  if (c.color) return c.color;
  let cur = c.parentId;
  for (let hop = 0; cur != null && hop < 10; hop++) {
    const p = byId.get(cur);
    if (!p) break;
    if (p.color) return p.color;
    cur = p.parentId;
  }
  return null;
}

/** Confirmed expense totals per category for a month (e.g. '2026-05'). */
export async function monthlyByCategory(exec: Exec, ledgerId: string, yearMonth: string): Promise<CategorySpend[]> {
  const rows = await exec(
    `SELECT c.id, c.name, SUM(COALESCE(ts.amount_base, t.amount_base) * -1) AS spent
       FROM transactions t
       LEFT JOIN transaction_splits ts ON ts.transaction_id = t.id
       JOIN categories c ON c.id = COALESCE(ts.category_id, t.category_id)
      WHERE t.ledger_id = ? AND t.date LIKE ?
        AND t.kind IN ('expense','refund') AND t.status = 'confirmed'
      GROUP BY c.id ORDER BY spent DESC`,
    [ledgerId, `${yearMonth}%`],
  );
  return rows.map((r) => ({ id: String(r.id), name: String(r.name), spent: Number(r.spent) }));
}
