// DB-backed category interactions: listing and per-category spend.

import type { Exec } from '@/lib/db/repo';

export interface CategoryRow {
  id: string;
  ledgerId: string;
  name: string;
  type: string;
  icon: string | null;
  /** Hex `#rrggbb`. Use lib/colors `categoryHex(hue)` to generate from a palette hue. */
  color: string | null;
}

/** List categories; pass a ledgerId to scope, or omit for all ledgers. */
export async function listCategories(exec: Exec, ledgerId?: string): Promise<CategoryRow[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM categories WHERE ledger_id = ? ORDER BY sort_order'
      : 'SELECT * FROM categories ORDER BY ledger_id, sort_order',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    name: String(r.name),
    type: String(r.kind),
    icon: r.icon == null ? null : String(r.icon),
    color: r.color == null ? null : String(r.color),
  }));
}

export interface CategoryPatch {
  name?: string;
  type?: string;
  icon?: string | null;
  color?: string | null;
}

/** Update a category's editable fields. */
export async function updateCategory(exec: Exec, id: string, patch: CategoryPatch): Promise<void> {
  const cols: Record<keyof CategoryPatch, string> = { name: 'name', type: 'kind', icon: 'icon', color: 'color' };
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

/** Hard delete a category; transactions.category_id becomes NULL (uncategorized). */
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
