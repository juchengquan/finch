// Automatic period rollover for budgets. Catches up missed period boundaries
// (rollover=on: leftover → carry_forward; either way: pending_amount → amount)
// and invalidates the rollover cache when a backdated transaction edit could
// have affected an already-rolled period.
//
// See plans/BUDGET_CYCLES_PLAN.md for the design.

import type { Exec } from '@/lib/db/repo';
import { periodOf, prevPeriod, nextPeriod, periodRange, type Frequency } from './period';

const r2 = (n: number) => Math.round(n * 100) / 100;

interface BudgetRow {
  id: string;
  ledger_id: string;
  type: 'income' | 'expense';
  amount: number;
  carry_forward: number;
  frequency: Frequency;
  start_date: string;
  end_date: string | null;
  is_recurring: number;
  rollover: number;
  rollover_limit: number | null;
  pending_amount: number | null;
  last_rolled_period: string | null;
  account_ids: string[];
  category_ids: string[];
}

async function loadBudgets(exec: Exec): Promise<BudgetRow[]> {
  const rows = await exec(
    `SELECT id, ledger_id, kind, amount, carry_forward, frequency, start_date, end_date,
            is_recurring, rollover, rollover_limit, pending_amount, last_rolled_period,
            account_ids, category_ids
       FROM budgets`,
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledger_id: String(r.ledger_id),
    type: String(r.kind) as 'income' | 'expense',
    amount: Number(r.amount),
    carry_forward: Number(r.carry_forward ?? 0),
    frequency: String(r.frequency) as Frequency,
    start_date: String(r.start_date),
    end_date: r.end_date == null ? null : String(r.end_date),
    is_recurring: Number(r.is_recurring ?? 1),
    rollover: Number(r.rollover ?? 0),
    rollover_limit: r.rollover_limit == null ? null : Number(r.rollover_limit),
    pending_amount: r.pending_amount == null ? null : Number(r.pending_amount),
    last_rolled_period: r.last_rolled_period == null ? null : String(r.last_rolled_period),
    account_ids: r.account_ids ? (JSON.parse(String(r.account_ids)) as string[]) : [],
    category_ids: r.category_ids ? (JSON.parse(String(r.category_ids)) as string[]) : [],
  }));
}

async function spentInRange(
  exec: Exec,
  budget: BudgetRow,
  from: string,
  to: string,
): Promise<number> {
  const where: string[] = [
    't.ledger_id = ?',
    't.date BETWEEN ? AND ?',
    't.amount < 0',
    't.transfer_group_id IS NULL',
    "t.kind != 'adjustment'",
    "t.status = 'confirmed'",
  ];
  const bind: (string | number)[] = [budget.ledger_id, from, to];

  // category_ids = [] is treated as "matches every category".
  if (budget.category_ids.length) {
    const placeholders = budget.category_ids.map(() => '?').join(',');
    where.push(`COALESCE(ts.category_id, t.category_id) IN (${placeholders})`);
    bind.push(...budget.category_ids);
  }
  if (budget.account_ids.length) {
    const placeholders = budget.account_ids.map(() => '?').join(',');
    where.push(`t.account_id IN (${placeholders})`);
    bind.push(...budget.account_ids);
  }
  const rows = await exec(
    `SELECT COALESCE(SUM(COALESCE(ts.amount_base, t.amount_base) * -1), 0) AS spent
       FROM transactions t
       LEFT JOIN transaction_splits ts ON ts.transaction_id = t.id
      WHERE ${where.join(' AND ')}`,
    bind,
  );
  return Number(rows[0]?.spent ?? 0);
}

/**
 * Catch up rollover state for every recurring budget that has missed period
 * boundaries. Per missed period:
 *   - rollover=on AND type=expense: spent over the period → leftover → capped →
 *     new carry_forward
 *   - either way: any pending_amount → amount (commits the staged change at
 *     the boundary; matches the plan's §2)
 *   - last_rolled_period advances by one
 *
 * Idempotent: no-op when no budget has missed a boundary. Safe to call on every
 * request. Returns the count of period transitions applied across all budgets.
 *
 * `today` is the reference date (YYYY-MM-DD) used to pick the current period.
 */
