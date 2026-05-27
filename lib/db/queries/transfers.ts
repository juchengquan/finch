// Transfers derived from the transactions table: each transfer_group_id has an
// outgoing row (amount < 0) and an incoming row (amount > 0). We reconstruct the
// from/to accounts and amount by grouping on transfer_group_id.

import type { Exec } from '@/lib/db/repo';
import { recomputeAccount } from './accounts';

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

export interface TransferPatch {
  amount?: number; // new magnitude, in the from-account's currency
  date?: string;
  note?: string | null;
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Edit a transfer in place: rewrite both legs (a new amount scales both legs
 * proportionally, preserving any FX ratio), then recompute both accounts.
 */
export async function updateTransfer(exec: Exec, groupId: string, patch: TransferPatch): Promise<void> {
  const legs = await exec(
    'SELECT id, account_id, amount, amount_base FROM transactions WHERE transfer_group_id = ?',
    [groupId],
  );
  if (!legs.length) return;

  if (patch.amount !== undefined) {
    const newAmount = Math.abs(patch.amount);
    if (!(newAmount > 0)) throw new Error('Transfer amount must be greater than 0');
    const fromLeg = legs.find((l) => Number(l.amount) < 0) ?? legs[0];
    const oldFrom = Math.abs(Number(fromLeg.amount));
    const factor = oldFrom > 0 ? newAmount / oldFrom : 1;
    for (const l of legs) {
      await exec('UPDATE transactions SET amount = ?, amount_base = ? WHERE id = ?', [
        r2(Number(l.amount) * factor),
        r2(Number(l.amount_base) * factor),
        String(l.id),
      ]);
    }
    await exec('UPDATE transfer_groups SET amount_base = ? WHERE id = ?', [newAmount, groupId]);
  }
  if (patch.date !== undefined) {
    await exec('UPDATE transactions SET date = ? WHERE transfer_group_id = ?', [patch.date, groupId]);
  }
  if (patch.note !== undefined) {
    await exec('UPDATE transactions SET notes = ? WHERE transfer_group_id = ?', [patch.note ?? null, groupId]);
    await exec('UPDATE transfer_groups SET notes = ? WHERE id = ?', [patch.note ?? null, groupId]);
  }

  for (const r of new Set(legs.map((l) => String(l.account_id)))) {
    await recomputeAccount(exec, r);
  }
}

/**
 * Delete a transfer: remove both leg transactions and the group row, then
 * recompute the balances of the affected accounts (the balance trigger only
 * fires on INSERT, so removing rows needs an explicit recompute).
 */
export async function deleteTransfer(exec: Exec, groupId: string): Promise<void> {
  const legs = await exec('SELECT DISTINCT account_id FROM transactions WHERE transfer_group_id = ?', [groupId]);
  await exec('DELETE FROM transactions WHERE transfer_group_id = ?', [groupId]);
  await exec('DELETE FROM transfer_groups WHERE id = ?', [groupId]);
  for (const r of legs) await recomputeAccount(exec, String(r.account_id));
}
