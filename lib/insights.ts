// Computed insights (INSIGHTS_PLAN.md Phase A): pure, ranked rules over the
// projected store. Each rule returns an Insight or null; the page falls back to
// curated copy when the engine produces nothing (cold/empty ledger).

import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';
import { categorySpend, netWorthSeries } from '@/lib/select';

export interface Insight {
  tone: 'pos' | 'warn' | 'neut';
  icon: string;
  title: string;
  body: string;
}

export interface InsightCtx {
  transactions: Tx[];
  categories: { id: string; name: string; budget: number }[];
  goals: { id: string; name: string; target: number; saved: number }[];
  accounts: AccountRow[];
  ledgerId: string;
  fmt: (n: number) => string;
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const ledgerOf = (t: Tx) => t.ledgerId ?? 'personal';

type Rule = (ctx: InsightCtx) => Insight | null;

// Worst over-budget category.
const overBudget: Rule = (ctx) => {
  const spent = categorySpend(ctx.transactions, ctx.ledgerId);
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
    title: `${worst.name} over budget`,
    body: `At ${ctx.fmt(worst.spent)} of ${ctx.fmt(worst.budget)} — ${ctx.fmt(worst.over)} over.`,
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
    title: `${items.length} pending to review`,
    body: `${ctx.fmt(total)} awaiting confirmation on the Pending screen.`,
  };
};

// Top spending category + its share.
const topCategory: Rule = (ctx) => {
  const spent = categorySpend(ctx.transactions, ctx.ledgerId);
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
    title: `${name} leads your spending`,
    body: `${ctx.fmt(topSpent)} — ${pct}% of expenses this period.`,
  };
};

// Day-of-week concentration (a day ≥ 1.5× the daily average).
const weekdaySkew: Rule = (ctx) => {
  const totals = new Array(7).fill(0);
  let any = false;
  for (const t of ctx.transactions) {
    if (ledgerOf(t) !== ctx.ledgerId || t.pending || t.amount >= 0 || t.transferGroupId) continue;
    totals[new Date(`${t.date}T00:00`).getDay()] += -t.amount;
    any = true;
  }
  if (!any) return null;
  const mean = totals.reduce((a, b) => a + b, 0) / 7;
  if (mean <= 0) return null;
  let maxDay = 0;
  for (let i = 1; i < 7; i++) if (totals[i] > totals[maxDay]) maxDay = i;
  const ratio = totals[maxDay] / mean;
  if (ratio < 1.5) return null;
  return {
    tone: 'neut',
    icon: 'sparkle',
    title: `${WEEKDAYS[maxDay]}s are your spendy days`,
    body: `You spend ${ratio.toFixed(1)}× the daily average on ${WEEKDAYS[maxDay]}s.`,
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
    title: `${top.name} is ${pct}% funded`,
    body: `${ctx.fmt(top.saved)} of ${ctx.fmt(top.target)} saved.`,
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
    title: up ? 'Net worth is trending up' : 'Net worth dipped',
    body: `${up ? '+' : '−'}${ctx.fmt(Math.abs(delta))} across this period's activity.`,
  };
};

const RULES: Rule[] = [overBudget, pending, topCategory, weekdaySkew, goalProgress, netWorthTrend];

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
