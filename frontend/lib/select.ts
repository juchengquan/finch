// Client-side selectors over the store's projected state. These mirror the SQL
// read queries in lib/db/queries/* so the read screens can compute from the
// store (which mirrors the server DB) instead of a second in-browser query DB.

import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';
import type { ListOptions } from '@/lib/db/queries/transactions';
import type { Transfer } from '@/lib/db/queries/transfers';

const ledgerOf = (t: Tx) => t.ledgerId ?? 'personal';

/** Mirrors listTransactions(): filter + sort an in-memory Tx list. */
export function selectTransactions(txns: Tx[], opts: ListOptions): Tx[] {
  let out = txns.filter((t) => ledgerOf(t) === opts.ledgerId);
  if (opts.direction === 'in') out = out.filter((t) => t.amount > 0);
  if (opts.direction === 'out') out = out.filter((t) => t.amount < 0);
  if (opts.query) {
    const q = opts.query.toLowerCase();
    out = out.filter((t) => t.merchant.toLowerCase().includes(q));
  }
  if (opts.accountId) out = out.filter((t) => t.account === opts.accountId);
  if (opts.categoryId) out = out.filter((t) => t.category === opts.categoryId);
  if (opts.status) out = out.filter((t) => t.pending === (opts.status === 'pending'));
  if (opts.from) out = out.filter((t) => t.date >= opts.from!);
  if (opts.to) out = out.filter((t) => t.date <= opts.to!);
  out = [...out].sort((a, b) => {
    if (a.date !== b.date) return a.date < b.date ? 1 : -1;
    const at = a.time ?? '';
    const bt = b.time ?? '';
    return at < bt ? 1 : at > bt ? -1 : 0;
  });
  if (opts.limit != null) {
    const off = opts.offset ?? 0;
    out = out.slice(off, off + opts.limit);
  }
  return out;
}

/** Confirmed expense total per category (positive magnitude). Pass `month`
 *  (YYYY-MM) to scope to a single month; omit for all-time. */
export function categorySpend(txns: Tx[], ledgerId: string, month?: string): Record<string, number> {
  const m: Record<string, number> = {};
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (month && t.date.slice(0, 7) !== month) continue;
    if (t.pending || t.amount >= 0 || t.transferGroupId || !t.category) continue;
    m[t.category] = (m[t.category] ?? 0) + -t.amount;
  }
  return m;
}

/** The latest transaction month (YYYY-MM) for a ledger; '' when it has none. */
export function currentMonth(txns: Tx[], ledgerId?: string): string {
  let max = '';
  for (const t of txns) {
    if (ledgerId && ledgerOf(t) !== ledgerId) continue;
    if (t.date > max) max = t.date;
  }
  return max.slice(0, 7);
}

/** The calendar month before `month` (YYYY-MM). */
export function prevMonth(month: string): string {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(y, m - 2, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

/** Balance of one account from the projected account rows. */
export function accountBalance(accounts: AccountRow[], accountId: string): number {
  return accounts.find((a) => a.id === accountId)?.balance ?? 0;
}

const byDateAsc = (a: Tx, b: Tx) => {
  if (a.date !== b.date) return a.date < b.date ? -1 : 1;
  const at = a.time ?? '';
  const bt = b.time ?? '';
  return at < bt ? -1 : at > bt ? 1 : 0;
};

// Reconstruct the running-balance curve from a transaction set whose final value
// is `endValue`: opening = end − Σamounts, then accumulate per transaction.
function runningSeries(txns: Tx[], endValue: number): number[] {
  const rows = [...txns].sort(byDateAsc);
  const opening = endValue - rows.reduce((s, t) => s + t.amount, 0);
  const out = [opening];
  let bal = opening;
  for (const t of rows) {
    bal += t.amount;
    out.push(bal);
  }
  return out;
}

/** Balance-over-time series for one account (ends at its current balance). */
export function balanceSeries(txns: Tx[], accountId: string, currentBalance: number): number[] {
  return runningSeries(txns.filter((t) => t.account === accountId), currentBalance);
}

/** Net-worth-over-time series for a ledger (ends at the current total). */
export function netWorthSeries(txns: Tx[], accounts: AccountRow[], ledgerId: string): number[] {
  const total = accounts.filter((a) => a.ledgerId === ledgerId).reduce((s, a) => s + a.balance, 0);
  return runningSeries(txns.filter((t) => (t.ledgerId ?? 'personal') === ledgerId), total);
}

/** Mirrors listTransfers(): reconstruct transfers by grouping on transferGroupId. */
export function selectTransfers(txns: Tx[], accounts: AccountRow[], ledgerId: string): Transfer[] {
  const nameById = new Map(accounts.filter((a) => a.ledgerId === ledgerId).map((a) => [a.id, a.name]));
  const groups = new Map<string, Tx[]>();
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId || !t.transferGroupId) continue;
    const arr = groups.get(t.transferGroupId);
    if (arr) arr.push(t);
    else groups.set(t.transferGroupId, [t]);
  }
  const out: Transfer[] = [];
  for (const [id, rows] of groups) {
    const out_ = rows.find((r) => r.amount < 0);
    const in_ = rows.find((r) => r.amount > 0);
    const date = rows.reduce((d, r) => (r.date > d ? r.date : d), rows[0].date);
    const note = rows.map((r) => r.note).find((n) => n != null) ?? null;
    const fromId = out_?.account ?? null;
    const toId = in_?.account ?? null;
    out.push({
      id,
      date,
      amount: out_ ? -out_.amount : 0,
      fromAccountId: fromId,
      toAccountId: toId,
      fromName: fromId == null ? null : nameById.get(fromId) ?? null,
      toName: toId == null ? null : nameById.get(toId) ?? null,
      note,
    });
  }
  return out.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
}
