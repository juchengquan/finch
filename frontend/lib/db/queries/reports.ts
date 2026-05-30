// DB-backed reporting interactions: monthly cash flow and budget progress.

import type { Exec } from '@/lib/db/repo';
import { periodOf, periodRange, periodLabel, type Frequency } from '@/lib/budgets/period';

export interface CashFlow {
  income: number; // positive
  expense: number; // negative
  net: number;
}

/** Confirmed, non-transfer cash flow for a month (e.g. '2026-05'). */
export async function monthlyCashFlow(exec: Exec, ledgerId: string, yearMonth: string): Promise<CashFlow> {
  const rows = await exec(
    `SELECT
       SUM(CASE WHEN amount > 0 THEN amount_base ELSE 0 END) AS income,
       SUM(CASE WHEN amount < 0 THEN amount_base ELSE 0 END) AS expense,
       SUM(amount_base) AS net
     FROM transactions
     WHERE ledger_id = ? AND date LIKE ? AND transfer_group_id IS NULL AND is_adjustment = 0 AND status = 'confirmed'`,
    [ledgerId, `${yearMonth}%`],
  );
  const r = rows[0] ?? {};
  return { income: Number(r.income ?? 0), expense: Number(r.expense ?? 0), net: Number(r.net ?? 0) };
}

export interface BudgetProgress {
  id: string;
  name: string | null;
  budget: number;
  spent: number; // positive magnitude
  remaining: number;
  pct: number;
  over: boolean;
  frequency: Frequency;
  /** Period id the spend window represents (e.g. '2026-04', '2026-Q2'). */
  period: string;
  /** Human-readable label for the period — UI header copy. */
  periodLabel: string;
  /** Inclusive YYYY-MM-DD bounds of the period. */
  periodFrom: string;
  periodTo: string;
}

/**
 * Per-budget spend over the current period. Each budget's period is derived
 * from its own `frequency` + `start_date`, so a weekly budget reports its
 * current week and a quarterly budget reports its current quarter — no more
 * implicit "monthly" assumption.
 *
 * `today` is the reference date (YYYY-MM-DD) used to pick the current period.
 */
export async function budgetProgress(exec: Exec, ledgerId: string, today: string): Promise<BudgetProgress[]> {
  const budgets = await exec(
    'SELECT id, name, amount, carry_forward, frequency, start_date, category_ids, warning_pct FROM budgets WHERE ledger_id = ?',
    [ledgerId],
  );
  const result: BudgetProgress[] = [];
  for (const b of budgets) {
    const frequency = String(b.frequency) as Frequency;
    const startDate = String(b.start_date);
    const period = periodOf(today, frequency, startDate);
    const { from, to } = periodRange(period, frequency);

    const total = Number(b.amount) + Number(b.carry_forward ?? 0);
    const catIds = b.category_ids ? (JSON.parse(String(b.category_ids)) as string[]) : [];
    let spent = 0;
    if (catIds.length) {
      const placeholders = catIds.map(() => '?').join(',');
      const rows = await exec(
        `SELECT COALESCE(SUM(COALESCE(ts.amount_base, t.amount_base) * -1), 0) AS spent
           FROM transactions t
           LEFT JOIN transaction_splits ts ON ts.transaction_id = t.id
          WHERE t.ledger_id = ? AND t.date BETWEEN ? AND ? AND t.amount < 0
            AND t.transfer_group_id IS NULL AND t.is_adjustment = 0 AND t.status = 'confirmed'
            AND COALESCE(ts.category_id, t.category_id) IN (${placeholders})`,
        [ledgerId, from, to, ...catIds],
      );
      spent = Number(rows[0]?.spent ?? 0);
    }
    const pct = total > 0 ? Math.round((spent / total) * 1000) / 10 : 0;
    result.push({
      id: String(b.id),
      name: b.name == null ? null : String(b.name),
      budget: total,
      spent,
      remaining: Math.round((total - spent) * 100) / 100,
      pct,
      over: total > 0 && spent / total >= Number(b.warning_pct ?? 80) / 100,
      frequency,
      period,
      periodLabel: periodLabel(period, frequency),
      periodFrom: from,
      periodTo: to,
    });
  }
  return result;
}
