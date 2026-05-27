# Insights — design plan

Status: **Phase A implemented.** Companion to `SQLITE_INTEGRATION_PLAN.md` §6.
- ✅ **Phase A** — `lib/insights.ts` rule engine over the projected store
  (over-budget, pending, top category, weekday skew, goal progress, net-worth
  direction), ranked + capped; the Insights screen renders computed cards and
  falls back to curated copy only for a cold/empty ledger.
- ↩ **Phase B** (not started) — seed multi-month history to unlock MoM/trend
  insights and make the charts/header derive from real data. High blast radius;
  its own PR.

## 1. Goal

Replace the three hand-written insight cards with **computed** insights derived
from the projected store (transactions, budgets, accounts, goals), while keeping
the same card UI (`tone`, `icon`, `title`, `body`).

Non-goal: ML/anomaly detection or free-form natural-language generation — insights
are rule-based with templated copy.

## 2. Current state

- **Static copy.** `data/insights.json` holds 3 cards
  (`{ tone: 'pos'|'warn'|'neut', icon, title, body }`), exported as `MOCK.insights`
  / `INSIGHTS` and rendered by `app/(main)/insights/page.tsx`.
- The same screen shows charts (`monthly-spending.json`, `daily-spending.json`,
  `cashflow.json`) that are **aggregate JSON, not derived** from transactions.
- **Thin history.** Seed transactions span only **2026-05-13 → 2026-05-25**
  (~2 weeks of a single month). `monthly-spending.json` has 12 monthly totals but
  no per-category, per-transaction backing.

## 3. The hard part

The marquee insight ("Entertainment cut by 71% vs last month") is a
**month-over-month, per-category** comparison. With only ~2 weeks of single-month
transactions, MoM category deltas **cannot be computed** from real data. Two ways
forward:

- **(A) Compute only what current data supports** now, keep MoM-style cards as
  curated copy until history exists. Lowest risk; insights are real but fewer.
- **(B) Seed multi-month transaction history** to unlock MoM/trend insights. Higher
  fidelity but **ripples widely** — it changes balances, reports, charts, and
  every figure derived from transactions, and the seed's opening-balance invariant
  must be re-derived. Treat as its own phase with careful re-verification.

Recommended: ship **(A)** first behind a small rule engine; pursue **(B)** only if
we want trend/MoM insights, as a separate, well-tested change.

## 4. Rules computable from today's data (phase A)

Each rule is a pure function over the projected store returning an
`Insight | null`; the engine runs them, ranks, and takes the top N.

- **Budget overage / near-limit** — per category, `categorySpend` vs
  `budgetOverrides ?? budget`: over → `warn`; ≥ warning_pct → `neut`.
- **Top spending category** this month — leader + share of total.
- **Day-of-week concentration** — bucket confirmed expenses by weekday; flag if a
  day is ≥ 1.5× the mean ("Fridays are spendy").
- **Large/standout transaction** — a single expense ≫ the category median.
- **Pending awaiting confirmation** — count + total of `status='pending'`.
- **Goal progress** — nearest goal to completion, or one with no recent
  contribution.
- **Net-worth direction** — sign/slope of `netWorthSeries` (already implemented in
  `lib/select.ts`).

All inputs already exist in the store; no schema change for phase A.

## 5. Work breakdown

**Phase A — rule engine (no schema change)**
- `lib/insights.ts` — `generateInsights(store, ledgerId): Insight[]`: an ordered
  list of rule fns, each `(ctx) => Insight | null`; rank by severity/recency; cap
  at N (e.g. 4). Reuse `categorySpend` / `netWorthSeries` from `lib/select.ts`.
- Wire `app/(main)/insights/page.tsx` to `generateInsights(...)`, falling back to
  the curated `INSIGHTS` when the engine returns nothing (cold/empty ledger).
- Unit-test each rule with small fixtures (over-budget, weekday skew, pending,
  goal progress, empty → fallback).

**Phase B — real history (optional, separate)**
- Extend `data/transactions.json` with several prior months of transactions
  (per ledger), re-derive `openingBalance`, and re-verify the seed/balance tests
  and every figure-bearing screen. Unlocks MoM/trend rules.
- Replace the aggregate chart JSON (`monthly-spending`, `cashflow`) with values
  derived from the history so the charts and insights agree.

## 6. Risks

- **Thin data → generic insights.** Phase A on ~2 weeks yields a few cards;
  keep curated fallback so the screen never looks empty.
- **Phase B ripple.** Adding history is the highest-blast-radius change in the
  app — it moves balances/reports/charts. Gate it behind its own PR with full
  re-verification; do not bundle with phase A.
- **Copy quality.** Templated bodies must read naturally across value ranges
  (singular/plural, %, currency via `useMoney`).

## 7. Open questions

- Ledger scope: insights for the **active ledger** only (consistent with other
  screens), or a combined view?
- Do we want phase B at all, or is a real-but-smaller insight set (phase A) the
  intended end state for the demo?
