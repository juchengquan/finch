// DB-backed category interactions: listing and per-category spend.

import type { Exec } from '@/lib/db/repo';

export interface CategoryRow {
  id: string;
  name: string;
  parentName: string | null;
  type: string;
  icon: string | null;
}

export async function listCategories(exec: Exec, ledgerId: string): Promise<CategoryRow[]> {
  const rows = await exec('SELECT * FROM categories WHERE ledger_id = ? ORDER BY sort_order', [ledgerId]);
  return rows.map((r) => ({
    id: String(r.id),
    name: String(r.name),
    parentName: r.parent_name == null ? null : String(r.parent_name),
    type: String(r.type),
    icon: r.icon == null ? null : String(r.icon),
  }));
}

export interface CategorySpend {
  id: string;
  name: string;
  spent: number; // positive magnitude of expenses
}

/** Confirmed expense totals per category for a month (e.g. '2026-05'). */
export async function monthlyByCategory(exec: Exec, ledgerId: string, yearMonth: string): Promise<CategorySpend[]> {
  const rows = await exec(
    `SELECT c.id, c.name, SUM(t.amount_base * -1) AS spent
       FROM transactions t JOIN categories c ON t.category_id = c.id
      WHERE t.ledger_id = ? AND t.date LIKE ?
        AND t.amount < 0 AND t.transfer_group_id IS NULL AND t.status = 'confirmed'
      GROUP BY c.id ORDER BY spent DESC`,
    [ledgerId, `${yearMonth}%`],
  );
  return rows.map((r) => ({ id: String(r.id), name: String(r.name), spent: Number(r.spent) }));
}
