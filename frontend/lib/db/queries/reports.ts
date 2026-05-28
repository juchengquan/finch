// DB-backed reporting interactions: monthly cash flow and budget progress.

import type { Exec } from '@/lib/db/repo';

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
}

/**
 * Per-budget spend for the budget's period (monthly budgets), honouring the
 * category_ids filter. Accounts/tags filters arrive with their phases.
 */
export async function budgetProgress(exec: Exec, ledgerId: string, yearMonth: string): Promise<BudgetProgress[]> {
  const budgets = await exec(
    "SELECT id, name, amount, carry_forward, category_ids, warning_pct FROM budgets WHERE ledger_id = ? AND frequency = 'monthly'",
    [ledgerId],
  );
  const result: BudgetProgress[] = [];
  for (const b of budgets) {
    const total = Number(b.amount) + Number(b.carry_forward ?? 0);
    const catIds = b.category_ids ? (JSON.parse(String(b.category_ids)) as string[]) : [];
    let spent = 0;
    if (catIds.length) {
      const placeholders = catIds.map(() => '?').join(',');
      const rows = await exec(
        `SELECT COALESCE(SUM(amount_base * -1), 0) AS spent
           FROM transactions
          WHERE ledger_id = ? AND date LIKE ? AND amount < 0
            AND transfer_group_id IS NULL AND is_adjustment = 0 AND status = 'confirmed'
            AND category_id IN (${placeholders})`,
        [ledgerId, `${yearMonth}%`, ...catIds],
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
    });
  }
  return result;
}
