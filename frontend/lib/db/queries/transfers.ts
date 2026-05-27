// Transfers derived from the transactions table: each transfer_group_id has an
// outgoing row (amount < 0) and an incoming row (amount > 0). We reconstruct the
// from/to accounts and amount by grouping on transfer_group_id.

import type { Exec } from '@/lib/db/repo';

export interface Transfer {
  id: string; // transfer_group_id
  date: string;
  amount: number; // positive magnitude
  fromAccountId: string | null;
  toAccountId: string | null;
  fromName: string | null;
  toName: string | null;
  note: string | null;
}

export async function listTransfers(exec: Exec, ledgerId: string): Promise<Transfer[]> {
  const rows = await exec(
    `SELECT
       t.transfer_group_id AS id,
       MAX(t.date) AS date,
       MAX(CASE WHEN t.amount < 0 THEN -t.amount END) AS amount,
       MAX(CASE WHEN t.amount < 0 THEN t.account_id END) AS fromId,
       MAX(CASE WHEN t.amount > 0 THEN t.account_id END) AS toId,
       MAX(t.notes) AS note
     FROM transactions t
     WHERE t.ledger_id = ? AND t.transfer_group_id IS NOT NULL AND t.status != 'cancelled'
     GROUP BY t.transfer_group_id
     ORDER BY date DESC`,
    [ledgerId],
  );
  if (rows.length === 0) return [];

  const accts = await exec('SELECT id, name FROM accounts WHERE ledger_id = ?', [ledgerId]);
  const nameById = new Map(accts.map((a) => [String(a.id), String(a.name)]));
  return rows.map((r) => ({
    id: String(r.id),
    date: String(r.date),
    amount: Number(r.amount ?? 0),
    fromAccountId: r.fromId == null ? null : String(r.fromId),
    toAccountId: r.toId == null ? null : String(r.toId),
    fromName: r.fromId == null ? null : nameById.get(String(r.fromId)) ?? null,
    toName: r.toId == null ? null : nameById.get(String(r.toId)) ?? null,
    note: r.note == null ? null : String(r.note),
  }));
}
