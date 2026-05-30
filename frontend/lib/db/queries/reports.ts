// DB-backed reporting interactions: monthly cash flow.

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
     WHERE ledger_id = ? AND date LIKE ? AND kind NOT IN ('transfer','adjustment') AND status = 'confirmed'`,
    [ledgerId, `${yearMonth}%`],
  );
  const r = rows[0] ?? {};
  return { income: Number(r.income ?? 0), expense: Number(r.expense ?? 0), net: Number(r.net ?? 0) };
}
