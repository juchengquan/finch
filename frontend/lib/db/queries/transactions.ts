// DB-backed transaction interactions, run server-side against the shared DB
// (lib/db/server.ts). Reads return the store's `Tx` shape so the projected
// state can feed the store directly.

import type { Exec } from '@/lib/db/repo';
import type { Tx } from '@/lib/store';
import { convertToBase } from './rates';

export type Direction = 'all' | 'in' | 'out';

export interface ListOptions {
  ledgerId: string;
  direction?: Direction;
  query?: string;
  accountId?: string;
  categoryId?: string;
  status?: 'pending' | 'confirmed';
  from?: string; // inclusive YYYY-MM-DD
  to?: string; // inclusive YYYY-MM-DD
  /** Filter by absolute amount, magnitude in the ledger base currency. */
  minAmount?: number;
  maxAmount?: number;
  limit?: number;
  offset?: number;
}

export interface AddInput {
  ledgerId: string;
  accountId: string;
  amount: number; // signed, native (in `currency`)
  amountBase?: number; // signed, ledger base; defaults to `amount` (same-currency)
  currency?: string; // native currency; defaults to the account's currency
  merchant: string;
  categoryId?: string | null;
  date: string;
  time?: string;
  note?: string;
  status?: 'pending' | 'confirmed';
  /** Explicit classification; defaults to income/expense by amount sign.
   *  'adjustment' is the manual balance-reconciliation kind. */
  kind?: 'income' | 'expense' | 'transfer' | 'adjustment';
}

export function rowToTx(r: Record<string, unknown>): Tx {
  // The store/derive `amount` is the ledger-base figure (DB `amount_base`);
  // DB `amount` is the native amount the user entered, kept for display.
  const amount = Number(r.amount_base);
  const nativeAmount = Number(r.amount);
  return {
    id: String(r.id),
    merchant: String(r.description ?? ''),
    category: r.category_id === null || r.category_id === undefined ? null : String(r.category_id),
    amount,
    currency: r.currency == null ? undefined : String(r.currency),
    nativeAmount,
    account: String(r.account_id),
    date: String(r.date),
    time: r.time == null ? undefined : String(r.time),
    note: r.notes == null ? undefined : String(r.notes),
    pending: String(r.status) === 'pending',
    kind: String(r.kind) as Tx['kind'],
    ledgerId: String(r.ledger_id),
    transferGroupId: r.transfer_group_id == null ? undefined : String(r.transfer_group_id),
    sourceTemplateId: r.source_template_id == null ? undefined : String(r.source_template_id),
  };
}

/** List transactions for a ledger with optional search / filters. */
export async function listTransactions(exec: Exec, opts: ListOptions): Promise<Tx[]> {
  const where: string[] = ['ledger_id = ?'];
  const bind: (string | number | null)[] = [opts.ledgerId];

  if (opts.direction === 'in') where.push('amount > 0');
  if (opts.direction === 'out') where.push('amount < 0');
  if (opts.query) {
    where.push('description LIKE ?');
    bind.push(`%${opts.query}%`);
  }
  if (opts.accountId) {
    where.push('account_id = ?');
    bind.push(opts.accountId);
  }
  if (opts.categoryId) {
    where.push('category_id = ?');
    bind.push(opts.categoryId);
  }
  if (opts.status) {
    where.push('status = ?');
    bind.push(opts.status);
  }
  if (opts.from) {
    where.push('date >= ?');
    bind.push(opts.from);
  }
  if (opts.to) {
    where.push('date <= ?');
    bind.push(opts.to);
  }
  if (opts.minAmount != null) {
    where.push('ABS(amount_base) >= ?');
    bind.push(opts.minAmount);
  }
  if (opts.maxAmount != null) {
    where.push('ABS(amount_base) <= ?');
    bind.push(opts.maxAmount);
  }

  let sql = `SELECT * FROM transactions WHERE ${where.join(' AND ')} ORDER BY date DESC, time DESC`;
  if (opts.limit != null) {
    sql += ' LIMIT ?';
    bind.push(opts.limit);
    sql += ' OFFSET ?';
    bind.push(opts.offset ?? 0);
  }
  const rows = await exec(sql, bind);
  return rows.map(rowToTx);
}

