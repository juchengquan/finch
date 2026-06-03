// Client-side selectors over the store's projected state. These mirror the SQL
// read queries in lib/db/queries/* so the read screens can compute from the
// store (which mirrors the server DB) instead of a second in-browser query DB.

import type { Tx, ScheduledTemplate } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';
import type { ListOptions } from '@/lib/db/queries/transactions';
import type { Transfer } from '@/lib/db/queries/transfers';
import type { BudgetRow } from '@/lib/db/queries/budgets';
import type { Holding } from '@/lib/db/queries/holdings';

const ledgerOf = (t: Tx) => t.ledgerId ?? 'personal';

/** A transaction's kind, with a fallback for pre-hydration seed rows that
 *  predate the `kind` column (derived from the transfer link + amount sign). */
export const kindOf = (t: Tx): 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund' =>
  t.kind ?? (t.transferGroupId ? 'transfer' : t.amount > 0 ? 'income' : 'expense');

/** Kinds that count toward category spend: expenses plus refunds. A refund's
 *  amount is positive, so `-amount` nets it back against its category. */
const isSpend = (t: Tx): boolean => kindOf(t) === 'expense' || kindOf(t) === 'refund';

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
    if (t.pending || !isSpend(t)) continue;
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
    if (t.pending || !isSpend(t)) continue;
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
    if (t.pending || !isSpend(t)) continue;
    if (!by.has(t.date)) continue;
    by.set(t.date, (by.get(t.date) ?? 0) + -t.amount);
  }
  for (const row of out) row.value = r2(by.get(row.date) ?? 0);
  return out;
}

/** Re-express an amount in `currency` into the ledger base currency. Net-worth
 *  selectors take one so mixed-currency account balances sum in a single currency;
 *  callers build it from the live rate map (`useMoney().toBase`). */
export type ToBase = (amount: number, currency: string) => number;
const identityBase: ToBase = (amount) => amount;

/**
 * Net worth at the end of each of the last N months, oldest first. Computes the
 * opening total (current_total − Σ all txns) and accumulates forward, snapshotting
 * after every month. Uses string-prefix month comparison so it matches the
 * lexicographic YYYY-MM-DD date format used everywhere else.
 *
 * `toBase` re-expresses each account's native balance in the ledger base (default
 * identity — a no-op when every account is already in the ledger base).
 */
export function netWorthByMonth(
  txns: Tx[],
  accounts: AccountRow[],
  ledgerId: string,
  endMonth: string,
  n: number,
  toBase: ToBase = identityBase,
): { m: string; v: number }[] {
  if (!endMonth) return [];
  const months = monthsBack(endMonth, n);
  const total = accounts
    .filter((a) => a.ledgerId === ledgerId)
    .reduce((s, a) => s + toBase(a.balance, a.currency), 0);
  // Pending (unconfirmed) txns aren't in the balance total, so exclude them here too.
  const ledgerTxns = txns.filter((t) => ledgerOf(t) === ledgerId && !t.pending);
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
  /** Scheduled expense/reminder templates due later this month (matched by `dayOfMonth`). */
  scheduledRest: number;
  /** Total: mtdSpent + unscheduledRest + scheduledRest. */
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
 * and known upcoming costs (scheduled templates including reminders).
 *
 * `today` is YYYY-MM-DD; if it falls outside `month`, the forecast collapses
 * to whatever's already known (no projection, no upcoming).
 */
export function monthForecast(
  txns: Tx[],
  scheduled: ScheduledTemplate[],
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
    if (t.pending || !isSpend(t)) continue;
    if (t.date.slice(0, 7) !== month) continue;
    if (inMonth && t.date > today) continue;
    mtdSpent += -t.amount;
  }

  // Upcoming scheduled expenses + reminders for the rest of this month.
  // Count monthly templates/reminders with a known amount and a day_of_month
  // falling after today. Income and transfer types are excluded.
  let scheduledRest = 0;
  if (inMonth) {
    for (const rt of scheduled) {
      if (rt.type !== 'expense') continue;
      if (rt.frequency !== 'monthly') continue;
      if (rt.amount == null) continue;
      if (rt.dayOfMonth <= dayOfMonth) continue;
      if (rt.dayOfMonth > daysInMonth) continue;
      scheduledRest += Math.abs(rt.amount);
    }
  }

  const dailyRunRate = daysElapsed > 0 ? mtdSpent / daysElapsed : 0;
  const unscheduledRest = inMonth ? r2(dailyRunRate * daysRemaining) : 0;
  const projected = r2(mtdSpent + unscheduledRest + scheduledRest);

  return {
    mtdSpent: r2(mtdSpent),
    unscheduledRest,
    scheduledRest: r2(scheduledRest),
    projected,
    daysElapsed,
    daysRemaining,
    daysInMonth,
    dailyRunRate: r2(dailyRunRate),
  };
}

