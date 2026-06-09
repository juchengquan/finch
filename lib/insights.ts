// Computed insights (INSIGHTS_PLAN.md Phase A): pure, ranked rules over the
// projected store. Each rule returns an Insight or null; the page falls back to
// curated copy when the engine produces nothing (cold/empty ledger).
//
// Insight titles and bodies are returned as ICU message keys + interpolation
// params so the InsightCard can translate via `useTranslations('insightCards')`.
// Pre-formatted monetary strings come from `ctx.fmt`; weekday names come from
// `ctx.weekdayName` so the caller can supply locale-aware labels.

import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/domain/accounts/types';
import { categorySpend, netWorthSeries, prevMonth, kindOf } from '@/lib/select';

type Params = Record<string, string | number>;

export interface Insight {
  tone: 'pos' | 'warn' | 'neut';
  icon: string;
  title: { key: string; params?: Params };
  body: { key: string; params?: Params };
}

export interface InsightCtx {
  transactions: Tx[];
  categories: { id: string; name: string; budget: number }[];
  goals: { id: string; name: string; target: number; saved: number }[];
  accounts: AccountRow[];
  ledgerId: string;
  month: string; // current month (YYYY-MM); budget/spend rules scope to it
  fmt: (n: number) => string;
  /** Locale-aware weekday name for index 0-6 (Sun-Sat). */
  weekdayName: (dow: number) => string;
}

const sumValues = (m: Record<string, number>) => Object.values(m).reduce((s, v) => s + v, 0);

const ledgerOf = (t: Tx) => t.ledgerId ?? 'personal';

/** Day-of-week for a `YYYY-MM-DD` transaction date. Returns NaN for an
 *  unparseable date — callers must guard with `Number.isFinite(dow)`
 *  before using the result as an array index. Parses as UTC so server
 *  (UTC) and client (any local zone) agree on the day; a Saturday in
 *  Singapore would otherwise roll into Friday on a UTC server. */
function dowOf(date: string): number {
  const d = new Date(`${date}T00:00:00Z`);
  return d.getUTCDay();
}

type Rule = (ctx: InsightCtx) => Insight | null;

// Total spending this month vs last month.
const spendingTrend: Rule = (ctx) => {
  if (!ctx.month) return null;
  const cur = sumValues(categorySpend(ctx.transactions, ctx.ledgerId, ctx.month));
  const prev = sumValues(categorySpend(ctx.transactions, ctx.ledgerId, prevMonth(ctx.month)));
  if (prev <= 0) return null;
  const pct = Math.round(((cur - prev) / prev) * 100);
  if (pct === 0) return null;
  const down = cur < prev;
  return {
    tone: down ? 'pos' : 'warn',
    icon: down ? 'arrow-d' : 'arrow-u',
    title: { key: down ? 'spendingDown' : 'spendingUp', params: { pct: Math.abs(pct) } },
    body: { key: 'spendingBody', params: { cur: ctx.fmt(cur), prev: ctx.fmt(prev) } },
  };
};

// Worst over-budget category.
const overBudget: Rule = (ctx) => {
  const spent = categorySpend(ctx.transactions, ctx.ledgerId, ctx.month);
  let worst: { name: string; spent: number; budget: number; over: number } | null = null;
  for (const c of ctx.categories) {
    if (!c.budget) continue;
    const s = spent[c.id] ?? 0;
    const over = s - c.budget;
    if (over > 0 && (!worst || over > worst.over)) worst = { name: c.name, spent: s, budget: c.budget, over };
  }
  if (!worst) return null;
  return {
    tone: 'warn',
    icon: 'arrow-u',
    title: { key: 'overBudget', params: { name: worst.name } },
    body: { key: 'overBudgetBody', params: { spent: ctx.fmt(worst.spent), budget: ctx.fmt(worst.budget), over: ctx.fmt(worst.over) } },
  };
};

