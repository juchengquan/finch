// Budgets live in the `budgets` table (a budget targets one or more categories
// via category_ids). The app's UI models a per-category limit at one of six
// cycles (daily/weekly/biweekly/monthly/quarterly/yearly); we project a
// categoryId → amount map (currently-active limit) plus a richer
// per-category metadata projection for the cycle + pending-amount UI.

import type { Exec } from '@/lib/db/repo';
import type { Frequency } from '@/lib/budgets/period';

/** Map of categoryId → currently-active budget amount (regardless of cycle). */
export async function budgetByCategory(exec: Exec): Promise<Record<string, number>> {
  const rows = await exec('SELECT amount, category_ids FROM budgets');
  const map: Record<string, number> = {};
  for (const r of rows) {
    const ids = r.category_ids ? (JSON.parse(String(r.category_ids)) as string[]) : [];
    for (const id of ids) map[id] = Number(r.amount);
  }
  return map;
}

export interface BudgetMeta {
  /** Budget id (matches `bud-<categoryId>` for per-category budgets). */
  id: string;
  amount: number;
  frequency: Frequency;
  /** Cycle anchor — only meaningful for biweekly; ignored for other cycles. */
  startDate: string;
  /** Staged amount change activated at the next period boundary; NULL = none. */
  pendingAmount: number | null;
}

/** Map of categoryId → budget metadata (cycle + amount + pending). */
export async function budgetMetaByCategory(exec: Exec): Promise<Record<string, BudgetMeta>> {
  const rows = await exec(
    'SELECT id, amount, frequency, start_date, pending_amount, category_ids FROM budgets',
  );
  const map: Record<string, BudgetMeta> = {};
  for (const r of rows) {
    const ids = r.category_ids ? (JSON.parse(String(r.category_ids)) as string[]) : [];
    const meta: BudgetMeta = {
      id: String(r.id),
      amount: Number(r.amount),
      frequency: String(r.frequency) as Frequency,
      startDate: String(r.start_date),
      pendingAmount: r.pending_amount == null ? null : Number(r.pending_amount),
    };
    for (const id of ids) map[id] = meta;
  }
  return map;
}

export interface BudgetRolloverInfo {
  /** Whether unused budget should roll into the next period. */
  rollover: boolean;
  /** Optional cap on the rolled-forward balance. */
  rolloverLimit: number | null;
  /** Current carry-forward balance (added to `amount` in budgetProgress). */
  carryForward: number;
}

/** Map of categoryId → rollover config + current carry-forward amount. */
export async function budgetRolloverByCategory(exec: Exec): Promise<Record<string, BudgetRolloverInfo>> {
  const rows = await exec('SELECT rollover, rollover_limit, carry_forward, category_ids FROM budgets');
  const map: Record<string, BudgetRolloverInfo> = {};
  for (const r of rows) {
    const ids = r.category_ids ? (JSON.parse(String(r.category_ids)) as string[]) : [];
    const info: BudgetRolloverInfo = {
      rollover: Number(r.rollover) === 1,
      rolloverLimit: r.rollover_limit == null ? null : Number(r.rollover_limit),
      carryForward: Number(r.carry_forward ?? 0),
    };
    for (const id of ids) map[id] = info;
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

export interface BudgetRolloverPatch {
  rollover?: boolean;
  /** null clears the cap (uncapped roll-over). */
  rolloverLimit?: number | null;
  /** Manually set the current carry-forward balance (auto month-end carry-over is a separate task). */
  carryForward?: number;
}

/** Update rollover settings (and optionally the current carry-forward) for the
 * `bud-<categoryId>` row. Throws if no budget exists for the category yet. */
export async function setCategoryBudgetRollover(
  exec: Exec,
  categoryId: string,
  patch: BudgetRolloverPatch,
): Promise<void> {
  const id = `bud-${categoryId}`;
  const existing = await exec('SELECT 1 AS x FROM budgets WHERE id = ?', [id]);
  if (!existing.length) throw new Error('Set a budget for this category first');
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  if (patch.rollover !== undefined) {
    sets.push('rollover = ?');
    bind.push(patch.rollover ? 1 : 0);
  }
  if (patch.rolloverLimit !== undefined) {
    sets.push('rollover_limit = ?');
    bind.push(patch.rolloverLimit);
  }
  if (patch.carryForward !== undefined) {
    sets.push('carry_forward = ?');
    bind.push(patch.carryForward);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE budgets SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Remove a category's monthly budget row. */
export async function deleteCategoryBudget(exec: Exec, categoryId: string): Promise<void> {
  await exec('DELETE FROM budgets WHERE id = ?', [`bud-${categoryId}`]);
}
