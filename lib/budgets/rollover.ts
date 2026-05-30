// Automatic period rollover for budgets. Catches up missed period boundaries
// (rollover=on: leftover → carry_forward; either way: pending_amount → amount)
// and invalidates the rollover cache when a backdated transaction edit could
// have affected an already-rolled period.
//
// See plans/BUDGET_CYCLES_PLAN.md §5 / §6 for the design.

import type { Exec } from '@/lib/db/repo';
import {
  periodOf,
  prevPeriod,
  nextPeriod,
  periodRange,
  type Frequency,
} from './period';

const r2 = (n: number) => Math.round(n * 100) / 100;

interface BudgetRow {
  id: string;
  ledger_id: string;
  amount: number;
  carry_forward: number;
  frequency: Frequency;
  start_date: string;
  rollover: number;
  rollover_limit: number | null;
  pending_amount: number | null;
  last_rolled_period: string | null;
  category_ids: string[];
  end_date: string | null;
}

async function loadBudgets(exec: Exec): Promise<BudgetRow[]> {
  const rows = await exec(
    `SELECT id, ledger_id, amount, carry_forward, frequency, start_date, end_date,
            rollover, rollover_limit, pending_amount, last_rolled_period, category_ids
       FROM budgets`,
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledger_id: String(r.ledger_id),
    amount: Number(r.amount),
    carry_forward: Number(r.carry_forward ?? 0),
    frequency: String(r.frequency) as Frequency,
    start_date: String(r.start_date),
    end_date: r.end_date == null ? null : String(r.end_date),
    rollover: Number(r.rollover ?? 0),
    rollover_limit: r.rollover_limit == null ? null : Number(r.rollover_limit),
    pending_amount: r.pending_amount == null ? null : Number(r.pending_amount),
    last_rolled_period: r.last_rolled_period == null ? null : String(r.last_rolled_period),
    category_ids: r.category_ids ? (JSON.parse(String(r.category_ids)) as string[]) : [],
  }));
}

async function spentInRange(
  exec: Exec,
  ledgerId: string,
  categoryIds: string[],
  from: string,
  to: string,
): Promise<number> {
  if (!categoryIds.length) return 0;
  const placeholders = categoryIds.map(() => '?').join(',');
  const rows = await exec(
    `SELECT COALESCE(SUM(COALESCE(ts.amount_base, t.amount_base) * -1), 0) AS spent
       FROM transactions t
       LEFT JOIN transaction_splits ts ON ts.transaction_id = t.id
      WHERE t.ledger_id = ? AND t.date BETWEEN ? AND ? AND t.amount < 0
        AND t.transfer_group_id IS NULL AND t.is_adjustment = 0 AND t.status = 'confirmed'
        AND COALESCE(ts.category_id, t.category_id) IN (${placeholders})`,
    [ledgerId, from, to, ...categoryIds],
  );
  return Number(rows[0]?.spent ?? 0);
}

/**
 * Catch up rollover state for every budget that has missed period boundaries.
 * For each missing period:
 *   - if rollover=on: spent over the period → leftover → capped → new
 *     carry_forward
 *   - either way: any pending_amount activates as the new active amount
 *   - last_rolled_period advances by one
 *
 * Idempotent: a no-op when no budget has missed a boundary. Safe to call on
 * every request.
 *
 * `today` is the reference date (YYYY-MM-DD) used to pick the current period.
 * Returns the number of period transitions applied across all budgets.
 */
export async function rollBudgetsIfDue(exec: Exec, today: string): Promise<{ rolled: number }> {
  const budgets = await loadBudgets(exec);
  let rolled = 0;
  for (const b of budgets) {
    if (b.start_date > today) continue; // dormant
    if (b.end_date && b.end_date < today) continue; // past end
    const currentPeriod = periodOf(today, b.frequency, b.start_date);
    const target = prevPeriod(currentPeriod, b.frequency, b.start_date);

    let lastRolled = b.last_rolled_period;
    let amount = b.amount;
    let carryForward = b.carry_forward;
    let pendingAmount = b.pending_amount;

    // Walk forward one period at a time until we've rolled everything that
    // closed before today's period began. `target` is the most-recent
    // already-closed period — anything past it is "in progress" / future.
    while (lastRolled == null || lastRolled < target) {
      const rollFrom = lastRolled == null
        ? periodOf(b.start_date, b.frequency, b.start_date)
        : nextPeriod(lastRolled, b.frequency, b.start_date);
      if (rollFrom > target) break;

      if (b.rollover === 1) {
        const { from, to } = periodRange(rollFrom, b.frequency);
        const spent = await spentInRange(exec, b.ledger_id, b.category_ids, from, to);
        const effective = amount + carryForward;
        const leftover = Math.max(0, effective - spent);
        carryForward = b.rollover_limit == null
          ? r2(leftover)
          : r2(Math.min(leftover, b.rollover_limit));
      }
      lastRolled = rollFrom;

      // pending_amount activates as the NEW period (after rollFrom) begins.
      // Run this after computing rollover so the closed period used the
      // in-effect amount.
      if (pendingAmount != null) {
        amount = pendingAmount;
        pendingAmount = null;
      }
      rolled++;
    }

    // Only write when something actually advanced — keeps idempotent calls
    // cheap (no UPDATE noise on quiet ticks).
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
 * categories live under a budget whose `last_rolled_period` covers the
 * affected date. If so, reset rollover state for that budget so the next
 * `rollBudgetsIfDue` replays from the start_date forward.
 *
 * `earliestDate` is the earliest YYYY-MM-DD across all affected transactions
 * (old + new). `categoryIds` is the union of every category mentioned by
 * those transactions (parent + splits, old + new).
 */
export async function invalidateRollover(
  exec: Exec,
  categoryIds: string[],
  earliestDate: string,
): Promise<{ invalidated: number }> {
  if (!categoryIds.length || !earliestDate) return { invalidated: 0 };
  const budgets = await loadBudgets(exec);
  let invalidated = 0;
  for (const b of budgets) {
    if (b.last_rolled_period == null) continue;
    if (!categoryIds.some((c) => b.category_ids.includes(c))) continue;
    const affectedPeriod = periodOf(earliestDate, b.frequency, b.start_date);
    if (affectedPeriod > b.last_rolled_period) continue;
    await exec(
      `UPDATE budgets SET last_rolled_period = NULL, carry_forward = 0,
                          updated_at = datetime('now')
       WHERE id = ?`,
      [b.id],
    );
    invalidated++;
  }
  return { invalidated };
}