// Pending transactions awaiting confirmation.
const pending: Rule = (ctx) => {
  const items = ctx.transactions.filter((t) => ledgerOf(t) === ctx.ledgerId && t.pending);
  if (!items.length) return null;
  const total = items.reduce((s, t) => s + Math.abs(t.amount), 0);
  return {
    tone: 'neut',
    icon: 'doc',
    title: { key: 'pending', params: { count: items.length } },
    body: { key: 'pendingBody', params: { total: ctx.fmt(total) } },
  };
};

// Top spending category + its share.
const topCategory: Rule = (ctx) => {
  const spent = categorySpend(ctx.transactions, ctx.ledgerId, ctx.month);
  const entries = Object.entries(spent);
  if (!entries.length) return null;
  const total = entries.reduce((s, [, v]) => s + v, 0);
  if (total <= 0) return null;
  const [topId, topSpent] = entries.reduce((a, b) => (b[1] > a[1] ? b : a));
  const name = ctx.categories.find((c) => c.id === topId)?.name ?? topId;
  const pct = Math.round((topSpent / total) * 100);
  return {
    tone: 'neut',
    icon: 'fork',
    title: { key: 'topCategory', params: { name } },
    body: { key: 'topCategoryBody', params: { amount: ctx.fmt(topSpent), pct } },
  };
};

// Day-of-week concentration (a day ≥ 1.5× the daily average).
const weekdaySkew: Rule = (ctx) => {
  const totals = new Array(7).fill(0);
  let any = false;
  for (const t of ctx.transactions) {
    if (ledgerOf(t) !== ctx.ledgerId || t.pending || kindOf(t) !== 'expense') continue;
    const dow = dowOf(t.date);
    if (!Number.isFinite(dow)) continue;
    totals[dow] += -t.amount;
    any = true;
  }
  if (!any) return null;
  const mean = totals.reduce((a, b) => a + b, 0) / 7;
  if (mean <= 0) return null;
  let maxDay = 0;
  for (let i = 1; i < 7; i++) if (totals[i] > totals[maxDay]) maxDay = i;
  const ratio = totals[maxDay] / mean;
  if (ratio < 1.5) return null;
  const day = ctx.weekdayName(maxDay);
  return {
    tone: 'neut',
    icon: 'sparkle',
    title: { key: 'weekdaySkew', params: { day } },
    body: { key: 'weekdaySkewBody', params: { ratio: ratio.toFixed(1), day } },
  };
};

// ---------------------------------------------------------------------------
// Pattern surfacer rules. Pure descriptive aggregates over the user's own
// confirmed expenses — they find which axis of variation is loudest and turn
// it into one sentence. None of these need external data, models, or a budget.
// All are gated on a minimum sample so they don't fire on a stub ledger.
// ---------------------------------------------------------------------------

// Per-calendar-day weekend spend vs weekday spend, across the entire data
// range. Fires when weekends cost noticeably more per day (ratio ≥ 1.5×). The
// inverse case ("you spend more on weekdays") is almost universally true — work
// commute, lunches — so we don't surface it.
const weekendVsWeekday: Rule = (ctx) => {
  let weekendSum = 0;
  let weekdaySum = 0;
  let earliest = '';
  let latest = '';
  for (const t of ctx.transactions) {
    if (ledgerOf(t) !== ctx.ledgerId || t.pending || kindOf(t) !== 'expense') continue;
    if (!earliest || t.date < earliest) earliest = t.date;
    if (!latest || t.date > latest) latest = t.date;
    const dow = dowOf(t.date);
    if (!Number.isFinite(dow)) continue;
    if (dow === 0 || dow === 6) weekendSum += -t.amount;
    else weekdaySum += -t.amount;
  }
  if (!earliest || !latest) return null;
  // Count weekend vs weekday calendar days in the data range so the per-day
  // means are like-for-like (the alternative — "distinct dates with activity" —
  // would under-count no-spend days and skew toward whichever segment is busier).
  let weekendDays = 0;
  let weekdayDays = 0;
  const cursor = new Date(`${earliest}T00:00:00Z`);
  const end = new Date(`${latest}T00:00:00Z`);
  while (cursor <= end) {
    const dow = cursor.getDay();
    if (dow === 0 || dow === 6) weekendDays++;
    else weekdayDays++;
    cursor.setDate(cursor.getDate() + 1);
  }
  if (weekendDays < 6 || weekdayDays < 15) return null;
  const weekendPerDay = weekendSum / weekendDays;
  const weekdayPerDay = weekdaySum / weekdayDays;
  if (weekdayPerDay <= 0) return null;
  const ratio = weekendPerDay / weekdayPerDay;
  if (ratio < 1.5) return null;
  return {
    tone: 'neut',
    icon: 'calendar',
    title: { key: 'weekendVsWeekday' },
    body: { key: 'weekendVsWeekdayBody', params: { ratio: ratio.toFixed(1), weekend: ctx.fmt(weekendPerDay), weekday: ctx.fmt(weekdayPerDay) } },
  };
};

