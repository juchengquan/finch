// DB-backed account interactions: listing with group + balance, the balance
// curve from snapshots, net worth, and editing account details.

import type { Exec } from '@/lib/db/repo';

/**
 * Recompute an account's running balances from its opening balance forward.
 * The balance trigger only fires on INSERT, so any edit/cancel/delete that
 * changes the amount or membership of the live txn set must call this to keep
 * balance_after (per row) and current_balance correct.
 */
export async function recomputeAccount(exec: Exec, accountId: string): Promise<void> {
  const acc = await exec('SELECT opening_balance FROM accounts WHERE id = ?', [accountId]);
  if (!acc.length) return;
  let running = Number(acc[0].opening_balance ?? 0);
  const rows = await exec(
    "SELECT id, amount_base FROM transactions WHERE account_id = ? AND status != 'cancelled' ORDER BY date, time, created_at",
    [accountId],
  );
  for (const r of rows) {
    running = Math.round((running + Number(r.amount_base)) * 100) / 100;
    await exec('UPDATE transactions SET balance_after = ? WHERE id = ?', [running, String(r.id)]);
  }
  await exec("UPDATE accounts SET current_balance = ?, updated_at = datetime('now') WHERE id = ?", [running, accountId]);
}

/** Recompute the account that the given transaction belongs to (if any). */
export async function recomputeForTransaction(exec: Exec, txnId: string): Promise<void> {
  const rows = await exec('SELECT account_id FROM transactions WHERE id = ?', [txnId]);
  if (rows.length) await recomputeAccount(exec, String(rows[0].account_id));
}

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
  color: string | null;
  last4: string | null;
  institution: string | null;
  routing: string | null;
}

/** List accounts; pass a ledgerId to scope, or omit for all ledgers. */
export async function listAccounts(exec: Exec, ledgerId?: string): Promise<AccountRow[]> {
  const where = ledgerId ? 'WHERE a.ledger_id = ? AND a.is_active = 1' : 'WHERE a.is_active = 1';
  const rows = await exec(
    `SELECT a.id, a.ledger_id AS ledgerId, a.name, a.type, a.currency, a.current_balance AS balance,
            a.group_id AS groupId, g.name AS groupName, a.color, a.last4, a.institution, a.routing,
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
    color: r.color == null ? null : String(r.color),
    last4: r.last4 == null ? null : String(r.last4),
    institution: r.institution == null ? null : String(r.institution),
    routing: r.routing == null ? null : String(r.routing),
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

export interface AccountPatch {
  name?: string;
  type?: string;
  notes?: string | null;
  color?: string | null;
  last4?: string | null;
  institution?: string | null;
  routing?: string | null;
  groupId?: string | null;
}

const PATCH_COLUMNS: Record<keyof AccountPatch, string> = {
  name: 'name',
  type: 'type',
  notes: 'notes',
  color: 'color',
  last4: 'last4',
  institution: 'institution',
  routing: 'routing',
  groupId: 'group_id',
};

/** Update an account's editable fields on the real table (replaces the old shim). */
export async function updateAccount(exec: Exec, id: string, patch: AccountPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof AccountPatch)[]) {
    const value = patch[key];
    if (value === undefined) continue;
    sets.push(`${PATCH_COLUMNS[key]} = ?`);
    bind.push(value ?? null);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE accounts SET ${sets.join(', ')} WHERE id = ?`, bind);
}

export interface NewAccount {
  id: string;
  ledgerId: string;
  name: string;
  type: string;
  currency: string;
  groupId: string | null;
  openingBalance: number;
  color: string | null;
  last4: string | null;
}

/** Insert a new account; current_balance starts at the opening balance. */
export async function createAccount(exec: Exec, a: NewAccount): Promise<void> {
  await exec(
    `INSERT INTO accounts
       (id,ledger_id,group_id,name,type,currency,current_balance,opening_balance,color,last4,include_in_net_worth,is_active,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,1,datetime('now'),datetime('now'))`,
    [a.id, a.ledgerId, a.groupId, a.name, a.type, a.currency, a.openingBalance, a.openingBalance, a.color, a.last4, null],
  );
}

/** Soft-delete: keep transaction history, drop the account from the active list. */
export async function archiveAccount(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE accounts SET is_active = 0, updated_at = datetime('now') WHERE id = ?", [id]);
}

/** Hard delete — only safe when the account has no transactions (FK is RESTRICT). */
export async function deleteAccount(exec: Exec, id: string): Promise<void> {
  const [{ n }] = await exec('SELECT COUNT(*) AS n FROM transactions WHERE account_id = ?', [id]) as { n: number }[];
  if (Number(n) > 0) throw new Error('Account has transactions — archive it instead');
  await exec('DELETE FROM accounts WHERE id = ?', [id]);
}
