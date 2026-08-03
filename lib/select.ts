// Client-side selectors over the store's projected state. These mirror the SQL
// read queries in lib/db/queries/* so the read screens can compute from the
// store (which mirrors the server DB) instead of a second in-browser query DB.

import type { Tx, ScheduledTemplate } from '@/lib/store';
import type { AccountRow } from '@/lib/db/domain/accounts/types';
import type { ListOptions } from '@/lib/db/domain/transactions/types';
import type { Transfer } from '@/lib/db/domain/transfers/types';
import type { BudgetRow } from '@/lib/db/domain/budgets/types';
import type { Holding } from '@/lib/db/domain/holdings/types';
import type { AccountType } from '@/lib/account-types';
import { occurrencesUpTo } from '@/lib/recurrence';
import { expandDescendants } from '@/lib/db/domain/categories/queries';

const ledgerOf = (t: Tx) => t.ledgerId ?? 'personal';

/** Groups a row with the other payment legs of the same purchase. Falls back to
 *  the posting id when `entryId` is absent — a fixture written before the field
 *  existed — reproducing the pre-fix behaviour of counting each leg separately
 *  rather than collapsing every such row under one shared undefined key. */
export const purchaseKey = (t: Tx): string => t.entryId ?? t.id;

/** One row per purchase: the payment legs of a split-tender purchase summed into
 *  a single row carrying the true total. Mirrors iOS `Selectors.byPurchase`.
 *
 *  Use wherever a statistic or ranking needs what was actually spent — a mean, a
 *  variance, a z-score, a "biggest". For counting alone `purchaseKey` is enough.
 *
 *  `nativeAmount`/`currency` are dropped when the legs disagree: split tender is
 *  multi-currency and consumers read `nativeAmount ?? amount`, so summing raw
 *  natives across currencies would hand them a number that is not money in any
 *  unit — worse than the comparable base amount they fall back to.
 *
 *  Identity fields (`id`, `account`, `clearedAt`, `pending`) are the FIRST leg's;
 *  do not use this where a specific leg's account or reconcile mark matters. On a
 *  transfer the legs cancel to amount 0 — every caller filters by kind first. */
export function byPurchase(txns: Tx[]): Tx[] {
  const order: string[] = [];
  const acc = new Map<string, Tx>();
  for (const t of txns) {
    const key = purchaseKey(t);
    const seen = acc.get(key);
    if (!seen) { order.push(key); acc.set(key, { ...t }); continue; }
    seen.amount = r2(seen.amount + t.amount);
    if (seen.currency === t.currency && seen.nativeAmount != null && t.nativeAmount != null) {
      seen.nativeAmount = r2(seen.nativeAmount + t.nativeAmount);
    } else {
      seen.currency = undefined;
      seen.nativeAmount = undefined;
    }
  }
  return order.map((k) => acc.get(k)!).filter(Boolean);
}

/** A transaction's kind, with a fallback for pre-hydration seed rows that
 *  predate the `kind` column (derived from the transfer link + amount sign). */
export const kindOf = (t: Tx): 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund' =>
  t.kind ?? (t.transferGroupId ? 'transfer' : t.amount > 0 ? 'income' : 'expense');

/** Kinds that count toward category spend: expenses plus refunds. A refund's
 *  amount is positive, so `-amount` nets it back against its category. */
const isSpend = (t: Tx): boolean => kindOf(t) === 'expense' || kindOf(t) === 'refund';

/** Optional id→name lookups that widen `query` matching beyond the merchant
 *  text to what the feed row actually displays (category title, tag chips).
 *  Omitted maps fall back to merchant-only matching. */
export interface SearchNames {
  categories?: Record<string, string>;
  tags?: Record<string, string>;
}

/** Case-insensitive query match over what a feed row displays: the merchant
 *  text, the category title (incl. split categories), and tag names — the
 *  name lookups come from `SearchNames`. Shared by `selectTransactions` and
 *  the activity page's inline filter so the two can't drift. */
export function txMatchesQuery(t: Tx, query: string, names?: SearchNames): boolean {
  const q = query.toLowerCase();
  const catHit = (id: string | null | undefined) =>
    !!id && (names?.categories?.[id] ?? '').toLowerCase().includes(q);
  return (
    t.merchant.toLowerCase().includes(q) ||
    catHit(t.category) ||
    (t.splits ?? []).some((s) => catHit(s.categoryId)) ||
    (t.tags ?? []).some((id) => (names?.tags?.[id] ?? '').toLowerCase().includes(q))
  );
}