// The single weekday whose spending is dominated by one category — e.g.
// "Saturdays are mostly Dining out". Fires when that weekday has ≥ 40% share
// in one category, on a base of ≥ $100 weekly spend that day.
const topCategoryByWeekday: Rule = (ctx) => {
  if (!ctx.categories.length) return null;
  const byDay: Record<number, Record<string, number>> = {};
  for (let d = 0; d < 7; d++) byDay[d] = {};
  for (const t of ctx.transactions) {
    if (ledgerOf(t) !== ctx.ledgerId || t.pending || kindOf(t) !== 'expense') continue;
    if (!t.category) continue;
    const dow = dowOf(t.date);
    if (!Number.isFinite(dow)) continue;
    byDay[dow][t.category] = (byDay[dow][t.category] ?? 0) + -t.amount;
  }
  let best: { dow: number; categoryId: string; share: number } | null = null;
  for (let d = 0; d < 7; d++) {
    const entries = Object.entries(byDay[d]);
    if (entries.length < 2) continue;
    const total = entries.reduce((s, [, v]) => s + v, 0);
    if (total < 100) continue;
    const [topId, topSpent] = entries.reduce((a, b) => (b[1] > a[1] ? b : a));
    const share = topSpent / total;
    if (share < 0.4) continue;
    if (!best || share > best.share) best = { dow: d, categoryId: topId, share };
  }
  if (!best) return null;
  const name = ctx.categories.find((c) => c.id === best.categoryId)?.name ?? best.categoryId;
  const day = ctx.weekdayName(best.dow);
  return {
    tone: 'neut',
    icon: 'tag',
    title: { key: 'topCategoryByWeekday', params: { day, name } },
    body: { key: 'topCategoryByWeekdayBody', params: { pct: Math.round(best.share * 100), day, name } },
  };
};

// Days 23-end-of-month vs days 1-22 across all observed months. Fires when the
// last-week-of-month per-day spend runs ≥ 1.3× the rest. Captures "I always
// blow it before payday" and "rent + utilities cluster at month-end" alike.
const endOfMonthBump: Rule = (ctx) => {
  let lastWeekSum = 0;
  let restSum = 0;
  const months = new Set<string>();
  for (const t of ctx.transactions) {
    if (ledgerOf(t) !== ctx.ledgerId || t.pending || kindOf(t) !== 'expense') continue;
    months.add(t.date.slice(0, 7));
    const day = Number(t.date.slice(8, 10));
    if (day >= 23) lastWeekSum += -t.amount;
    else restSum += -t.amount;
  }
  // Approx: every month has ~8 "last week" days (23-30/31) and ~22 earlier
  // days. Scale by the count of observed months to get a per-day mean.
  if (months.size < 3) return null;
  const lastWeekPerDay = lastWeekSum / (months.size * 8);
  const restPerDay = restSum / (months.size * 22);
  if (restPerDay <= 0) return null;
  const ratio = lastWeekPerDay / restPerDay;
  if (ratio < 1.3) return null;
  return {
    tone: 'neut',
    icon: 'calendar',
    title: { key: 'endOfMonthBump' },
    body: { key: 'endOfMonthBumpBody', params: { ratio: ratio.toFixed(1) } },
  };
};