export interface IncomeFlow {
  /** Total confirmed income for the month (positive). */
  income: number;
  /** Top expense categories by spend, oldest=first (sorted desc). */
  categories: { id: string; name: string; spent: number; color: string }[];
  /** income − Σ categories' spent, floor 0. */
  saved: number;
}

const FALLBACK_CAT_COLOR = '#9ca3af';

/**
 * Aggregate income vs. confirmed expense categories for the month, ready for
 * a Sankey "income → categories" chart. Caller passes the category lookup
 * (id → { name, color }) so the result is render-ready.
 */
export function incomeCategoryFlow(
  txns: Tx[],
  categories: { id: string; name: string; color?: string | null }[],
  ledgerId: string,
  month: string,
  topN = 6,
): IncomeFlow {
  let income = 0;
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending || kindOf(t) !== 'income') continue;
    if (month && t.date.slice(0, 7) !== month) continue;
    income += t.amount;
  }
  const byCat = categorySpend(txns, ledgerId, month);
  const lookup = new Map(categories.map((c) => [c.id, { name: c.name, color: c.color ?? FALLBACK_CAT_COLOR }]));
  const ranked = Object.entries(byCat)
    .map(([id, spent]) => ({ id, name: lookup.get(id)?.name ?? id, color: lookup.get(id)?.color ?? FALLBACK_CAT_COLOR, spent }))
    .filter((c) => c.spent > 0)
    .sort((a, b) => b.spent - a.spent);
  const top = ranked.slice(0, topN);
  const restSpent = ranked.slice(topN).reduce((s, c) => s + c.spent, 0);
  if (restSpent > 0) top.push({ id: '__other__', name: 'Other', color: FALLBACK_CAT_COLOR, spent: restSpent });
  const spentTotal = ranked.reduce((s, c) => s + c.spent, 0);
  const saved = Math.max(0, r2(income - spentTotal));
  return { income: r2(income), categories: top.map((c) => ({ ...c, spent: r2(c.spent) })), saved };
}

