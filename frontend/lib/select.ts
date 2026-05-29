// Client-side selectors over the store's projected state. These mirror the SQL
// read queries in lib/db/queries/* so the read screens can compute from the
// store (which mirrors the server DB) instead of a second in-browser query DB.

import type { Tx, RecurringTemplate } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';
import type { ListOptions } from '@/lib/db/queries/transactions';
import type { Transfer } from '@/lib/db/queries/transfers';
import type { ScheduledItem } from '@/lib/db/queries/planning';

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
  if (opts.minAmount != null) out = out.filter((t) => Math.abs(t.amount) >= opts.minAmount!);
  if (opts.maxAmount != null) out = out.filter((t) => Math.abs(t.amount) <= opts.maxAmount!);
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
 *  (YYYY-MM) to scope to a single month; omit for all-time. When a transaction
 *  has splits, each split's category + amountBase contributes instead of the
 *  parent's category/amount (mirrors the server's LEFT JOIN + COALESCE). */
export function categorySpend(txns: Tx[], ledgerId: string, month?: string): Record<string, number> {
  const m: Record<string, number> = {};
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (month && t.date.slice(0, 7) !== month) continue;
    if (t.pending || t.amount >= 0 || t.transferGroupId || t.isAdjustment) continue;
    if (t.splits && t.splits.length) {
      for (const s of t.splits) {
        if (!s.categoryId) continue;
        m[s.categoryId] = (m[s.categoryId] ?? 0) + -s.amountBase;
      }
    } else if (t.category) {
      m[t.category] = (m[t.category] ?? 0) + -t.amount;
    }
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

const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const r2 = (n: number) => Math.round(n * 100) / 100;

/** YYYY-MM keys for the N months ending at (and including) `endMonth`, oldest first. */
function monthsBack(endMonth: string, n: number): string[] {
  if (!endMonth) return [];
  const [y, m] = endMonth.split('-').map(Number);
  const out: string[] = [];
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(y, m - 1 - i, 1);
    out.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`);
  }
  return out;
}

/** Monthly expense totals (positive magnitude), oldest first. Mirrors MOCK.monthly. */
export function monthlySpending(txns: Tx[], ledgerId: string, endMonth: string, n: number): { m: string; v: number }[] {
  const months = monthsBack(endMonth, n);
  const by = new Map<string, number>(months.map((mo) => [mo, 0]));
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending || t.amount >= 0 || t.transferGroupId || t.isAdjustment) continue;
    const mo = t.date.slice(0, 7);
    if (!by.has(mo)) continue;
    by.set(mo, (by.get(mo) ?? 0) + -t.amount);
  }
  return months.map((mo) => ({ m: MONTH_LABELS[Number(mo.slice(5)) - 1], v: r2(by.get(mo) ?? 0) }));
}

/** Daily expense totals (positive) for the N days ending at `endDate`, oldest first. */
export function dailySpending(txns: Tx[], ledgerId: string, endDate: string, n: number): { date: string; value: number }[] {
  if (!endDate) return [];
  const out: { date: string; value: number }[] = [];
  const by = new Map<string, number>();
  const end = new Date(`${endDate}T00:00`);
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setDate(end.getDate() - i);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    by.set(key, 0);
    out.push({ date: key, value: 0 });
  }
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending || t.amount >= 0 || t.transferGroupId || t.isAdjustment) continue;
    if (!by.has(t.date)) continue;
    by.set(t.date, (by.get(t.date) ?? 0) + -t.amount);
  }
  for (const row of out) row.value = r2(by.get(row.date) ?? 0);
  return out;
}

/**
 * Net worth at the end of each of the last N months, oldest first. Computes the
 * opening total (current_total − Σ all txns) and accumulates forward, snapshotting
 * after every month. Uses string-prefix month comparison so it matches the
 * lexicographic YYYY-MM-DD date format used everywhere else.
 */
export function netWorthByMonth(
  txns: Tx[],
  accounts: AccountRow[],
  ledgerId: string,
  endMonth: string,
  n: number,
): { m: string; v: number }[] {
  if (!endMonth) return [];
  const months = monthsBack(endMonth, n);
  const total = accounts.filter((a) => a.ledgerId === ledgerId).reduce((s, a) => s + a.balance, 0);
  const ledgerTxns = txns.filter((t) => ledgerOf(t) === ledgerId);
  const sorted = [...ledgerTxns].sort(byDateAsc);
  const opening = total - sorted.reduce((s, t) => s + t.amount, 0);
  let bal = opening;
  let i = 0;
  return months.map((mo) => {
    while (i < sorted.length && sorted[i].date.slice(0, 7) <= mo) {
      bal += sorted[i].amount;
      i++;
    }
    return { m: MONTH_LABELS[Number(mo.slice(5)) - 1], v: r2(bal) };
  });
}

export interface MonthForecast {
  /** Confirmed expenses month-to-date (positive magnitude). */
  mtdSpent: number;
  /** Run-rate projection for remaining unscheduled days (mtdSpent/daysElapsed × daysRemaining). */
  unscheduledRest: number;
  /** Recurring expense templates due later this month (matched by `dayOfMonth`). */
  recurringRest: number;
  /** Scheduled-items (calendar bills) due later this month. */
  scheduledRest: number;
  /** Total: mtdSpent + unscheduledRest + recurringRest + scheduledRest. */
  projected: number;
  daysElapsed: number;
  daysRemaining: number;
  daysInMonth: number;
  /** Average daily spend MTD; 0 when no days elapsed. */
  dailyRunRate: number;
}

/**
 * Forecast the current month's total spending by combining month-to-date
 * confirmed expenses, a daily run-rate projection for the rest of the month,
 * and known upcoming costs (recurring templates + scheduled items).
 *
 * `today` is YYYY-MM-DD; if it falls outside `month`, the forecast collapses
 * to whatever's already known (no projection, no upcoming).
 */
export function monthForecast(
  txns: Tx[],
  recurring: RecurringTemplate[],
  scheduledItems: ScheduledItem[],
  ledgerId: string,
  month: string,
  today: string,
): MonthForecast | null {
  if (!month) return null;
  const [y, m] = month.split('-').map(Number);
  const daysInMonth = new Date(y, m, 0).getDate();
  const inMonth = today.slice(0, 7) === month;
  const dayOfMonth = inMonth ? Math.min(Number(today.slice(8, 10)), daysInMonth) : daysInMonth;
  const daysElapsed = dayOfMonth;
  const daysRemaining = Math.max(0, daysInMonth - dayOfMonth);

  let mtdSpent = 0;
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending || t.amount >= 0 || t.transferGroupId || t.isAdjustment) continue;
    if (t.date.slice(0, 7) !== month) continue;
    if (inMonth && t.date > today) continue;
    mtdSpent += -t.amount;
  }

  // Upcoming recurring expenses for the rest of this month (templates with a
  // known monthly amount whose day_of_month falls after today). Income is
  // excluded so the figure is comparable to mtdSpent.
  let recurringRest = 0;
  if (inMonth) {
    for (const rt of recurring) {
      if (rt.type !== 'expense') continue;
      if (rt.frequency !== 'monthly') continue;
      if (rt.amount == null) continue;
      if (rt.dayOfMonth <= dayOfMonth) continue;
      if (rt.dayOfMonth > daysInMonth) continue;
      recurringRest += Math.abs(rt.amount);
    }
  }

  // Scheduled items use a 3-letter month label; only count rows for this
  // month with a day still ahead.
  const monthLabel = MONTH_LABELS[m - 1];
  let scheduledRest = 0;
  if (inMonth) {
    for (const it of scheduledItems) {
      if (it.ledgerId !== ledgerId) continue;
      if (it.month !== monthLabel) continue;
      if (it.day <= dayOfMonth) continue;
      if (it.day > daysInMonth) continue;
      scheduledRest += Math.abs(it.amount);
    }
  }

  const dailyRunRate = daysElapsed > 0 ? mtdSpent / daysElapsed : 0;
  const unscheduledRest = inMonth ? r2(dailyRunRate * daysRemaining) : 0;
  const projected = r2(mtdSpent + unscheduledRest + recurringRest + scheduledRest);

  return {
    mtdSpent: r2(mtdSpent),
    unscheduledRest,
    recurringRest: r2(recurringRest),
    scheduledRest: r2(scheduledRest),
    projected,
    daysElapsed,
    daysRemaining,
    daysInMonth,
    dailyRunRate: r2(dailyRunRate),
  };
}

/** Income / expense totals per month (both positive). Mirrors MOCK.cashflow. */
export function monthlyCashflow(txns: Tx[], ledgerId: string, endMonth: string, n: number): { m: string; inc: number; exp: number }[] {
  const months = monthsBack(endMonth, n);
  const inc = new Map<string, number>(months.map((mo) => [mo, 0]));
  const exp = new Map<string, number>(months.map((mo) => [mo, 0]));
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending || t.transferGroupId || t.isAdjustment) continue;
    const mo = t.date.slice(0, 7);
    if (!inc.has(mo)) continue;
    if (t.amount > 0) inc.set(mo, (inc.get(mo) ?? 0) + t.amount);
    else exp.set(mo, (exp.get(mo) ?? 0) + -t.amount);
  }
  return months.map((mo) => ({ m: MONTH_LABELS[Number(mo.slice(5)) - 1], inc: r2(inc.get(mo) ?? 0), exp: r2(exp.get(mo) ?? 0) }));
}

/**
 * Top categories by absolute month-over-month spend delta. `a` = previous month,
 * `b` = current month, `d` = percent change (mirrors the old APR_VS_MAY shape).
 */
export function topCategoryDeltas(
  txns: Tx[],
  ledgerId: string,
  curMonth: string,
  categories: { id: string; name: string }[],
  count = 5,
): { name: string; a: number; b: number; d: number }[] {
  if (!curMonth) return [];
  const prev = prevMonth(curMonth);
  const cur = categorySpend(txns, ledgerId, curMonth);
  const prv = categorySpend(txns, ledgerId, prev);
  const nameById = new Map(categories.map((c) => [c.id, c.name]));
  const seen = new Set<string>([...Object.keys(cur), ...Object.keys(prv)]);
  return [...seen]
    .map((id) => {
      const a = r2(prv[id] ?? 0);
      const b = r2(cur[id] ?? 0);
      const d = a > 0 ? Math.round(((b - a) / a) * 100) : b > 0 ? 100 : 0;
      return { name: nameById.get(id) ?? id, a, b, d };
    })
    .filter((r) => r.a > 0 || r.b > 0)
    .sort((x, y) => Math.abs(y.b - y.a) - Math.abs(x.b - x.a))
    .slice(0, count);
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
