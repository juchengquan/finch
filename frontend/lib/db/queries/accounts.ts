// DB-backed account interactions: listing with group + balance, the balance
// curve from snapshots, net worth, and editing account details.

import type { Exec } from '@/lib/db/repo';
import { defaultIncludeInNetWorth } from '@/lib/account-types';
import { convertToBase } from './rates';

/**
 * Recompute an account's current_balance from its opening balance + confirmed
 * transactions. The insert trigger moves the balance for new confirmed rows, so
 * any edit/confirm/delete that changes the confirmed set must call this.
 *
 * Only `confirmed` rows move the balance: `pending` (unconfirmed) transactions
 * are excluded so they don't affect accounts until confirmed. The delta is taken
 * in the account's currency (native amount when the entry is in that currency,
 * else the ledger-base figure for a foreign entry on a base-currency account).
 */
export async function recomputeAccount(exec: Exec, accountId: string): Promise<void> {
  const acc = await exec('SELECT opening_balance, currency FROM accounts WHERE id = ?', [accountId]);
  if (!acc.length) return;
  const accountCurrency = String(acc[0].currency ?? 'USD');
  let running = Number(acc[0].opening_balance ?? 0);
  const rows = await exec(
    "SELECT amount, amount_base, currency FROM transactions WHERE account_id = ? AND status = 'confirmed'",
    [accountId],
  );
  for (const r of rows) {
    const delta = String(r.currency) === accountCurrency ? Number(r.amount) : Number(r.amount_base);
    running = Math.round((running + delta) * 100) / 100;
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
  /** Ledger-base value of the opening balance, locked at account creation. The
   *  cost-basis half of the unrealized-FX calculation: cost basis =
   *  openingBalanceBase + Σ amount_base of confirmed transactions. */
  openingBalanceBase: number;
  groupId: string | null;
  groupName: string | null;
  includeInNetWorth: number; // 0/1; defaulted from `type` at create, flippable per account
  color: string | null;
  sortOrder: number;
}

/** List accounts; pass a ledgerId to scope, or omit for all ledgers. */
export async function listAccounts(exec: Exec, ledgerId?: string): Promise<AccountRow[]> {
  const where = ledgerId ? 'WHERE a.ledger_id = ? AND a.is_active = 1' : 'WHERE a.is_active = 1';
  const rows = await exec(
    `SELECT a.id, a.ledger_id AS ledgerId, a.name, a.type, a.currency, a.current_balance AS balance,
            a.opening_balance_base AS openingBalanceBase,
            a.group_id AS groupId, g.name AS groupName, a.color,
            a.sort_order AS sortOrder, a.include_in_net_worth AS inw
       FROM accounts a LEFT JOIN account_groups g ON a.group_id = g.id
      ${where}
      ORDER BY g.sort_order, a.sort_order, a.name`,
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledgerId),
    name: String(r.name),
    type: String(r.type),
    currency: String(r.currency),
    balance: Number(r.balance),
    openingBalanceBase: Number(r.openingBalanceBase ?? 0),
    groupId: r.groupId == null ? null : String(r.groupId),
    groupName: r.groupName == null ? null : String(r.groupName),
    includeInNetWorth: Number(r.inw),
    color: r.color == null ? null : String(r.color),
    sortOrder: Number(r.sortOrder ?? 0),
  }));
}

/** Net worth = sum of balances for accounts that count (assets minus liabilities). */
export async function netWorth(exec: Exec, ledgerId: string): Promise<number> {
  const rows = await exec(
    `SELECT COALESCE(SUM(current_balance), 0) AS total
       FROM accounts
      WHERE ledger_id = ? AND is_active = 1 AND include_in_net_worth = 1`,
    [ledgerId],
  );
  return Number(rows[0]?.total ?? 0);
}

