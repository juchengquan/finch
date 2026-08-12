// DB-backed account interactions: listing with group + balance, the balance
// curve from snapshots, net worth, and editing account details.

import type { Exec } from '../core/repo';
import { defaultIncludeInNetWorth } from '@/lib/account-types';
import { recomputeAccountFromPostings, postOpening, deleteEntry, resolveEntryRef } from '../core/entries';
import { I18nError } from '@/lib/i18n-error';
import { ACCOUNT_ERROR_CODES } from '@/lib/db/domain/accounts/errors';
import type { AccountRow, AccountPatch, NewAccount } from '@/lib/db/domain/accounts/types';
// convertToBase removed — opening_balance derivation now uses postOpening (entries layer)

/**
 * Recompute an account's current_balance from confirmed postings.
 * Delegates to recomputeAccountFromPostings (DOUBLE_ENTRY_PLAN §3.2).
 * Keep this export — many call sites reference it; only the body changes.
 */
export async function recomputeAccount(exec: Exec, accountId: string): Promise<void> {
  // One-line delegate to the entries-layer chokepoint (postings is the source
  // of truth; opening entry is included in the sum — no separate seed term).
  await recomputeAccountFromPostings(exec, accountId);
}

/** Recompute the account that the given entry/posting ref belongs to (if any).
 *  Resolves via resolveEntryRef so callers updated in B3b still work by
 *  passing either a posting id or an entry id. */
export async function recomputeForTransaction(exec: Exec, txnId: string): Promise<void> {
  const ref = await resolveEntryRef(exec, txnId);
  if (ref?.accountId) await recomputeAccount(exec, ref.accountId);
}

