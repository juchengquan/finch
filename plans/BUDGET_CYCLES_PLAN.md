# Budget cycles + automatic period rollover — plan

Two related changes, designed together because they touch the same
queries / mutations / UI:

1. **Budget cycles become first-class.** Today `frequency` exists in the
   schema (`daily | weekly | biweekly | monthly | quarterly | yearly`)
   but the entire app pretends every budget is monthly. Users can't
   pick a cycle, can't change one, and every read query filters
   `WHERE frequency = 'monthly'`.
2. **Automatic carry-forward at the end of each period.** Today
   `carry_forward` is just a manual number on the row; nothing actually
   moves last period's leftover into the next one.

---

## Current state

### Schema (`lib/db/schema.ts`)

The fields are mostly there already:

```sql
CREATE TABLE budgets (
  id              TEXT PRIMARY KEY,
  ledger_id       TEXT NOT NULL,
  name            TEXT,
  type            TEXT CHECK(type IN ('income','expense')),
  amount          REAL NOT NULL,
  carry_forward   REAL NOT NULL DEFAULT 0,
  frequency       TEXT CHECK(frequency IN ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  start_date      TEXT NOT NULL,
  end_date        TEXT,
  is_recurring    INTEGER NOT NULL DEFAULT 1,
  rollover        INTEGER NOT NULL DEFAULT 0,
  rollover_limit  REAL,
  category_ids    TEXT,
  ...
);
```

So `frequency` + `start_date` already exist. What's missing structurally
is one new column: **`last_rolled_period TEXT`** — the latest period the
auto-rollover has processed for this budget. NULL = never rolled.

### Read queries (`lib/db/queries/budgets.ts`, `reports.ts`)

- `budgetByCategory` filters `WHERE frequency = 'monthly'`.
- `budgetRolloverByCategory` — same.
- `budgetProgress` takes a `yearMonth` string and matches `date LIKE
  '2026-05%'`. Hard-coded to month-shaped periods.
- `monthlyByCategory`, the client `categorySpend` — same assumption.

### Mutations (`lib/db/mutations.ts`, `lib/db/queries/budgets.ts`)

- `setCategoryBudget(exec, categoryId, amount)` hardcodes
  `frequency = 'monthly'`, `start_date = '2026-05-01'`. No way to
  specify cycle.
- `setCategoryBudgetRollover` lets a user manually nudge `carry_forward`
  — that's the only path it ever changes.

### UI (`app/(main)/budgets/[id]/page.tsx`)

- Edit dialog only edits the amount. No cycle picker.
- Header shows "monthly limit". No "current period" indicator.

### Selectors (`lib/select.ts`)

- `categorySpend(txns, ledgerId, month?)` slices by `YYYY-MM`. No
  concept of a non-month period.

---

## Plan

### 1. Schema change (datetime version `2026-06-XX…`)

One new column on `budgets`, plus a corresponding index:

```sql
ALTER TABLE budgets ADD COLUMN last_rolled_period TEXT;
CREATE INDEX IF NOT EXISTS idx_budget_last_rolled ON budgets(last_rolled_period);
```

That's it for schema. `frequency` / `start_date` / `carry_forward` /
`rollover_limit` already exist.

A second migration step backfills `start_date` for existing rows — today
every row uses the hard-coded `'2026-05-01'`. For now that stays fine
since they're all monthly (calendar-aligned, no anchor matters).

### 2. Period arithmetic — new `lib/budgets/period.ts`

Pure helpers with no DB dependency:

```ts
export type Frequency = 'daily'|'weekly'|'biweekly'|'monthly'|'quarterly'|'yearly';

/**
 * Canonical id for the period containing `date`. Stable string keys that
 * sort chronologically:
 *   periodOf('2026-04-15', 'monthly',   anchor)      → '2026-04'
 *   periodOf('2026-04-15', 'quarterly', anchor)      → '2026-Q2'
 *   periodOf('2026-04-15', 'yearly',    anchor)      → '2026'
 *   periodOf('2026-04-15', 'weekly',    '2026-01-05') → '2026-W16'
 *   periodOf('2026-04-15', 'biweekly',  '2026-01-05') → '2026-BW08'
 *   periodOf('2026-04-15', 'daily',     anchor)      → '2026-04-15'
 */
export function periodOf(date: string, frequency: Frequency, anchor: string): string;

/** Inclusive YYYY-MM-DD bounds of the named period. */
export function periodRange(period: string, frequency: Frequency, anchor: string): { from: string; to: string };

/** Next / previous period id (chronologically). */
export function nextPeriod(period: string, frequency: Frequency): string;
export function prevPeriod(period: string, frequency: Frequency): string;

/** Human-readable label for headers ("April 2026", "Q2 2026", "Week of Apr 13"). */
export function periodLabel(period: string, frequency: Frequency): string;
```