/** Mirrors listTransactions(): filter + sort an in-memory Tx list. */
export function selectTransactions(txns: Tx[], opts: ListOptions, names?: SearchNames): Tx[] {
  let out = txns.filter((t) => ledgerOf(t) === opts.ledgerId);
  if (opts.direction === 'in') out = out.filter((t) => t.amount > 0);
  if (opts.direction === 'out') out = out.filter((t) => t.amount < 0);
  if (opts.query) {
    const q = opts.query;
    out = out.filter((t) => txMatchesQuery(t, q, names));
  }
  if (opts.accountId) out = out.filter((t) => t.account === opts.accountId);
  if (opts.categoryId) out = out.filter((t) => t.category === opts.categoryId);
  if (opts.status) out = out.filter((t) => t.pending === (opts.status === 'pending'));
  // A bare 'yyyy-MM-dd' compares against the transaction's DATE, exactly as it
  // always has. A bound carrying a time compares MOMENTS instead — and stays
  // inclusive at both ends, because a filter range is what the user typed ("from
  // here to here"), not a cycle whose top belongs to the next window.
  if (opts.from) {
    out = opts.from.length > 10
      ? out.filter((t) => momentOf(t) >= opts.from!)
      : out.filter((t) => t.date >= opts.from!);
  }
  if (opts.to) {
    out = opts.to.length > 10
      ? out.filter((t) => momentOf(t) <= opts.to!)
      : out.filter((t) => t.date <= opts.to!);
  }
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
  // Parse as UTC (`Z`) and use UTC accessors so server (UTC) and client
  // (any local zone) agree on the bucket boundaries — without this, an
  // 84-day window rolls one day earlier on a UTC-8 client, and the
  // CalendarHeatmap's per-cell <title> dates differ between server and
  // client, tripping a React hydration mismatch.
  const end = new Date(`${endDate}T00:00:00Z`);
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setUTCDate(end.getUTCDate() - i);
    const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
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
  // F4 + isActive fix: honour both filters to match `accounts/queries/accounts.ts::netWorth`
  // (which filters is_active=1 AND include_in_net_worth=1) and the headline Net-worth
  // card on /accounts. Falsy = include (default), 0 = exclude.
  const total = accounts
    .filter((a) => a.ledgerId === ledgerId && (a.includeInNetWorth ?? 1) !== 0 && (a.isActive ?? true))
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

/** Net-worth-movement decomposition over a trailing window of months. Each
 *  bucket is in the ledger's base currency (via `toBase`).
 *
 *  - income:     sum of confirmed kind='income' account-leg amounts (positive)
 *  - expense:    Σ|amount| for kind='expense' minus Σamount for kind='refund'.
 *                Refunds NET against the period (refund amounts are already
 *                positive on the account leg, so taking |amount| would
 *                double-count).
 *  - adjustment: sum of confirmed kind='adjustment' account-leg amounts (signed)
 *  - fx:         the residual — `net - (income - expense + adjustment)`. By
 *                construction (every entry's postings sum to zero), anything
 *                that moves the headline net-worth and isn't one of the three
 *                kinds above is an FX residue leg (sys:fx-gain equity category,
 *                in practice only emitted on cross-currency transfers).
 *  - net:        the month's end-to-start netWorthSeries delta (i.e. what the
 *                headline trend chart shows).
 *
 *  Transfer Tx pairs sum to zero and contribute to none of the buckets above. */
export function netWorthExplained(
  txns: Tx[],
  accounts: AccountRow[],
  ledgerId: string,
  endMonth: string,
  n: number,
  toBase: ToBase = identityBase,
): { m: string; income: number; expense: number; adjustment: number; fx: number; net: number }[] {
  if (!endMonth) return [];
  const months = monthsBack(endMonth, n);
  const series = netWorthByMonth(txns, accounts, ledgerId, endMonth, n + 1, toBase);
  // netWorthByMonth returns one point per month INCLUDING the end month; we
  // asked for n+1 so we can compute n monthly deltas. The `m` field of each
  // row is a month label (e.g. "Jun") not a YYYY-MM key, so we re-derive the
  // extended window here and index by position.
  const extendedMonths = monthsBack(endMonth, n + 1);
  const deltas = new Map<string, number>();
  for (let i = 1; i < series.length && i < extendedMonths.length; i++) {
    deltas.set(extendedMonths[i], series[i].v - series[i - 1].v);
  }
  const ledgerTxns = txns.filter((t) => ledgerOf(t) === ledgerId && !t.pending);
  return months.map((m) => {
    const inMonth = ledgerTxns.filter((t) => t.date.startsWith(m));
    let income = 0;
    let expensePositive = 0;
    let refundPositive = 0;
    let adjustment = 0;
    for (const t of inMonth) {
      if (t.kind === 'income') income += t.amount;
      else if (t.kind === 'expense') expensePositive += Math.abs(t.amount);
      else if (t.kind === 'refund') refundPositive += t.amount; // refund.amount is positive on the account leg
      else if (t.kind === 'adjustment') adjustment += t.amount;
    }
    const expense = expensePositive - refundPositive; // refunds net against expense
    const net = deltas.get(m) ?? 0;
    const fx = round2(net - income + expense - adjustment);
    return { m, income: round2(income), expense: round2(expense), adjustment: round2(adjustment), fx, net: round2(net) };
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

/** A trimmed Tx shape for the Add screen's "Recent" chips — just enough to
 *  pre-fill the form on tap. */
export interface RecentExpense {
  merchant: string;
  /** Native amount (account currency), positive magnitude for the chip
   *  display; the caller re-signs as expense on submit. */
  amount: number;
  /** Account currency at the time the row was written. */
  currency: string;
  accountId: string;
  categoryId: string | null;
}

/**
 * Recent confirmed expenses for the active ledger, **deduplicated** by
 * (merchant + amount + account + category). Useful as a one-tap "redo" for
 * habitual purchases — the daily coffee, the lunch place, the parking
 * meter. Pending rows, refunds, transfers, adjustments, and income are all
 * excluded because they don't make sense as "expense to repeat".
 *
 * The dedupe key uses native amount + currency so two identical purchases
 * collapse into one chip; sort is by most-recent-first so a chip's "freshness"
 * matches the user's intuition. `limit` caps the result.
 */
export function recentExpenses(txns: Tx[], ledgerId: string, limit = 5): RecentExpense[] {
  const seen = new Set<string>();
  const out: { date: string; time: string; row: RecentExpense }[] = [];
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending) continue;
    if (kindOf(t) !== 'expense') continue;
    // A split purchase is EXCLUDED, not collapsed: this feeds the Watch quick-add
    // templates, which can only write a single-card transaction, so a two-card
    // purchase cannot be repeated in one tap. Offering both legs ate two of three
    // slots; offering the total would silently book it all to one card.
    if ((t.accountLegCount ?? 1) > 1) continue;
    const native = t.nativeAmount ?? t.amount;
    if (native >= 0) continue; // sanity: an expense must be negative
    const currency = t.currency ?? 'USD';
    const amountMag = Math.abs(native);
    const key = `${t.merchant}|${amountMag.toFixed(2)}|${t.account}|${t.category ?? ''}|${currency}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      date: t.date,
      time: t.time ?? '',
      row: {
        merchant: t.merchant,
        amount: amountMag,
        currency,
        accountId: t.account,
        categoryId: t.category,
      },
    });
  }
  // Most-recent first; the iteration above respects DB insert order, but the
  // store can be in any order after edits, so sort defensively.
  out.sort((a, b) => {
    if (a.date !== b.date) return a.date < b.date ? 1 : -1;
    return a.time < b.time ? 1 : a.time > b.time ? -1 : 0;
  });
  return out.slice(0, limit).map((r) => r.row);
}

/** A confirmed transaction that looks like a likely duplicate of a draft. */
export interface DuplicateMatch {
  id: string;
  merchant: string;
  date: string;
}

/** Days on either side of the draft date that still count as "around the same
 *  time" for the soft duplicate check. */
const DUPLICATE_WINDOW_DAYS = 3;

/**
 * Soft duplicate detector for the Add form (#6). Returns an existing transaction
 * that closely matches the draft — same account, same merchant (case-insensitive),
 * same amount magnitude, within ±DUPLICATE_WINDOW_DAYS of the draft date — or
 * null when nothing's close. This is a *nudge*, never a block: it deliberately
 * ignores time-of-day and category so a near-miss the hard UNIQUE index (#5)
 * would allow still gets flagged here. Pending and non-expense/income rows are
 * skipped, as is the draft's own id (for the edit case).
 */
export function findDuplicate(
  txns: Tx[],
  ledgerId: string,
  draft: { merchant: string; amount: number; accountId: string; date: string; excludeId?: string },
): DuplicateMatch | null {
  const merchant = draft.merchant.trim().toLowerCase();
  if (!merchant) return null;
  const mag = Math.abs(draft.amount);
  if (!(mag > 0)) return null;
  const day = draft.date.slice(0, 10);

  // Compare against the PURCHASE, not one of its payments. A purchase paid from
  // several accounts has no single account and no single amount, so matching
  // row-by-row never fired for one: re-adding a 100 shop that already existed as
  // 60 + 40 found neither a 100 row nor a card that "the" purchase was on.
  //
  // byPurchase is not enough here, because it keeps only the FIRST leg's account
  // while the draft may name any of the paying cards — so group locally, keeping
  // the set of accounts alongside the total.
  const order: string[] = [];
  const totals = new Map<string, number>();
  const accounts = new Map<string, Set<string>>();
  const first = new Map<string, Tx>();
  // excludeId arrives as a POSTING id: resolve it to the purchase it belongs to,
  // or editing one leg of a split makes the sheet warn about itself.
  const excludedKey = draft.excludeId
    ? purchaseKey(txns.find((t) => t.id === draft.excludeId) ?? ({ id: draft.excludeId } as Tx))
    : undefined;

  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending) continue;
    const k = kindOf(t);
    if (k !== 'expense' && k !== 'income') continue;
    if (t.merchant.trim().toLowerCase() !== merchant) continue;
    const key = purchaseKey(t);
    if (key === excludedKey) continue;
    if (!totals.has(key)) { order.push(key); first.set(key, t); }
    // Native amounts across legs in different currencies are not a quantity in
    // any currency, so fall back to base when they disagree — byPurchase's rule.
    const sameCcy = first.get(key)!.currency === t.currency;
    totals.set(key, (totals.get(key) ?? 0) + (sameCcy ? (t.nativeAmount ?? t.amount) : t.amount));
    if (!accounts.has(key)) accounts.set(key, new Set());
    accounts.get(key)!.add(t.account);
  }

  for (const key of order) {
    const t = first.get(key);
    if (!t) continue;
    // Any paying card counts: the draft names the card being added to, which may
    // be either side of an existing split.
    if (!accounts.get(key)?.has(draft.accountId)) continue;
    if (Math.abs(Math.abs(totals.get(key) ?? 0) - mag) > 0.005) continue;
    if (Math.abs(dayDiff(t.date.slice(0, 10), day)) > DUPLICATE_WINDOW_DAYS) continue;
    return { id: t.id, merchant: t.merchant, date: t.date };
  }
  return null;
}

/** Whole-day difference a−b between two YYYY-MM-DD dates (UTC). */
function dayDiff(a: string, b: string): number {
  return Math.round((Date.parse(`${a}T00:00:00Z`) - Date.parse(`${b}T00:00:00Z`)) / 86400000);
}

// ---------------------------------------------------------------------------
// Weekly digest — Sunday-night recap of the most recently completed Mon-Sun
// window. Surfaces totals, top categories, biggest single expense, and how it
// compares to the prior week + a trailing 12-week average. Pure aggregation,
// one pass over the projected transactions.
// ---------------------------------------------------------------------------

/** Add `n` days (can be negative) to a YYYY-MM-DD date, UTC. */
function addDaysIso(iso: string, n: number): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + n);
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}

/** YYYY-MM-DD for the Monday of the ISO week containing `date` (UTC). */
function isoWeekMonday(date: string): string {
  const [y, m, d] = date.slice(0, 10).split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  // JS getUTCDay: Sun=0..Sat=6. Shift so Mon=0..Sun=6 via (day+6)%7.
  const shift = (dt.getUTCDay() + 6) % 7;
  dt.setUTCDate(dt.getUTCDate() - shift);
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}

export interface WeeklyDigest {
  /** Mon-Sun window the digest reports on (YYYY-MM-DD inclusive). */
  weekStart: string;
  weekEnd: string;
  /** Total confirmed expense magnitude in ledger base, this window. */
  spent: number;
  /** Total confirmed income in ledger base, this window. */
  income: number;
  /** income - spent (positive = saved, negative = burned cash). */
  net: number;
  /** Previous Mon-Sun window's spend; null when there's no prior confirmed data. */
  prevSpent: number | null;
  /** % change vs prevSpent (e.g. 0.18 = +18%); null when prevSpent is null/0. */
  vsPrevPct: number | null;
  /** Average weekly spend over the 4-12 weeks PRIOR to this one. */
  avgSpent: number;
  /** Weeks of history used to compute avgSpent (0..12). */
  avgWeeks: number;
  /** % change vs avgSpent; null when avg is 0 or we have < 4 weeks of history. */
  vsAvgPct: number | null;
  /** Top spending categories this week, descending. Capped at 5. */
  topCategories: { categoryId: string; amount: number }[];
  /** Largest single expense in the week (positive magnitude). Refunds excluded. */
  biggestExpense: { txId: string; merchant: string; amount: number; date: string } | null;
  /** Confirmed expense transaction count in the window. */
  txCount: number;
}

/**
 * Recap of the most recently completed Mon-Sun week before `anchor` (typically
 * today). Splits respect the same category attribution as `categorySpend`.
 *
 * Returns null when the ledger has no confirmed history at all — nothing to
 * recap. The vs-prev / vs-avg deltas are independently null when their
 * windows are empty or undersized (vs-avg requires ≥ 4 weeks of history to
 * avoid the "vs typical $50" exaggeration on a fresh ledger).
 */
export function weeklyDigest(txns: Tx[], ledgerId: string, anchor: string): WeeklyDigest | null {
  if (!anchor) return null;
  const thisMon = isoWeekMonday(anchor);
  const weekStart = addDaysIso(thisMon, -7);
  const weekEnd = addDaysIso(thisMon, -1);
  const prevStart = addDaysIso(weekStart, -7);
  const prevEnd = addDaysIso(weekStart, -1);
  const avgStart = addDaysIso(weekStart, -7 * 12);
  const avgEnd = addDaysIso(weekStart, -1);

  let spent = 0;
  let income = 0;
  let prevSpent = 0;
  let avgSum = 0;
  let txCount = 0;
  let prevHasAny = false;
  let everHadConfirmed = false;
  const byCat: Record<string, number> = {};
  const weeksWithData = new Set<string>();
  let biggest: { txId: string; merchant: string; amount: number; date: string } | null = null;

  // One row per PURCHASE. Fixes `txCount` and `biggest` together: a purchase
  // paid on two cards was counted twice and each leg ranked on its own, so a
  // $200 purchase could lose "biggest" to a $150 one. Sums are unaffected — the
  // legs add back to the total.
  for (const t of byPurchase(txns)) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending) continue;
    everHadConfirmed = true;
    const k = kindOf(t);
    const d = t.date;
    const inWeek = d >= weekStart && d <= weekEnd;
    const inPrev = d >= prevStart && d <= prevEnd;
    const inAvg = d >= avgStart && d <= avgEnd;
    if (inPrev) prevHasAny = true;

    if (isSpend(t)) {
      const mag = -t.amount;
      if (inWeek) {
        spent += mag;
        txCount++;
        if (t.splits && t.splits.length) {
          for (const s of t.splits) {
            if (!s.categoryId) continue;
            byCat[s.categoryId] = (byCat[s.categoryId] ?? 0) + -s.amountBase;
          }
        } else if (t.category) {
          byCat[t.category] = (byCat[t.category] ?? 0) + mag;
        }
        // Refunds offset category totals but don't make sense as a "biggest hit" headline.
        if (k === 'expense' && (!biggest || mag > biggest.amount)) {
          biggest = { txId: t.id, merchant: t.merchant, amount: mag, date: d };
        }
      }
      if (inPrev) prevSpent += mag;
      if (inAvg) {
        avgSum += mag;
        weeksWithData.add(isoWeekMonday(d));
      }
    } else if (k === 'income' && inWeek) {
      income += t.amount;
    }
  }

  if (!everHadConfirmed) return null;

  const prev: number | null = prevHasAny ? r2(prevSpent) : null;
  const avgWeeks = weeksWithData.size;
  const avg = avgWeeks > 0 ? r2(avgSum / avgWeeks) : 0;
  const topCategories = Object.entries(byCat)
    .map(([categoryId, amount]) => ({ categoryId, amount: r2(amount) }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 5);

  return {
    weekStart,
    weekEnd,
    spent: r2(spent),
    income: r2(income),
    net: r2(income - spent),
    prevSpent: prev,
    vsPrevPct: prev != null && prev > 0 ? r2((spent - prev) / prev) : null,
    avgSpent: avg,
    avgWeeks,
    vsAvgPct: avgWeeks >= 4 && avg > 0 ? r2((spent - avg) / avg) : null,
    topCategories,
    biggestExpense: biggest,
    txCount,
  };
}

// ---------------------------------------------------------------------------
// What-if baseline — average monthly spend per category over the trailing
// complete months, plus average income/spend totals. The Insights what-if
// card runs interactive hypotheticals ("cut dining 30%") against this
// baseline; the slider math itself is trivial and lives in the component.
// ---------------------------------------------------------------------------

export interface WhatIfBaseline {
  /** Months (YYYY-MM) the averages cover, oldest first. */
  months: string[];
  /** Top categories by average monthly spend, descending (positive amounts). */
  categories: { categoryId: string; avgMonthly: number }[];
  /** Average monthly confirmed income over the window. */
  avgIncome: number;
  /** Average total monthly spend over the window (all categories, not just top-N). */
  avgSpend: number;
}

/**
 * Baseline for the what-if sliders: category spend averaged over up to
 * `windowMonths` complete months before `anchorMonth` (the current, likely
 * partial, month). Months with no confirmed spend are dropped from the
 * average so a fresh ledger isn't diluted toward zero; when no complete
 * month has data the anchor month itself is the (1-month) window.
 * Returns null when there's no spend anywhere to build a baseline from.
 */
export function whatIfBaseline(
  txns: Tx[],
  ledgerId: string,
  anchorMonth: string,
  opts?: { windowMonths?: number; topN?: number },
): WhatIfBaseline | null {
  if (!anchorMonth) return null;
  const windowMonths = opts?.windowMonths ?? 3;
  const topN = opts?.topN ?? 5;

  const monthSpend = (month: string) => categorySpend(txns, ledgerId, month);
  const hasSpend = (by: Record<string, number>) => Object.values(by).some((v) => v > 0);

  // Trailing complete months with data; fall back to the anchor month.
  const candidates = monthsBack(prevMonth(anchorMonth), windowMonths);
  let window = candidates
    .map((m) => ({ m, by: monthSpend(m) }))
    .filter(({ by }) => hasSpend(by));
  if (window.length === 0) {
    const by = monthSpend(anchorMonth);
    if (!hasSpend(by)) return null;
    window = [{ m: anchorMonth, by }];
  }

  const n = window.length;
  const totals: Record<string, number> = {};
  for (const { by } of window) {
    for (const [cat, v] of Object.entries(by)) totals[cat] = (totals[cat] ?? 0) + v;
  }
  const categories = Object.entries(totals)
    .map(([categoryId, sum]) => ({ categoryId, avgMonthly: r2(sum / n) }))
    .filter((c) => c.avgMonthly > 0)
    .sort((a, b) => b.avgMonthly - a.avgMonthly)
    .slice(0, topN);
  if (categories.length === 0) return null;

  const monthSet = new Set(window.map(({ m }) => m));
  let incomeSum = 0;
  let spendSum = 0;
  for (const t of txns) {
    if (ledgerOf(t) !== ledgerId || t.pending) continue;
    if (!monthSet.has(t.date.slice(0, 7))) continue;
    const k = kindOf(t);
    if (k === 'income') incomeSum += t.amount;
    else if (isSpend(t)) spendSum += -t.amount;
  }

  return {
    months: window.map(({ m }) => m),
    categories,
    avgIncome: r2(incomeSum / n),
    avgSpend: r2(spendSum / n),
  };
}

// ---------------------------------------------------------------------------
// Anomaly detection — per-merchant z-score over confirmed expense magnitudes.
// Catches both fraud ("this is 4× my usual coffee") and "wait, that was
// expensive". Pure heuristic, no model.
// ---------------------------------------------------------------------------

export interface MerchantStats {
  /** Number of past confirmed expense samples for the merchant. */
  count: number;
  /** Mean of |amount| in account currency (we don't reconvert FX — the
   *  z-score is per-merchant and per-account-currency, so the unit cancels). */
  mean: number;
  /** Population standard deviation. Zero when count < 2. */
  std: number;
}

export interface AnomalyScore {
  /** Standard score against the merchant's past mean (always >= 0). */
  zScore: number;
  /** Mean spent at this merchant historically (account currency). */
  mean: number;
  /** Number of past samples used. */
  count: number;
  /** True when both `zScore >= threshold` and `count >= minCount`. */
  isAnomaly: boolean;
}

/** Bucket key for grouping past transactions by merchant identity. Mirrors
 *  the suggestCategory matching rules: the counterparty FK wins when set,
 *  otherwise a case-folded description match. */
function merchantKey(t: Tx): string | null {
  if (t.counterpartyId) return `cp:${t.counterpartyId}`;
  const name = t.merchant.trim().toLowerCase();
  return name ? `m:${name}` : null;
}

/**
 * Aggregate the merchant-level mean + population std over confirmed expenses
 * in `ledgerId`. Excludes pending, refunds, transfers, income, adjustments —
 * only "spent at this merchant" amounts make sense to compare. Returns a
 * lookup keyed by merchantKey for O(1) per-row anomaly scoring.
 *
 * One pass over the transaction list; downstream anomaly checks are
 * arithmetic. Caller is expected to call this once and reuse the map across
 * a list render (memoize with `useMemo`).
 */
export function merchantStats(txns: Tx[], ledgerId: string): Map<string, MerchantStats> {
  const sums = new Map<string, { n: number; sum: number; sqSum: number }>();
  // One row per PURCHASE. Wrong twice over otherwise: the count is inflated AND
  // each leg's magnitude is a fraction of what was spent, so the mean and
  // deviation are distorted rather than merely rescaled.
  for (const t of byPurchase(txns)) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending) continue;
    if (kindOf(t) !== 'expense') continue;
    const key = merchantKey(t);
    if (!key) continue;
    const mag = Math.abs(t.nativeAmount ?? t.amount);
    const bucket = sums.get(key) ?? { n: 0, sum: 0, sqSum: 0 };
    bucket.n += 1;
    bucket.sum += mag;
    bucket.sqSum += mag * mag;
    sums.set(key, bucket);
  }
  const out = new Map<string, MerchantStats>();
  for (const [key, b] of sums) {
    const mean = b.sum / b.n;
    // Population std (we have the full history at this merchant, not a sample).
    // n=1 gives variance=0 and a degenerate std — anomaly check guards on count.
    const variance = b.n > 0 ? b.sqSum / b.n - mean * mean : 0;
    const std = Math.sqrt(Math.max(0, variance));
    out.set(key, { count: b.n, mean: r2(mean), std: r2(std) });
  }
  return out;
}

/**
 * Score one transaction against its merchant's history. Returns null when
 * there's no meaningful comparison (no history yet, or only 1 past sample
 * which makes std undefined). Pass `stats` from `merchantStats` so the
 * aggregation runs once per list render, not once per row.
 *
 * **Important:** stats include the transaction itself when it's in the same
 * txns array — that's fine for new history-building but skews the per-row
 * check toward "no anomaly" (the row is in its own mean). Either exclude
 * `tx` from the txns array passed to `merchantStats`, or accept the slight
 * smoothing — for lists of 20+ rows per merchant the bias is negligible.
 *
 * Defaults: `minCount = 3` (need at least 3 past samples to call a trend),
 * `threshold = 2.5` (~99% confidence under normal, errs toward quiet).
 */
export function anomalyScore(
  tx: Tx,
  stats: Map<string, MerchantStats>,
  opts: { minCount?: number; threshold?: number } = {},
): AnomalyScore | null {
  if (kindOf(tx) !== 'expense' || tx.pending) return null;
  const key = merchantKey(tx);
  if (!key) return null;
  const s = stats.get(key);
  if (!s || s.count < 2 || s.std === 0) return null;
  const mag = Math.abs(tx.nativeAmount ?? tx.amount);
  const z = Math.abs(mag - s.mean) / s.std;
  const minCount = opts.minCount ?? 3;
  const threshold = opts.threshold ?? 2.5;
  return {
    zScore: r2(z),
    mean: s.mean,
    count: s.count,
    isAnomaly: z >= threshold && s.count >= minCount,
  };
}

export interface CategorySuggestion {
  /** Highest-frequency category id for the matched history. */
  categoryId: string;
  /** Number of past transactions backing this suggestion. */
  count: number;
  /** Share of matched history that picked this category (0..1). */
  confidence: number;
}

const NORMALIZE = (s: string) => s.trim().toLowerCase();

/**
 * Suggest a category for a new expense based on past confirmed expenses for
 * the same merchant. Two matching strategies, tried in order:
 *
 *   1. Counterparty FK match — if `counterpartyId` is set, look for past rows
 *      with the same `counterpartyId`. Highest signal: that's a merchant the
 *      user has explicitly named.
 *
 *   2. Case-insensitive description match — fall back to rows whose `merchant`
 *      equals (case-folded) `description`. Covers free-text entries that
 *      didn't get auto-resolved to a counterparty.
 *
 * The matched set is filtered to **confirmed expenses in the same ledger**:
 *   - pending rows aren't part of the user's stable history
 *   - refunds, transfers, adjustments, income don't categorize the same way
 *   - cross-ledger matches would leak Personal categorizations into Family
 *
 * Splits override the parent category — when a past row was split, each
 * split's category contributes (matches existing `categorySpend` semantics).
 *
 * Returns the dominant category + confidence + match count. Returns `null`
 * when there's no useful signal:
 *   - empty description AND no counterparty
 *   - zero past matches
 *   - top category's confidence is below `MIN_CONFIDENCE` (default 0.5) and
 *     the match count is too small (< MIN_COUNT) — surfacing a coin flip is
 *     more annoying than helpful
 *
 * Pure function over the store's projected transactions; no DB query.
 */
export function suggestCategory(
  txns: Tx[],
  ledgerId: string,
  description: string,
  counterpartyId?: string | null,
  opts: { minCount?: number; minConfidence?: number } = {},
): CategorySuggestion | null {
  const minCount = opts.minCount ?? 1;
  const minConfidence = opts.minConfidence ?? 0.5;
  const term = NORMALIZE(description);
  if (!term && !counterpartyId) return null;

  const counts = new Map<string, number>();
  let total = 0;
  // One row per PURCHASE, so a habitually-split merchant does not get double
  // weight in the vote. The per-split loop below is unchanged.
  for (const t of byPurchase(txns)) {
    if (ledgerOf(t) !== ledgerId) continue;
    if (t.pending) continue;
    if (kindOf(t) !== 'expense') continue;
    const matches = counterpartyId
      ? t.counterpartyId === counterpartyId
      : NORMALIZE(t.merchant) === term;
    if (!matches) continue;
    if (t.splits && t.splits.length) {
      for (const s of t.splits) {
        if (!s.categoryId) continue;
        counts.set(s.categoryId, (counts.get(s.categoryId) ?? 0) + 1);
        total++;
      }
    } else if (t.category) {
      counts.set(t.category, (counts.get(t.category) ?? 0) + 1);
      total++;
    }
  }
  if (total === 0) return null;
  let topId = '';
  let topCount = 0;
  for (const [id, n] of counts) {
    if (n > topCount) {
      topId = id;
      topCount = n;
    }
  }
  if (!topId) return null;
  const confidence = topCount / total;
  // Quiet down ambiguous results: a 1-of-2 coin flip surfaces as a chip with
  // 50% confidence — more noise than signal. Demand either confidence over
  // the threshold or enough samples to call the trend stable.
  if (confidence < minConfidence && topCount < minCount) return null;
  return { categoryId: topId, count: topCount, confidence };
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
    // Guard the ledger too — account ids are unique today, but the function
    // takes the whole store transaction list and shouldn't quietly rely on
    // that invariant. A future shared id can't drag in another ledger's rows.
    if (ledgerOf(t) !== account.ledgerId) continue;
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

export interface ForecastEvent {
  /** YYYY-MM-DD the event hits the account. */
  date: string;
  /** Signed amount in the account's currency (positive = inflow). */
  amount: number;
  /** Human-readable label for the marker — the template's description or name. */
  description: string;
  /** Source template id, for navigating to /scheduled or filtering. */
  templateId: string;
}

export interface AccountForecast {
  today: string;
  horizonDays: number;
  /** Account currency at the time of the forecast — for display. */
  currency: string;
  /** account.balance at `today`, before any forecast events apply. */
  startingBalance: number;
  /** Projected balance at the end of the horizon (= startingBalance + Σ events). */
  endingBalance: number;
  /** Lowest projected balance and the date it hits. When the trough equals
   *  startingBalance the account never dips below where it is now. */
  trough: { date: string; balance: number };
  events: ForecastEvent[];
  /** Daily projected balance for each day in [today, today + horizonDays],
   *  oldest first. Length = horizonDays + 1. Use for the sparkline. */
  series: { date: string; balance: number }[];
}

/**
 * Project an account's balance forward over the next `horizonDays`, combining
 * the current `account.balance` with every scheduled template that touches
 * this account (income, expense, or transfer leg).
 *
 * Per template:
 *   - **income**  → +amount on every future occurrence, if the template's
 *     `accountId` equals this account
 *   - **expense** → −amount on every future occurrence, if the template's
 *     `accountId` equals this account
 *   - **transfer** → +amount when this account is the `accountId` (the to-leg),
 *     −amount when this account is the `fromAccountId` (the from-leg). Cross-
 *     currency transfers are simplified to a same-currency move at the
 *     template's nominal amount — the real-time FX conversion only happens at
 *     post time, so a precise forecast would need a rate lookup we don't
 *     plumb here. Same-currency transfers are exact.
 *
 * Templates without an amount (variable) are skipped. Templates with
 * `installment_total` cap is respected. Past occurrences (already posted as
 * transactions) are NOT subtracted — `account.balance` is already a function
 * of those, so we'd double-count.
 *
 * Pure function over inputs; no DB query, no side effects.
 */
export function accountForecast(
  account: AccountRow,
  scheduled: ScheduledTemplate[],
  today: string,
  horizonDays: number,
): AccountForecast {
  const start = account.balance;
  const end = addDaysIso(today, horizonDays);

  // Collect every future occurrence that touches this account, sorted by date.
  const events: ForecastEvent[] = [];
  for (const t of scheduled) {
    if (t.amount == null) continue; // variable amount — manual entry only
    const isToHere = t.accountId === account.id;
    const isFromHere = t.type === 'transfer' && t.fromAccountId === account.id;
    if (!isToHere && !isFromHere) continue;

    // Sign of the cash flow on THIS account.
    let sign = 0;
    if (t.type === 'income' && isToHere) sign = 1;
    else if (t.type === 'expense' && isToHere) sign = -1;
    else if (t.type === 'transfer' && isToHere) sign = 1;
    else if (t.type === 'transfer' && isFromHere) sign = -1;
    if (sign === 0) continue;

    // occurrencesUpTo returns dates from the template's startDate; trim to
    // the forecast window's open-end (strictly after today, through end).
    const all = occurrencesUpTo(t, end);
    const future = all.filter((d) => d > today);
    if (!future.length) continue;

    // Respect installmentTotal: count CONFIRMED occurrences already booked
    // (mirrors the cap math in generateDueScheduled — installmentPaid is the
    // derived figure from confirmed transactions; future events can't exceed
    // total − paid).
    let cap = future.length;
    if (t.installmentTotal != null) {
      const remaining = Math.max(0, t.installmentTotal - (t.installmentPaid ?? 0));
      cap = Math.min(cap, remaining);
    }
    if (t.maxExecutions != null) {
      // We don't know how many have run for max_executions (no derived count),
      // so we can only conservatively cap at maxExecutions itself.
      cap = Math.min(cap, t.maxExecutions);
    }
    for (let i = 0; i < cap; i++) {
      events.push({
        date: future[i],
        amount: sign * Math.abs(Number(t.amount)),
        description: t.description ?? t.name ?? '',
        templateId: t.id,
      });
    }
  }
  events.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));

  // Walk forward day-by-day, accumulating events on their date.
  const eventsByDate = new Map<string, number>();
  for (const e of events) {
    eventsByDate.set(e.date, (eventsByDate.get(e.date) ?? 0) + e.amount);
  }
  const series: { date: string; balance: number }[] = [];
  let balance = start;
  let troughDate = today;
  let troughBalance = start;
  for (let i = 0; i <= horizonDays; i++) {
    const date = addDaysIso(today, i);
    const delta = eventsByDate.get(date) ?? 0;
    balance = r2(balance + delta);
    series.push({ date, balance });
    if (balance < troughBalance) {
      troughBalance = balance;
      troughDate = date;
    }
  }

  return {
    today,
    horizonDays,
    currency: account.currency,
    startingBalance: r2(start),
    endingBalance: r2(balance),
    trough: { date: troughDate, balance: r2(troughBalance) },
    events,
    series,
  };
}

/**
 * "templateId|occurrenceDate" → isPending, for every posted occurrence (txns
 * whose sourceTemplateId is set). true => pending; false => done. An absent
 * key means only **not posted** — callers must compare the date against
 * today to tell `upcoming` (still ahead) from `missed` (past, and nobody
 * posted it). Mirrors FinchCore's `Selectors.scheduledPostedMap`
 * (ios/FinchCore/Sources/FinchCore/Selectors/Forecast.swift) — keep the two
 * in lockstep.
 */
export function scheduledPostedMap(txns: Tx[]): Map<string, boolean> {
  const out = new Map<string, boolean>();
  // Key on the occurrence the entry FULFILS, not the day it was recorded —
  // they differ when the user posts a missed item on a later date. Undefined
  // falls back to `date`, which is the pre-2026-07-22 behaviour, so
  // historical generateDue postings still resolve with no backfill.
  for (const t of txns) {
    if (t.sourceTemplateId) out.set(`${t.sourceTemplateId}|${t.occurrenceDate ?? t.date}`, !!t.pending);
  }
  return out;
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
  // F4 + isActive fix: honour both filters to match `accounts/queries/accounts.ts::netWorth`
  // (which filters is_active=1 AND include_in_net_worth=1) and the headline Net-worth
  // card on /accounts. Falsy = include (default), 0 = exclude.
  const total = accounts
    .filter((a) => a.ledgerId === ledgerId && (a.includeInNetWorth ?? 1) !== 0 && (a.isActive ?? true))
    .reduce((s, a) => s + toBase(a.balance, a.currency), 0);
  return runningSeries(txns.filter((t) => (t.ledgerId ?? 'personal') === ledgerId && !t.pending), total);
}

/** Net-worth breakdown by `account.type` (cash / savings / investment /
 *  credit_card / fx / virtual). Honours the same `includeInNetWorth` and
 *  `isActive` predicates as `netWorthByMonth` so the headline Insights
 *  chart and this breakdown agree. Returns the 6 canonical types in a
 *  stable order, even when zero. */
export function netWorthByAccountType(
  accounts: AccountRow[],
  ledgerId: string,
  toBase: ToBase = identityBase,
): { type: AccountType; balance: number }[] {
  const byType = new Map<AccountType, number>();
  for (const a of accounts) {
    if (a.ledgerId !== ledgerId) continue;
    if ((a.includeInNetWorth ?? 1) === 0) continue;
    if (!(a.isActive ?? true)) continue;
    byType.set(a.type as AccountType, (byType.get(a.type as AccountType) ?? 0) + toBase(a.balance, a.currency));
  }
  const order: AccountType[] = ['cash', 'savings', 'investment', 'credit_card', 'fx', 'virtual'];
  return order.map((type) => ({ type, balance: round2(byType.get(type) ?? 0) }));
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
  /** Inclusive start time on `from` (HH:mm). Absent = midnight. */
  fromTime?: string;
  /** EXCLUSIVE end time on `to` (HH:mm). Absent = the whole of `to` counts. */
  toTime?: string;
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
  startTime: string | null = null,
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
  // '00:00' IS the untimed behaviour — a cycle running midnight-to-midnight.
  // Treating it as timed would take the branch below and change what `to` means for
  // every budget saved without touching the time, which is most of them. Normalised
  // here rather than at the write path so no route into the database can bypass it.
  if (!startTime || startTime === '00:00') {
    for (let guard = 0; e <= now && guard < 5000; guard++) {
      s = e;
      e = advance(e, frequency);
    }
    return { from: toYmd(s), to: toYmd(addDays(e, -1)) };
  }
  // Timed: the turnover is a moment inside the day, so compare moments. A bare
  // `today` reads as midnight, which puts a same-day "now" BEFORE the turnover —
  // correct, since the cycle has not rolled yet.
  const nowStamp = today.length > 10 ? today : `${today} 00:00`;
  for (let guard = 0; `${toYmd(e)} ${startTime}` <= nowStamp && guard < 5000; guard++) {
    s = e;
    e = advance(e, frequency);
  }
  // `to` is the day the cycle STOPS on — the day the next one starts — and
  // `toTime` is the moment it stops, exclusive.
  return { from: toYmd(s), to: toYmd(e), fromTime: startTime, toTime: startTime };
}

/** A transaction as a single comparable moment, 'yyyy-MM-dd HH:mm'. One with no
 *  time of its own reads as midnight — the assumption every date-only comparison
 *  already makes. */
export function momentOf(t: { date: string; time?: string | null }): string {
  return `${t.date} ${t.time ?? '00:00'}`;
}

/** Is `t` inside `[from fromTime, to toTime)`? Without times, the inclusive date
 *  comparison this has always used. With them, moments — a transaction carrying no
 *  time of its own reads as midnight. */
export function inCycleWindow(t: { date: string; time?: string | null }, w: CycleWindow): boolean {
  if (!w.fromTime && !w.toTime) return t.date >= w.from && t.date <= w.to;
  const stamp = momentOf(t);
  if (stamp < `${w.from} ${w.fromTime ?? '00:00'}`) return false;
  if (w.toTime) return stamp < `${w.to} ${w.toTime}`;
  return t.date <= w.to;
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
// splits. Returns the signed base-currency amount that matches `matchSet`
// (empty set = whole transaction matches — i.e. no category filter on the
// budget). The caller pre-expands the budget's category_ids to include
// descendants for recursive matching (CATEGORIES_LEVEL3_PLAN §4.2).
function matchedAmount(t: Tx, matchSet: Set<string>): number {
  if (matchSet.size === 0) return t.amount;
  if (t.splits && t.splits.length) {
    let sum = 0;
    for (const s of t.splits) if (s.categoryId && matchSet.has(s.categoryId)) sum += s.amountBase;
    return sum;
  }
  return t.category != null && matchSet.has(t.category) ? t.amount : 0;
}

/**
 * Progress for one named budget over its active cycle. Expense budgets sum
 * matching outflows; recurring income budgets sum matching inflows; one-shot
 * income/goal budgets seed `used` with the `saved` offset and add matching
 * inflows on top (`used = saved + Σ matched inflows`). Matching spans
 * account · category · tags · merchants (AND across, OR within, empty =
 * unconstrained); income goals also count incoming transfer legs.
 *
 * `categories` (optional) enables **recursive category matching** — a
 * budget on `food` also catches transactions in `food › restaurants ›
 * japanese`. Pass the projected list to opt in; omit for the legacy
 * non-recursive behaviour (still useful for tests that don't care about
 * descendant expansion).
 */
export function budgetProgress(
  budget: BudgetRow,
  txns: Tx[],
  today: string,
  categories: { id: string; parentId: string | null }[] = [],
): BudgetProgress {
  const win = cycleWindow(budget.frequency, budget.startDate, today, budget.endDate, budget.isRecurring, budget.startTime ?? null);
  const accountSet = budget.accountIds.length ? new Set(budget.accountIds) : null;
  // Pre-expand the budget's configured category ids to include every
  // descendant, once. Falls back to just the configured set when no
  // categories are passed (legacy behaviour for tests / external callers).
  const matchSet = categories.length
    ? expandDescendants(budget.categoryIds, categories)
    : new Set(budget.categoryIds);

  // Extra match dimensions (AND across dimensions, OR within, empty =
  // unconstrained — same rule as account/category).
  const tagSet = budget.tagIds?.length ? new Set(budget.tagIds) : null;
  const cpSet = budget.counterpartyIds?.length ? new Set(budget.counterpartyIds) : null;

  // One-shot income goals seed `used` with the pre-tracking `saved` offset and
  // then accumulate real matched inflows on top. Recurring income and expense
  // budgets start at 0 and sum matched flows only.
  const oneShotIncome = budget.type === 'income' && budget.isRecurring === 0;
  let used = oneShotIncome ? budget.saved : 0;
  // A one-shot goal with NO scope matches nothing — its progress is the `saved`
  // offset alone. Without this, an unconstrained goal would count ALL income
  // (new goals must set ≥1 dimension; this keeps migrated/unscoped goals from
  // ballooning). Scoped goals and expense/recurring budgets run the loop.
  const incomeUnscoped = oneShotIncome && !accountSet && matchSet.size === 0 && !tagSet && !cpSet;
  if (!incomeUnscoped) for (const t of txns) {
    if (ledgerOf(t) !== budget.ledgerId) continue;
    if (t.pending || kindOf(t) === 'adjustment') continue;
    // Transfers are excluded for expense budgets only; income goals count
    // incoming transfer legs (positive amount) landing in a matched account.
    if (budget.type === 'expense' && kindOf(t) === 'transfer') continue;
    if (!inCycleWindow(t, win)) continue;
    if (accountSet && !accountSet.has(t.account)) continue;
    if (tagSet && !(t.tags ?? []).some((x) => tagSet.has(x))) continue;
    if (cpSet && (t.counterpartyId == null || !cpSet.has(t.counterpartyId))) continue;
    const amt = matchedAmount(t, matchSet);
    if (budget.type === 'expense') {
      if (amt < 0) used += -amt;
    } else if (amt > 0) {
      used += amt;
    }
  }

  const base = round2(budget.amount + (budget.type === 'expense' ? budget.carryForward : 0));
  used = round2(used);
  const remaining = round2(base - used);
  const pct = base ? Math.round((used / base) * 100) : 0;
  const over = budget.type === 'expense' && used > base;
  return { ...win, base, used, remaining, pct, over };
}