// Counterpart to weekdaySkew: the day-of-week that's reliably quiet (≤ 0.5×
// the daily average). Gated to ≥ 25 expense rows so a sparse log doesn't
// declare arbitrary "no-spend days".
const quietestDay: Rule = (ctx) => {
  const totals = new Array(7).fill(0);
  const counts = new Array(7).fill(0);
  for (const t of ctx.transactions) {
    if (ledgerOf(t) !== ctx.ledgerId || t.pending || kindOf(t) !== 'expense') continue;
    const dow = dowOf(t.date);
    if (!Number.isFinite(dow)) continue;
    totals[dow] += -t.amount;
    counts[dow]++;
  }
  const txCount = counts.reduce((a: number, b: number) => a + b, 0);
  if (txCount < 25) return null;
  const mean = totals.reduce((a: number, b: number) => a + b, 0) / 7;
  if (mean <= 0) return null;
  let minDay = 0;
  for (let i = 1; i < 7; i++) if (totals[i] < totals[minDay]) minDay = i;
  const ratio = totals[minDay] / mean;
  if (ratio > 0.5) return null;
  const day = ctx.weekdayName(minDay);
  return {
    tone: 'pos',
    icon: 'check',
    title: { key: 'quietestDay', params: { day } },
    body: { key: 'quietestDayBody', params: { pct: Math.round((1 - ratio) * 100), day } },
  };
};

// Savings goal closest to funded.
const goalProgress: Rule = (ctx) => {
  const inProgress = ctx.goals.filter((g) => g.target > 0 && g.saved < g.target);
  if (!inProgress.length) return null;
  const top = inProgress.reduce((a, b) => (b.saved / b.target > a.saved / a.target ? b : a));
  const pct = Math.round((top.saved / top.target) * 100);
  return {
    tone: 'pos',
    icon: 'check',
    title: { key: 'goalProgress', params: { name: top.name, pct } },
    body: { key: 'goalProgressBody', params: { saved: ctx.fmt(top.saved), target: ctx.fmt(top.target) } },
  };
};

// Net-worth direction across the period.
const netWorthTrend: Rule = (ctx) => {
  const series = netWorthSeries(ctx.transactions, ctx.accounts, ctx.ledgerId);
  if (series.length < 2) return null;
  const delta = series[series.length - 1] - series[0];
  if (Math.abs(delta) < 1) return null;
  const up = delta > 0;
  return {
    tone: up ? 'pos' : 'warn',
    icon: up ? 'arrow-u' : 'arrow-d',
    title: { key: up ? 'netWorthUp' : 'netWorthDown' },
    body: { key: 'netWorthBody', params: { sign: up ? '+' : '−', delta: ctx.fmt(Math.abs(delta)) } },
  };
};

// Order matters: actionable first (trends, over-budget, pending), then
// descriptive (top category), then the pattern surfacers (weekday/weekend
// shape, end-of-month bump, quietest day), then progress/trend coda. The
// max=6 cap in generateInsights keeps the page short — surfacer rules
// only crowd out the bottom two slots when every action rule fires.
const RULES: Rule[] = [
  spendingTrend,
  overBudget,
  pending,
  topCategory,
  weekendVsWeekday,
  topCategoryByWeekday,
  endOfMonthBump,
  weekdaySkew,
  quietestDay,
  goalProgress,
  netWorthTrend,
];

/** Run the rules in priority order; returns up to `max` insights. */
export function generateInsights(ctx: InsightCtx, max = 6): Insight[] {
  const out: Insight[] = [];
  for (const rule of RULES) {
    const ins = rule(ctx);
    if (ins) out.push(ins);
    if (out.length >= max) break;
  }
  return out;
}
