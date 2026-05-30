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

/**
 * Set the per-category budget amount.
 *
 * - **No existing row** → create with `amount` active immediately, default
 *   monthly cycle, anchor 2026-05-01.
 * - **Existing row** → stage as `pending_amount`; the current period's
 *   spend calculation keeps using the old `amount`. The rollover loop
 *   commits the staged value to `amount` at the next period boundary.
 *
 * Use `updateBudgetCycle` when the user changes the frequency / start
 * date — that path applies the amount immediately under the new cycle.
 */
export async function setCategoryBudget(exec: Exec, categoryId: string, amount: number): Promise<void> {
  const id = `bud-${categoryId}`;
  const existing = await exec('SELECT 1 AS x FROM budgets WHERE id = ?', [id]);
  if (existing.length) {
    await exec(
      "UPDATE budgets SET pending_amount = ?, updated_at = datetime('now') WHERE id = ?",
      [amount, id],
    );
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

/**
 * Change a budget's cycle (and optionally its amount in the same step).
 * Cycle changes are immediate per BUDGET_CYCLES_PLAN §4a:
 *   - `amount` becomes the new active limit (carried over from the prior
 *     row if not supplied).
 *   - `frequency` + `start_date` are written.
 *   - `pending_amount` is discarded.
 *   - `last_rolled_period` resets to NULL — period IDs from the old cycle
 *     don't translate, so the next request's rollBudgetsIfDue starts the
 *     new cycle's clock fresh.
 *   - `carry_forward` and `rollover_limit` are preserved (absolute amounts).
 */
export async function updateBudgetCycle(
  exec: Exec,
  categoryId: string,
  patch: { frequency: Frequency; startDate: string; amount?: number },
): Promise<void> {
  const id = `bud-${categoryId}`;
  const existing = await exec('SELECT amount FROM budgets WHERE id = ?', [id]);
  if (!existing.length) throw new Error('Set a budget for this category first');
  const amount = patch.amount ?? Number(existing[0].amount);
  await exec(
    `UPDATE budgets
       SET amount = ?, frequency = ?, start_date = ?,
           pending_amount = NULL, last_rolled_period = NULL,
           updated_at = datetime('now')
     WHERE id = ?`,
    [amount, patch.frequency, patch.startDate, id],
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