/** List accounts; pass a ledgerId to scope, or omit for all ledgers. */
export async function listAccounts(exec: Exec, ledgerId?: string): Promise<AccountRow[]> {
  const where = ledgerId ? 'WHERE a.ledger_id = ? AND a.is_active = 1' : 'WHERE a.is_active = 1';
  const rows = await exec(
    `SELECT a.id, a.ledger_id AS ledgerId, a.name, a.type, a.currency, a.current_balance AS balance,
            -- Opening balance projected from the opening entry's account leg (id-agnostic):
            -- avoids storing a redundant column; postOpening is the write path.
            COALESCE(op.amount, 0) AS openingBalance,
            COALESCE(op.amount_base, 0) AS openingBalanceBase,
            a.group_id AS groupId, g.name AS groupName, a.color,
            a.sort_order AS sortOrder, a.include_in_net_worth AS inw,
            a.is_active AS isActive,
            a.last_reconciled_at AS lastReconciledAt,
            a.last_reconciled_balance AS lastReconciledBalance,
            a.archived_at AS archivedAt
       FROM accounts a
       LEFT JOIN account_groups g ON a.group_id = g.id
       LEFT JOIN postings op ON op.entry_id = 'open-' || a.id AND op.account_id = a.id
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
    openingBalance: Number(r.openingBalance ?? 0),
    openingBalanceBase: Number(r.openingBalanceBase ?? 0),
    groupId: r.groupId == null ? null : String(r.groupId),
    groupName: r.groupName == null ? null : String(r.groupName),
    includeInNetWorth: Number(r.inw),
    isActive: Number(r.isActive ?? 0) !== 0,
    color: r.color == null ? null : String(r.color),
    sortOrder: Number(r.sortOrder ?? 0),
    lastReconciledAt: r.lastReconciledAt == null ? null : String(r.lastReconciledAt),
    lastReconciledBalance: r.lastReconciledBalance == null ? null : Number(r.lastReconciledBalance),
    archivedAt: r.archivedAt == null ? null : String(r.archivedAt),
  }));
}

/** List archived (is_active=0) accounts; pass a ledgerId to scope, or omit for
 *  all ledgers. Same row shape as listAccounts (the mapper is duplicated
 *  below; both queries return the canonical AccountRow so consumers can
 *  treat them uniformly). Ordered by archived_at DESC (most recent first). */
export async function listArchivedAccounts(exec: Exec, ledgerId?: string): Promise<AccountRow[]> {
  const where = ledgerId ? 'WHERE a.ledger_id = ? AND a.is_active = 0' : 'WHERE a.is_active = 0';
  const rows = await exec(
    `SELECT a.id, a.ledger_id AS ledgerId, a.name, a.type, a.currency, a.current_balance AS balance,
            COALESCE(op.amount, 0) AS openingBalance,
            COALESCE(op.amount_base, 0) AS openingBalanceBase,
            a.group_id AS groupId, g.name AS groupName, a.color,
            a.sort_order AS sortOrder, a.include_in_net_worth AS inw,
            a.is_active AS isActive,
            a.archived_at AS archivedAt,
            a.last_reconciled_at AS lastReconciledAt,
            a.last_reconciled_balance AS lastReconciledBalance
       FROM accounts a
       LEFT JOIN account_groups g ON a.group_id = g.id
       LEFT JOIN postings op ON op.entry_id = 'open-' || a.id AND op.account_id = a.id
      ${where}
      ORDER BY a.archived_at DESC`,
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledgerId),
    name: String(r.name),
    type: String(r.type),
    currency: String(r.currency),
    balance: Number(r.balance),
    openingBalance: Number(r.openingBalance ?? 0),
    openingBalanceBase: Number(r.openingBalanceBase ?? 0),
    groupId: r.groupId == null ? null : String(r.groupId),
    groupName: r.groupName == null ? null : String(r.groupName),
    includeInNetWorth: Number(r.inw),
    isActive: Number(r.isActive ?? 0) !== 0,
    archivedAt: r.archivedAt == null ? null : String(r.archivedAt),
    color: r.color == null ? null : String(r.color),
    sortOrder: Number(r.sortOrder ?? 0),
    lastReconciledAt: r.lastReconciledAt == null ? null : String(r.lastReconciledAt),
    lastReconciledBalance: r.lastReconciledBalance == null ? null : Number(r.lastReconciledBalance),
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

// `currency` is deliberately not patchable — it's fixed at account creation
  // (see AccountPatch in lib/db/domain/accounts/types). Any stray key without a column mapping is
// skipped below.
const PATCH_COLUMNS: Record<keyof AccountPatch, string> = {
  name: 'name',
  type: 'type',
  color: 'color',
  groupId: 'group_id',
  includeInNetWorth: 'include_in_net_worth',
  sortOrder: 'sort_order',
  icon: 'icon',
  notes: 'notes',
  statementDay: 'statement_day',
  dueDay: 'due_day',
  creditLimit: 'credit_limit',
  institution: 'institution',
  accountLast4: 'account_last4',
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

/** Insert a new account; current_balance starts at 0.
 *  Sort_order is appended after the existing rows in the same group (or
 *  ungrouped bucket) so new accounts land at the bottom of the list.
 *
 *  When openingBalance ≠ 0, a postOpening entry (pre-cleared, dated today)
 *  is posted and recomputeAccount brings current_balance to the opening figure.
 *  The opening entry IS the cost-basis anchor (DOUBLE_ENTRY_PLAN §6). */
export async function createAccount(exec: Exec, a: NewAccount): Promise<void> {
  const rows = await exec(
    a.groupId == null
      ? 'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM accounts WHERE ledger_id = ? AND group_id IS NULL'
      : 'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM accounts WHERE ledger_id = ? AND group_id = ?',
    a.groupId == null ? [a.ledgerId] : [a.ledgerId, a.groupId],
  );
  const sortOrder = Number(rows[0]?.n ?? 0);
  const inw = defaultIncludeInNetWorth(a.type);
  const today = new Date().toISOString().slice(0, 10);
  await exec(
    `INSERT INTO accounts
       (id,ledger_id,group_id,name,type,currency,current_balance,color,icon,notes,statement_day,due_day,credit_limit,institution,account_last4,sort_order,include_in_net_worth,is_active,created_at,updated_at)
     VALUES (?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,1,datetime('now'),datetime('now'))`,
    [a.id, a.ledgerId, a.groupId, a.name, a.type, a.currency, a.color,
     a.icon ?? null, a.notes ?? null, a.statementDay ?? null, a.dueDay ?? null, a.creditLimit ?? null,
     a.institution ?? null, a.accountLast4 ?? null,
     sortOrder, inw],
  );
  if (a.openingBalance !== 0) {
    await postOpening(exec, { ledgerId: a.ledgerId, accountId: a.id, amount: a.openingBalance, date: a.openingDate ?? today });
  }
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

/** Hard delete — only safe when the account has no postings beyond the
 *  optional opening entry. If the ONLY postings are from the opening entry,
 *  auto-delete that entry first, then delete the account. If there are other
 *  postings (real transactions), throw so the caller can archive instead. */
export async function deleteAccount(exec: Exec, id: string): Promise<void> {
  const [{ total }] = (await exec('SELECT COUNT(*) AS total FROM postings WHERE account_id = ?', [id])) as { total: number }[];
  const totalCount = Number(total);

  if (totalCount > 0) {
    // Count postings that are NOT part of the opening entry.
    const openEntryId = `open-${id}`;
    const [{ other }] = (await exec(
      'SELECT COUNT(*) AS other FROM postings WHERE account_id = ? AND entry_id != ?',
      [id, openEntryId],
    )) as { other: number }[];
    if (Number(other) > 0) {
      throw new I18nError(
        ACCOUNT_ERROR_CODES.hasTransactions,
        {},
        'Account has transactions — archive it instead',
      );
    }
    // Only the opening entry exists — delete it first.
    await deleteEntry(exec, openEntryId);
  }
  await exec('DELETE FROM accounts WHERE id = ?', [id]);
}