// `currency` is intentionally not editable — it's fixed at account creation
// (changing it would re-interpret stored native amounts / locked amount_base).
export interface AccountPatch {
  name?: string;
  type?: string;
  color?: string | null;
  groupId?: string | null;
  /** Per-account net-worth flag. Defaulted from `type` on create; flippable. */
  includeInNetWorth?: number;
}

// `currency` is deliberately not patchable — it's fixed at account creation
// (see AccountPatch in lib/store.ts). Any stray key without a column mapping is
// skipped below.
const PATCH_COLUMNS: Record<keyof AccountPatch, string> = {
  name: 'name',
  type: 'type',
  color: 'color',
  groupId: 'group_id',
  includeInNetWorth: 'include_in_net_worth',
};

/** Update an account's editable fields on the real table (replaces the old shim). */
export async function updateAccount(exec: Exec, id: string, patch: AccountPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof AccountPatch)[]) {
    const value = patch[key];
    const col = PATCH_COLUMNS[key];
    if (value === undefined || !col) continue; // skip undefined + non-patchable keys (e.g. currency)
    sets.push(`${col} = ?`);
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
}

/** Insert a new account; current_balance starts at the opening balance.
 *  Sort_order is appended after the existing rows in the same group (or
 *  ungrouped bucket) so new accounts land at the bottom of the list.
 *
 *  opening_balance is the native figure the user typed; opening_balance_base
 *  locks its ledger-base equivalent at today's rate. The base figure stays
 *  put when FX moves later, so the account's cost basis is stable and any
 *  drift from the live valuation shows up as unrealized FX gain/loss. */
export async function createAccount(exec: Exec, a: NewAccount): Promise<void> {
  const rows = await exec(
    a.groupId == null
      ? 'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM accounts WHERE ledger_id = ? AND group_id IS NULL'
      : 'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM accounts WHERE ledger_id = ? AND group_id = ?',
    a.groupId == null ? [a.ledgerId] : [a.ledgerId, a.groupId],
  );
  const sortOrder = Number(rows[0]?.n ?? 0);
  const inw = defaultIncludeInNetWorth(a.type);
  const lRows = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [a.ledgerId]);
  const ledgerBase = String(lRows[0]?.base_currency ?? a.currency);
  const today = new Date().toISOString().slice(0, 10);
  const { amountBase: openingBase } = await convertToBase(exec, a.openingBalance, a.currency, ledgerBase, today);
  await exec(
    `INSERT INTO accounts
       (id,ledger_id,group_id,name,type,currency,current_balance,opening_balance,opening_balance_base,color,sort_order,include_in_net_worth,is_active,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,1,datetime('now'),datetime('now'))`,
    [a.id, a.ledgerId, a.groupId, a.name, a.type, a.currency, a.openingBalance, a.openingBalance, openingBase, a.color, sortOrder, inw],
  );
}

/** Soft-delete: keep transaction history, drop the account from the active list.
 *  Stamps archived_at so the UI can surface "archived <date>" later. */
export async function archiveAccount(exec: Exec, id: string): Promise<void> {
  await exec(
    "UPDATE accounts SET is_active = 0, archived_at = datetime('now'), updated_at = datetime('now') WHERE id = ?",
    [id],
  );
}

/** Reverse archive — restore an archived account to the active list and clear archived_at. */
export async function unarchiveAccount(exec: Exec, id: string): Promise<void> {
  await exec(
    "UPDATE accounts SET is_active = 1, archived_at = NULL, updated_at = datetime('now') WHERE id = ?",
    [id],
  );
}

/** Hard delete — only safe when the account has no transactions (FK is RESTRICT). */
export async function deleteAccount(exec: Exec, id: string): Promise<void> {
  const [{ n }] = await exec('SELECT COUNT(*) AS n FROM transactions WHERE account_id = ?', [id]) as { n: number }[];
  if (Number(n) > 0) throw new Error('Account has transactions — archive it instead');
  await exec('DELETE FROM accounts WHERE id = ?', [id]);
}
