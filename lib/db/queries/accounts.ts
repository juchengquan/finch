// DB-backed account interactions: listing with group + balance, the balance
// curve from snapshots, net worth, and editing account details.

import type { Exec } from '@/lib/db/repo';

export interface AccountRow {
  id: string;
  ledgerId: string;
  name: string;
  type: string;
  currency: string;
  balance: number;
  groupId: string | null;
  groupName: string | null;
  includeInNetWorth: number; // resolved (account override ?? group default ?? 1)
}

/** List accounts; pass a ledgerId to scope, or omit for all ledgers. */
export async function listAccounts(exec: Exec, ledgerId?: string): Promise<AccountRow[]> {
  const where = ledgerId ? 'WHERE a.ledger_id = ? AND a.is_active = 1' : 'WHERE a.is_active = 1';
  const rows = await exec(
    `SELECT a.id, a.ledger_id AS ledgerId, a.name, a.type, a.currency, a.current_balance AS balance,
            a.group_id AS groupId, g.name AS groupName,
            COALESCE(a.include_in_net_worth, g.include_in_net_worth, 1) AS inw
       FROM accounts a LEFT JOIN account_groups g ON a.group_id = g.id
      ${where}
      ORDER BY g.sort_order, a.name`,
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledgerId),
    name: String(r.name),
    type: String(r.type),
    currency: String(r.currency),
    balance: Number(r.balance),
    groupId: r.groupId == null ? null : String(r.groupId),
    groupName: r.groupName == null ? null : String(r.groupName),
    includeInNetWorth: Number(r.inw),
  }));
}

/** Net worth = sum of balances for accounts that count (assets minus liabilities). */
export async function netWorth(exec: Exec, ledgerId: string): Promise<number> {
  const rows = await exec(
    `SELECT COALESCE(SUM(a.current_balance), 0) AS total
       FROM accounts a LEFT JOIN account_groups g ON a.group_id = g.id
      WHERE a.ledger_id = ? AND a.is_active = 1
        AND COALESCE(a.include_in_net_worth, g.include_in_net_worth, 1) = 1`,
    [ledgerId],
  );
  return Number(rows[0]?.total ?? 0);
}

export interface BalancePoint {
  date: string;
  balance: number;
}

export async function accountBalanceSeries(exec: Exec, accountId: string): Promise<BalancePoint[]> {
  const rows = await exec(
    'SELECT date, balance FROM account_balance_snapshots WHERE account_id = ? ORDER BY date',
    [accountId],
  );
  return rows.map((r) => ({ date: String(r.date), balance: Number(r.balance) }));
}

export async function setAccountDetails(
  exec: Exec,
  id: string,
  patch: { name?: string; type?: string; notes?: string },
): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  if (patch.name !== undefined) { sets.push('name = ?'); bind.push(patch.name); }
  if (patch.type !== undefined) { sets.push('type = ?'); bind.push(patch.type); }
  if (patch.notes !== undefined) { sets.push('notes = ?'); bind.push(patch.notes ?? null); }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE accounts SET ${sets.join(', ')} WHERE id = ?`, bind);
}