Anchor matters for `weekly` / `biweekly` (otherwise "what day is the
week boundary?" is undefined). For everything else it's calendar-aligned
and the anchor is ignored. The anchor is just `budgets.start_date`.

### 3. Read queries become period-aware

- `budgetByCategory()` drops the `WHERE frequency = 'monthly'`. Returns
  `Record<categoryId, { amount, frequency, startDate }>` so the UI can
  display the right unit.
- `budgetProgress()` switches from `(ledgerId, yearMonth)` to
  `(ledgerId)` and, for each budget, computes its **own** current period
  via `periodOf(today, freq, start_date)`, builds a date filter from
  `periodRange(...)`, and sums spend.
- `monthlyByCategory()` stays month-shaped (it's used by the monthly
  report card). We add a parallel `categorySpendForPeriod()` that takes
  the period.
- Client `categorySpend(txns, ledgerId, month?)` is unchanged for now;
  the budget detail page calls a new period-shaped variant.

### 4. Cycle-change behaviour (design choice — surfaced)

When the user changes a budget's frequency, what happens to the amount?
Three options:

- **(A) Keep amount, prompt user** — modal: "Switching $700 monthly to
  weekly. Keep $700 as the weekly limit, or pro-rate to $175?" Pick.
- **(B) Pro-rate silently** — every cycle has a per-day rate; convert.
  Silent, occasionally surprising.
- **(C) Reset and force re-enter** — clears `amount`, opens the edit
  dialog.

**Recommendation: A.** Most explicit, no surprises. Pro-rate is
computed as `amount * (newDays / oldDays)` using the canonical
days-per-cycle map (`daily=1, weekly=7, biweekly=14, monthly=30.42,
quarterly=91.25, yearly=365.25`).

Either way: when the cycle changes, **`last_rolled_period` is reset to
NULL** and **`carry_forward` is reset to 0**. Rolling over a budget
across a unit change isn't well-defined; clean slate is the honest move.

### 5. Automatic carry-forward — auto-on-load + targeted recompute

#### When it runs

A new helper `rollBudgetsIfDue(exec)` runs:

- Once per request, near the top of `/api/state` (and `/api/mutate`'s
  return-projection step). It's idempotent — a no-op when nothing's due
  — so calling it on every request is fine.
- Triggered explicitly after backdated edits (see below).

#### What it does, per budget with `rollover = 1`

```
today        = current date (YYYY-MM-DD)
currentP     = periodOf(today, freq, start_date)
lastRolled   = budget.last_rolled_period           // may be NULL
target       = prevPeriod(currentP, freq)          // the period to roll INTO currentP

while lastRolled < target:
  rollFrom = lastRolled == NULL ? periodOf(start_date, freq, start_date) : nextPeriod(lastRolled, freq)
  range    = periodRange(rollFrom, freq, start_date)
  spent    = SUM(amount_base) for confirmed expenses in budget's category_ids
             whose date is in [range.from, range.to]
  effective = amount + carry_forward
  leftover  = max(0, effective - spent)
  newCF     = rollover_limit == null ? leftover : min(leftover, rollover_limit)

  carry_forward     = newCF
  last_rolled_period = rollFrom
```

So the loop catches up cleanly if the app's been closed for a few
months. Bounded — only the missing periods get processed.

#### When `last_rolled_period` is NULL on a never-rolled budget

It starts at `start_date`'s period — i.e., the budget doesn't try to
roll periods that pre-date itself.

### 6. Backdated edits invalidate the cache

Same prior-art the app already uses for `recomputeAccount`. After every
mutation that affects a transaction (`addTransaction`,
`updateTransaction`, `cancelTransaction`, `setTransactionSplits`):

```
affectedCategories = {tx.category, ...tx.splits.map(s => s.categoryId)}
affectedPeriod     = periodOf(tx.date, ...)

for each budget that includes one of affectedCategories:
  if affectedPeriod <= budget.last_rolled_period:
    budget.last_rolled_period = prevPeriod(affectedPeriod, freq)
    // bound: never go before the budget's start period
```

The next request to `rollBudgetsIfDue` will replay rollover forward
from there. Cheap — the recompute walks at most the number of periods
between the edit's date and today.

### 7. UI changes

- **Budget detail edit dialog**: add a cycle selector (daily through
  yearly). Changing the cycle pops the cycle-change dialog from §4.
- **Budget detail header**: show the current period ("Q2 2026 ·
  Apr 1 – Jun 30") + the cycle.
- **Budget list / category row**: show the period unit next to the
  amount (e.g. "$700/mo", "$175/wk").
- **Rollover dialog**: disable the rollover toggle when frequency =
  daily (carry-forward at daily resolution is nonsensical for budgets).

### 8. Edge cases

- **New budget mid-period**: rollover is a no-op until the period the
  budget was created in ends.
- **Toggling rollover ON mid-period**: no retroactive carry-forward;
  the next period boundary picks it up.
- **Cycle change mid-period**: the budget's new "first period" is the
  period containing `today` under the new frequency. We don't try to
  reconstruct rollover history under the new cycle (would be ambiguous).
- **`start_date` in the future**: budget is dormant — `currentPeriod`
  resolves to `null` until the date is reached; `rollBudgetsIfDue`
  skips dormant budgets.
- **`end_date` set and passed**: `currentPeriod` returns `null` after
  end; rollover stops accumulating.
- **Daily rollover**: schema-allowed but blocked at the mutation
  boundary (`setCategoryBudgetRollover` throws when frequency = daily).
- **Bi-weekly anchor**: the period id includes the anchor's week-of-year
  parity so weekly and biweekly don't collide.
- **Multiple budgets sharing a category**: each budget's rollover is
  computed independently from its own `last_rolled_period`; same spend
  decrements both effective totals.
- **DST / timezone**: dates are YYYY-MM-DD strings — no DST math
  needed. We treat day boundaries as local calendar days (matching
  every other date filter in the app).

### 9. Tests

- `periodOf` round-trips through every frequency at quarter, year,
  week, and biweek boundaries (including the anchor edge case).
- `periodRange(periodOf(date)).contains(date)` for every frequency.
- `rollBudgetsIfDue` on a fresh budget never runs (`last_rolled` =
  null, immediately advances to `currentPeriod - 1`'s start).
- `rollBudgetsIfDue` catches up multiple missed periods.
- `rolloverLimit` caps the carry-forward.
- Backdated edit invalidates `last_rolled_period` and the next call
  replays correctly.
- Cycle change resets `last_rolled_period` + `carry_forward`.

---

## File touch list

| Path | Change |
|---|---|
| `lib/db/schema.ts` | New datetime migration: `ALTER TABLE budgets ADD COLUMN last_rolled_period TEXT` + index. |
| `lib/budgets/period.ts` *(new)* | `periodOf`, `periodRange`, `nextPeriod`, `prevPeriod`, `periodLabel`. |
| `lib/budgets/period.test.ts` *(new)* | Unit tests over every frequency. |
| `lib/budgets/rollover.ts` *(new)* | `rollBudgetsIfDue(exec)`, `recomputeRolloverFor(exec, txnDate, categoryIds)`. |
| `lib/budgets/rollover.test.ts` *(new)* | Catch-up, cap, backdated-edit recompute. |
| `lib/db/queries/budgets.ts` | `setCategoryBudget` takes `frequency` + `startDate`; new `updateBudgetCycle`; period-shaped read queries. |
| `lib/db/queries/reports.ts` | `budgetProgress` switches from `yearMonth` to per-budget current-period derivation. |
| `lib/db/mutations.ts` | New cases: `updateBudgetCycle`, `setCategoryBudgetWithCycle`. Call `recomputeRolloverFor` from the existing tx-mutation handlers. |
| `app/api/state/route.ts` | Call `rollBudgetsIfDue(exec)` before projecting. |
| `app/api/mutate/route.ts` | Same — after applying the mutation, before re-projection. |
| `app/(main)/budgets/[id]/page.tsx` | Cycle selector + cycle-change dialog + period header. |
| `app/(main)/budgets/page.tsx` | Show cycle next to amount in the list. |
| `lib/store.ts` | Carry `frequency` + `startDate` per category on the projected map. |
| `lib/select.ts` | `categorySpendForPeriod(txns, ledgerId, from, to)` + period helpers re-exported for client. |
| `plans/MASTER_PLAN.md` | Strike "automatic month-end carry-forward" once shipped. |

**Suggested commit split**:

1. **Schema migration + period arithmetic** (`schema.ts`, `lib/budgets/period.ts`, tests). No behaviour change yet; everything still uses monthly.
2. **Period-aware reads** (`budgets.ts`, `reports.ts`, `state.ts`,
   `mutations.ts` for the read side). Still no auto-rollover, but
   non-monthly budgets render correctly.
3. **Cycle-change UI + mutation** (`budgets/[id]/page.tsx`,
   `mutations.ts`, cycle-change dialog).
4. **`rollBudgetsIfDue` + backdated-edit recompute** (`rollover.ts`,
   wired into `/api/state` and `/api/mutate`).

---

## Out of scope

- ❌ Per-account budgets (the `account_ids` column exists but is unused
  app-wide; not in this PR).
- ❌ Per-tag budgets (same — `tag_ids` exists, unused).
- ❌ Rollover for non-`rollover_limit`-capped overflows that *grow* via
  income (we only roll under-spend, not over-income).
- ❌ Showing historical carry-forward per period (we keep only "current
  carry_forward + last_rolled_period"; reconstructing the timeline is a
  separate feature).
- ❌ Daily-rolling daily budgets — schema-allowed, mutation-blocked.