export async function rollBudgetsIfDue(exec: Exec, today: string): Promise<{ rolled: number }> {
  const budgets = await loadBudgets(exec);
  let rolled = 0;
  for (const b of budgets) {
    if (b.is_recurring !== 1) continue; // one-shot budgets never roll
    if (b.start_date > today) continue;  // dormant
    if (b.end_date && b.end_date < today) continue; // past end

    const firstPeriod = periodOf(b.start_date, b.frequency, b.start_date);
    const currentPeriod = periodOf(today, b.frequency, b.start_date);
    // Still in the first period — nothing has closed yet.
    if (currentPeriod === firstPeriod) continue;
    const target = prevPeriod(currentPeriod, b.frequency, b.start_date);

    let lastRolled = b.last_rolled_period;
    let amount = b.amount;
    let carryForward = b.carry_forward;
    let pendingAmount = b.pending_amount;

    // Walk one period at a time until we've rolled everything that closed
    // before today's period began. `target` is the most-recent already-closed
    // period — anything past it is in-progress.
    while (lastRolled == null || lastRolled < target) {
      const rollFrom = lastRolled == null
        ? periodOf(b.start_date, b.frequency, b.start_date)
        : nextPeriod(lastRolled, b.frequency, b.start_date);
      if (rollFrom > target) break;

      if (b.rollover === 1 && b.type === 'expense') {
        const { from, to } = periodRange(rollFrom, b.frequency, b.start_date);
        const spent = await spentInRange(exec, b, from, to);
        const effective = amount + carryForward;
        const leftover = Math.max(0, effective - spent);
        carryForward = b.rollover_limit == null
          ? r2(leftover)
          : r2(Math.min(leftover, b.rollover_limit));
      }
      lastRolled = rollFrom;

      // pending_amount activates as the NEW period (after rollFrom) begins.
      // Run this after computing rollover so the just-closed period used the
      // in-effect amount.
      if (pendingAmount != null) {
        amount = pendingAmount;
        pendingAmount = null;
      }
      rolled++;
    }

    // Only UPDATE when something actually advanced — keeps idempotent calls
    // cheap (no SQL noise on quiet ticks).
    if (lastRolled !== b.last_rolled_period) {
      await exec(
        `UPDATE budgets
           SET amount = ?, carry_forward = ?, pending_amount = ?, last_rolled_period = ?,
               updated_at = datetime('now')
         WHERE id = ?`,
        [amount, carryForward, pendingAmount, lastRolled, b.id],
      );
    }
  }
  return { rolled };
}

/**
 * After a transaction edit / add / cancel, check whether any affected
 * categories/accounts live under a budget whose `last_rolled_period` covers
 * the affected date. If so, reset rollover state for that budget so the next
 * `rollBudgetsIfDue` replays from start_date forward.
 *
 * `affected` carries the union of every category + account touched by the
 * mutation (old + new). `earliestDate` is the earliest YYYY-MM-DD across
 * all involved transactions.
 *
 * A budget with empty `category_ids` (or `account_ids`) is treated as
 * "matches everything" — those filters mean "no restriction".
 */
export async function invalidateRollover(
  exec: Exec,
  affected: { categoryIds: string[]; accountIds: string[] },
  earliestDate: string,
): Promise<{ invalidated: number }> {
  if (!earliestDate) return { invalidated: 0 };
  const budgets = await loadBudgets(exec);
  let invalidated = 0;
  for (const b of budgets) {
    if (b.last_rolled_period == null) continue;

    const catOverlap = b.category_ids.length === 0
      || affected.categoryIds.some((c) => b.category_ids.includes(c));
    const acctOverlap = b.account_ids.length === 0
      || affected.accountIds.some((a) => b.account_ids.includes(a));
    if (!catOverlap || !acctOverlap) continue;

    const affectedPeriod = periodOf(earliestDate, b.frequency, b.start_date);
    if (affectedPeriod > b.last_rolled_period) continue;

    await exec(
      `UPDATE budgets
         SET last_rolled_period = NULL, carry_forward = 0,
             updated_at = datetime('now')
       WHERE id = ?`,
      [b.id],
    );
    invalidated++;
  }
  return { invalidated };
}
