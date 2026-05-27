// Budgets live in the `budgets` table (a budget targets one or more categories
// via category_ids). The app's UI models a per-category monthly limit, so we
// project a categoryId → amount map and upsert a per-category budget row keyed
// `bud-<categoryId>` — replacing the old budgetOverrides app_state shim.

import type { Exec } from '@/lib/db/repo';

/** Map of categoryId → monthly budget amount. */
export async function budgetByCategory(exec: Exec): Promise<Record<string, number>> {
  const rows = await exec("SELECT amount, category_ids FROM budgets WHERE frequency = 'monthly'");
  const map: Record<string, number> = {};
  for (const r of rows) {
    const ids = r.category_ids ? (JSON.parse(String(r.category_ids)) as string[]) : [];
    for (const id of ids) map[id] = Number(r.amount);
  }
  return map;
}

/** Upsert the monthly budget for a single category. */
export async function setCategoryBudget(exec: Exec, categoryId: string, amount: number): Promise<void> {
  const id = `bud-${categoryId}`;
  const existing = await exec('SELECT 1 AS x FROM budgets WHERE id = ?', [id]);
  if (existing.length) {
    await exec("UPDATE budgets SET amount = ?, updated_at = datetime('now') WHERE id = ?", [amount, id]);
    return;
  }
  const cat = await exec('SELECT ledger_id, name FROM categories WHERE id = ?', [categoryId]);
  if (!cat.length) throw new Error('Category not found');
  await exec(
    `INSERT INTO budgets
       (id,ledger_id,name,type,amount,carry_forward,frequency,start_date,is_recurring,rollover,category_ids,warning_pct,created_at,updated_at)
     VALUES (?,?,?,'expense',?,0,'monthly','2026-05-01',1,0,?,80,datetime('now'),datetime('now'))`,
    [id, String(cat[0].ledger_id), String(cat[0].name), amount, JSON.stringify([categoryId])],
  );
}

/** Remove a category's monthly budget row. */
export async function deleteCategoryBudget(exec: Exec, categoryId: string): Promise<void> {
  await exec('DELETE FROM budgets WHERE id = ?', [`bud-${categoryId}`]);
}
