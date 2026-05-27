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
    recurring: !!Number(r.recurring),
    kind: amount > 0 ? 'income' : undefined,
    ledgerId: String(r.ledger_id),
    transferGroupId: r.transfer_group_id == null ? undefined : String(r.transfer_group_id),
  };
}

/** List transactions for a ledger with optional search / filters. Excludes cancelled. */
export async function listTransactions(exec: Exec, opts: ListOptions): Promise<Tx[]> {
  const where: string[] = ['ledger_id = ?', "status != 'cancelled'"];
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

/** Insert a transaction; computes balance_after from the account's current balance. */
export async function addTransaction(exec: Exec, input: AddInput): Promise<string> {
  const id = newId();
  const status = input.status ?? 'confirmed';
  const acct = await exec('SELECT current_balance, currency FROM accounts WHERE id = ?', [input.accountId]);
  const currentBalance = Number(acct[0]?.current_balance ?? 0);
  const baseCurrency = String(acct[0]?.currency ?? 'USD');
  const currency = input.currency ?? baseCurrency;
  // `amount` is native (in `currency`); `amount_base` is the ledger-base figure
  // that drives balances/reports. Convert via the exchange_rates table and lock
  // the rate + date on the row.
  const conv = await convertToBase(exec, input.amount, currency, baseCurrency, input.date);
  const amountBase = conv.amountBase;
  const exchangeRate = conv.rate;
  const balanceAfter = Math.round((currentBalance + amountBase) * 100) / 100;
  await exec(
    `INSERT INTO transactions
      (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,exchange_rate_date,
       description,category_id,counterparty_id,transfer_group_id,status,confirmed_at,
       balance_after,currency,notes,recurring,created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now'))`,
    [
      id, input.ledgerId, input.accountId, input.date, input.time ?? null, input.amount, amountBase, exchangeRate, input.date,
      input.merchant, input.categoryId ?? null, null, null, status, status === 'confirmed' ? new Date().toISOString() : null,
      balanceAfter, currency, input.note || null, 0,
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
  if (patch.amount !== undefined) { sets.push('amount = ?', 'amount_base = ?'); bind.push(patch.amount, patch.amount); }
  if (patch.date !== undefined) { sets.push('date = ?'); bind.push(patch.date); }
  if (patch.time !== undefined) { sets.push('time = ?'); bind.push(patch.time ?? null); }
  if (patch.note !== undefined) { sets.push('notes = ?'); bind.push(patch.note ?? null); }
  if (!sets.length) return;
  bind.push(id);
  await exec(`UPDATE transactions SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Void a transaction (soft delete) — keeps history, drops it from reports. */
export async function cancelTransaction(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE transactions SET status = 'cancelled' WHERE id = ?", [id]);
}

/** Confirm a pending transaction so it counts in reports. */
export async function confirmTransaction(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE transactions SET status = 'confirmed', confirmed_at = ? WHERE id = ? AND status = 'pending'", [
    new Date().toISOString(),
    id,
  ]);
}