/** Income / expense totals per month (both positive). Mirrors MOCK.cashflow. */
export function monthlyCashflow(txns: Tx[], ledgerId: string, endMonth: string, n: number): { m: string; inc: number; exp: number }[] {
  const months = monthsBack(endMonth, n);
  const inc = new Map<string, number>(months.map((mo) => [mo, 0]));
  const exp = new Map<string, number>(months.map((mo) => [mo, 0]));
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    const k = kindOf(t);
    if (t.pending || k === 'transfer' || k === 'adjustment') continue;
    const mo = t.date.slice(0, 7);
    if (!inc.has(mo)) continue;
    // Income by kind; everything else here (expense + refund) nets into expense
    // — a refund's positive amount reduces the month's expense, not income.
    if (k === 'income') inc.set(mo, (inc.get(mo) ?? 0) + t.amount);
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

/**
 * Unrealized FX gain/loss on one account, in the ledger base currency.
 *
 *   cost basis      = openingBalanceBase + Σ amount_base of confirmed txns
 *   current value   = toBase(currentBalance, accountCurrency)        [live rate]
 *   unrealized FX   = current value − cost basis
 *
 * `Tx.amount` IS the locked ledger-base figure (it mirrors DB `amount_base`),
 * so the cost basis sums those directly — no per-transaction reconversion. A
 * same-currency-as-base account always returns 0 (toBase is identity, base
 * never moves). Pending rows are excluded — they aren't in the live balance
 * either.
 */
export function unrealizedFx(
  account: AccountRow,
  txns: Tx[],
  toBase: ToBase,
): number {
  const currentValueBase = toBase(account.balance, account.currency);
  let costBasis = account.openingBalanceBase;
  for (const t of txns) {
    if (t.account !== account.id) continue;
    if (t.pending) continue;
    costBasis += t.amount;
  }
  return r2(currentValueBase - costBasis);
}

/** Holdings for one account (already filtered by ledger via the holdings table). */
export function holdingsForAccount(holdings: Holding[], accountId: string): Holding[] {
  return holdings.filter((h) => h.accountId === accountId);
}

/** Live market value of one position in the holding's own currency.
 *  Returns null when no last_price has been logged — the caller decides
 *  whether to fall back to cost basis or render "no quote". */
export function holdingValue(h: Holding): number | null {
  if (h.lastPrice == null) return null;
  return r2(h.shares * h.lastPrice);
}

/** Unrealized gain/loss on one position in the holding's own currency
 *  (value − costBasis). Null when there's no price to compute value. */
export function holdingGainLoss(h: Holding): number | null {
  const v = holdingValue(h);
  if (v == null) return null;
  return r2(v - h.costBasis);
}

/** Sum of holding values for `accountId`, expressed in the account's currency.
 *  Positions without a logged price fall back to their cost basis so the total
 *  reflects "money parked here", not "live valuation of what we know about". */
export function holdingsValueForAccount(holdings: Holding[], accountId: string): number {
  let total = 0;
  for (const h of holdings) {
    if (h.accountId !== accountId) continue;
    const v = holdingValue(h);
    total += v ?? h.costBasis;
  }
  return r2(total);
}

/** Total value of an investment account: cash (account.balance) + holdings
 *  value. Non-investment accounts return the cash balance unchanged. The
 *  returned figure is in the account's own currency. */
export function investmentAccountTotal(account: AccountRow, holdings: Holding[]): number {
  if (account.type !== 'investment') return account.balance;
  return r2(account.balance + holdingsValueForAccount(holdings, account.id));
}

const byDateAsc = (a: Tx, b: Tx) => {
  if (a.date !== b.date) return a.date < b.date ? -1 : 1;
  const at = a.time ?? '';
  const bt = b.time ?? '';
  return at < bt ? -1 : at > bt ? 1 : 0;
};

// Reconstruct the running-balance curve from a transaction set whose final value
// is `endValue`: opening = end − Σamounts, then accumulate per transaction.
function runningSeries(txns: Tx[], endValue: number, amountOf: (t: Tx) => number = (t) => t.amount): number[] {
  const rows = [...txns].sort(byDateAsc);
  const opening = endValue - rows.reduce((s, t) => s + amountOf(t), 0);
  const out = [opening];
  let bal = opening;
  for (const t of rows) {
    bal += amountOf(t);
    out.push(bal);
  }
  return out;
}

/** Balance-over-time series for one account (ends at its current balance).
 *  Pending (unconfirmed) txns are excluded so the curve matches the balance.
 *  The curve is in the ACCOUNT's currency — walk the native amount so it ends at
 *  the native `current_balance`, not the ledger-base `Tx.amount`. */
export function balanceSeries(txns: Tx[], accountId: string, currentBalance: number): number[] {
  return runningSeries(
    txns.filter((t) => t.account === accountId && !t.pending),
    currentBalance,
    (t) => t.nativeAmount ?? t.amount,
  );
}

/** Net-worth-over-time series for a ledger (ends at the current total). `toBase`
 *  re-expresses each account's native balance in the ledger base so mixed-currency
 *  accounts sum correctly; it defaults to identity (no-op when account == base). */
export function netWorthSeries(
  txns: Tx[],
  accounts: AccountRow[],
  ledgerId: string,
  toBase: ToBase = identityBase,
): number[] {
  const total = accounts
    .filter((a) => a.ledgerId === ledgerId)
    .reduce((s, a) => s + toBase(a.balance, a.currency), 0);
  return runningSeries(txns.filter((t) => (t.ledgerId ?? 'personal') === ledgerId && !t.pending), total);
}

/** Mirrors listTransfers(): reconstruct transfers by grouping on transferGroupId. */
export function selectTransfers(txns: Tx[], accounts: AccountRow[], ledgerId: string): Transfer[] {
  const ledgerAccounts = accounts.filter((a) => a.ledgerId === ledgerId);
  const nameById = new Map(ledgerAccounts.map((a) => [a.id, a.name]));
  const curById = new Map(ledgerAccounts.map((a) => [a.id, a.currency]));
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
    const time = rows.map((r) => r.time).find((t) => t != null) ?? null;
    const note = rows.map((r) => r.note).find((n) => n != null) ?? null;
    const fromId = out_?.account ?? null;
    const toId = in_?.account ?? null;
    // Amounts are native (each leg's own currency) so a cross-currency transfer
    // shows the real sent/received figures, not the ledger-base equivalents.
    out.push({
      id,
      date,
      time,
      amount: out_ ? Math.abs(out_.nativeAmount ?? out_.amount) : 0,
      toAmount: in_ ? Math.abs(in_.nativeAmount ?? in_.amount) : 0,
      fromCurrency: (fromId ? curById.get(fromId) : undefined) ?? out_?.currency ?? 'USD',
      toCurrency: (toId ? curById.get(toId) : undefined) ?? in_?.currency ?? 'USD',
      fromAccountId: fromId,
      toAccountId: toId,
      fromName: fromId == null ? null : nameById.get(fromId) ?? null,
      toName: toId == null ? null : nameById.get(toId) ?? null,
      note,
    });
  }
  return out.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
}

// ---------------------------------------------------------------------------
// Named budgets — cycle windows and progress (spent vs limit / earned vs target)
// ---------------------------------------------------------------------------