export async function getTransaction(exec: Exec, id: string): Promise<Tx | null> {
  const rows = await exec('SELECT * FROM transactions WHERE id = ?', [id]);
  return rows[0] ? rowToTx(rows[0]) : null;
}

function newId(): string {
  return `t-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

/** Insert a transaction; confirmed rows move the account balance via the insert trigger. */
export async function addTransaction(exec: Exec, input: AddInput): Promise<string> {
  const id = newId();
  const status = input.status ?? 'confirmed';
  const acct = await exec(
    `SELECT a.currency, l.base_currency
       FROM accounts a JOIN ledgers l ON l.id = a.ledger_id
      WHERE a.id = ?`,
    [input.accountId],
  );
  const accountCurrency = String(acct[0]?.currency ?? 'USD');
  const ledgerBase = String(acct[0]?.base_currency ?? accountCurrency);
  const currency = input.currency ?? accountCurrency;
  // `amount` is native (in `currency`); `amount_base` is the LEDGER-base figure
  // that drives cross-account reports — convert native → ledger base + lock the
  // rate. The account balance is moved by the insert trigger (confirmed rows
  // only), using the account-currency delta. (A three-currency row — entry ≠
  // account ≠ base — is unsupported; the entry currency tracks the account's.)
  const conv = await convertToBase(exec, input.amount, currency, ledgerBase, input.date);
  const amountBase = conv.amountBase;
  const exchangeRate = conv.rate;
  const kind = input.kind ?? (amountBase > 0 ? 'income' : 'expense');
  await exec(
    `INSERT INTO transactions
      (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,
       description,category_id,transfer_group_id,kind,status,confirmed_at,
       currency,notes,created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now'))`,
    [
      id, input.ledgerId, input.accountId, input.date, input.time ?? null, input.amount, amountBase, exchangeRate,
      input.merchant, input.categoryId ?? null, null, kind, status, status === 'confirmed' ? new Date().toISOString() : null,
      currency, input.note || null,
    ],
  );
  return id;
}

export async function updateTransaction(
  exec: Exec,
  id: string,
  patch: Partial<Pick<Tx, 'merchant' | 'category' | 'amount' | 'date' | 'time' | 'note'>>,
): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  if (patch.merchant !== undefined) { sets.push('description = ?'); bind.push(patch.merchant); }
  if (patch.category !== undefined) { sets.push('category_id = ?'); bind.push(patch.category); }
  if (patch.date !== undefined) { sets.push('date = ?'); bind.push(patch.date); }
  if (patch.time !== undefined) { sets.push('time = ?'); bind.push(patch.time ?? null); }
  if (patch.note !== undefined) { sets.push('notes = ?'); bind.push(patch.note ?? null); }
  if (patch.amount !== undefined) {
    // `amount` is native (the transaction's own currency). Re-derive the
    // ledger-base figure + lock the rate, using the (possibly edited) date for
    // the rate lookup — so an edit stays correct when account currency ≠ base.
    const [row] = await exec(
      `SELECT t.currency, t.date, l.base_currency
         FROM transactions t JOIN accounts a ON a.id = t.account_id JOIN ledgers l ON l.id = a.ledger_id
        WHERE t.id = ?`,
      [id],
    );
    const currency = String(row?.currency ?? 'USD');
    const ledgerBase = String(row?.base_currency ?? currency);
    const rateDate = patch.date ?? String(row?.date ?? '');
    const conv = await convertToBase(exec, patch.amount, currency, ledgerBase, rateDate);
    sets.push('amount = ?', 'amount_base = ?', 'exchange_rate = ?');
    bind.push(patch.amount, conv.amountBase, conv.rate);
  }
  if (!sets.length) return;
  bind.push(id);
  await exec(`UPDATE transactions SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Hard-delete a transaction (tags/splits cascade). Returns its account_id so the
 *  caller can recompute that account's balance afterward. */
export async function deleteTransactionRow(exec: Exec, id: string): Promise<string | null> {
  const rows = await exec('SELECT account_id FROM transactions WHERE id = ?', [id]);
  if (!rows.length) return null;
  await exec('DELETE FROM transactions WHERE id = ?', [id]);
  return String(rows[0].account_id);
}

/** Confirm a pending transaction so it counts in reports. */
export async function confirmTransaction(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE transactions SET status = 'confirmed', confirmed_at = ? WHERE id = ? AND status = 'pending'", [
    new Date().toISOString(),
    id,
  ]);
}