const round2 = (n: number) => Math.round(n * 100) / 100;
const pad2 = (n: number) => String(n).padStart(2, '0');
const toYmd = (d: Date) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const fromYmd = (s: string) => {
  const [y, m, d] = s.slice(0, 10).split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
};
const addDays = (d: Date, n: number) => {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
};
// Month add that clamps the day to the target month's length (Jan 31 +1mo → Feb 28).
const addMonths = (d: Date, n: number) => {
  const day = d.getDate();
  const t = new Date(d.getFullYear(), d.getMonth() + n, 1);
  const lastDay = new Date(t.getFullYear(), t.getMonth() + 1, 0).getDate();
  t.setDate(Math.min(day, lastDay));
  return t;
};
const advance = (d: Date, frequency: string): Date => {
  switch (frequency) {
    case 'daily': return addDays(d, 1);
    case 'weekly': return addDays(d, 7);
    case 'biweekly': return addDays(d, 14);
    case 'quarterly': return addMonths(d, 3);
    case 'yearly': return addMonths(d, 12);
    case 'monthly':
    default: return addMonths(d, 1);
  }
};

export interface CycleWindow {
  /** Inclusive first day of the active period (YYYY-MM-DD). */
  from: string;
  /** Inclusive last day of the active period (YYYY-MM-DD). */
  to: string;
}

/**
 * The active cycle window containing `today`, stepping from `startDate` by
 * `frequency`. Non-recurring budgets have a single window [startDate, endDate or
 * today]. Dates are compared as YYYY-MM-DD strings everywhere else, so the bounds
 * are returned that way too.
 */
export function cycleWindow(
  frequency: string,
  startDate: string,
  today: string,
  endDate: string | null = null,
  isRecurring = 1,
): CycleWindow {
  const start = fromYmd(startDate);
  const now = fromYmd(today);

  if (!isRecurring) {
    return { from: toYmd(start), to: endDate ? endDate.slice(0, 10) : (now < start ? toYmd(start) : today.slice(0, 10)) };
  }

  // Today before the first period → clamp to the first period.
  if (now < start) {
    return { from: toYmd(start), to: toYmd(addDays(advance(start, frequency), -1)) };
  }

  // Walk forward until the period end passes `now`. Bounded for safety.
  let s = start;
  let e = advance(s, frequency);
  for (let guard = 0; e <= now && guard < 5000; guard++) {
    s = e;
    e = advance(e, frequency);
  }
  return { from: toYmd(s), to: toYmd(addDays(e, -1)) };
}

export interface BudgetProgress extends CycleWindow {
  /** Limit (expense) or target (income), incl. expense carry-forward. */
  base: number;
  /** Spent (expense) or earned/saved (income) in the window. */
  used: number;
  /** base − used (can be negative when over). */
  remaining: number;
  pct: number;
  over: boolean;
}

// Whether/how much of a transaction counts for a category filter, honouring
// splits. Returns the signed base-currency amount that matches `categoryIds`
// (empty set = whole transaction matches).
function matchedAmount(t: Tx, categoryIds: string[]): number {
  if (categoryIds.length === 0) return t.amount;
  const set = new Set(categoryIds);
  if (t.splits && t.splits.length) {
    let sum = 0;
    for (const s of t.splits) if (s.categoryId && set.has(s.categoryId)) sum += s.amountBase;
    return sum;
  }
  return t.category != null && set.has(t.category) ? t.amount : 0;
}

/**
 * Progress for one named budget over its active cycle. Expense budgets sum
 * matching outflows; recurring income budgets sum matching inflows; one-shot
 * income/goal budgets use the manual `saved` accumulator (hybrid model).
 */
export function budgetProgress(budget: BudgetRow, txns: Tx[], today: string): BudgetProgress {
  const win = cycleWindow(budget.frequency, budget.startDate, today, budget.endDate, budget.isRecurring);
  const accountSet = budget.accountIds.length ? new Set(budget.accountIds) : null;

  let used = 0;
  const oneShotIncome = budget.type === 'income' && budget.isRecurring === 0;
  if (oneShotIncome) {
    used = budget.saved;
  } else {
    for (const t of txns) {
      if (ledgerOf(t) !== budget.ledgerId) continue;
      if (t.pending || kindOf(t) === 'transfer' || kindOf(t) === 'adjustment') continue;
      if (t.date < win.from || t.date > win.to) continue;
      if (accountSet && !accountSet.has(t.account)) continue;
      const amt = matchedAmount(t, budget.categoryIds);
      if (budget.type === 'expense') {
        if (amt < 0) used += -amt;
      } else if (amt > 0) {
        used += amt;
      }
    }
  }

  const base = round2(budget.amount + (budget.type === 'expense' ? budget.carryForward : 0));
  used = round2(used);
  const remaining = round2(base - used);
  const pct = base ? Math.round((used / base) * 100) : 0;
  const over = budget.type === 'expense' && used > base;
  return { ...win, base, used, remaining, pct, over };
}
