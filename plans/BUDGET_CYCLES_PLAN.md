# Budget cycles + automatic period rollover — plan

> **Status (2026-05-31).** Shipped in **PR #48** (`66cff5f`) against the *legacy
> per-category* budget model (`budgetByCategory` maps, `bud-<categoryId>` rows).
> That model was then **superseded by the named-budgets redesign**
> (`plans/budgets_redesign.md`), merged into `feat/frontend` in the clean-slate-DB
> squash (`bdd6f47`), which **dropped #48's engine** — `lib/budgets/period.ts`,
> `lib/budgets/rollover.ts`, and the `last_rolled_period` / `pending_amount`
> columns are no longer in the tree.
>
> This doc is now the **re-application spec**. The period arithmetic and rollover
> semantics (§2, §4, §5, §6, §8) are still correct and model-agnostic; the
> *per-category* plumbing (§3 reads, the §1 schema notes, the file-touch list)
> must be re-expressed against **named budget entities**. See **§10** for the
> concrete mapping. The original code is recoverable from `66cff5f`:
> `lib/budgets/period.ts` is pure and reusable verbatim; `rollover.ts` needs
> adapting to named budgets.

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

Two new columns on `budgets`, plus a corresponding index:

```sql
ALTER TABLE budgets ADD COLUMN last_rolled_period TEXT;
ALTER TABLE budgets ADD COLUMN pending_amount    REAL;
CREATE INDEX IF NOT EXISTS idx_budget_last_rolled ON budgets(last_rolled_period);
```

- `last_rolled_period` — the latest period the auto-rollover has
  processed for this budget. NULL = never rolled.
- `pending_amount` — staged amount change that activates at the next
  period boundary. NULL = no change pending. See §4b.

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

### 4a. Cycle-change behaviour — immediate, amount carries over

When the user changes a budget's frequency:

- The **same number stays as the `amount`**, just attached to the new
  unit. Monthly $700 → weekly $700/week. No pro-rate, no prompt.
- The cycle change is **immediate**: the new cycle's first period
  starts at the current `today`'s slot under the new frequency
  (e.g., switching to weekly on a Wednesday → the current week's
  period under weekly is now active).
- `last_rolled_period` is **reset to NULL**. Period IDs from the old
  cycle don't translate to the new cycle, so rollover starts fresh
  on the new unit. The next request's `rollBudgetsIfDue` advances
  it to the period *just before* the current one — no spurious
  retroactive carry-forward.
- `carry_forward` is **preserved**. It's an absolute dollar amount;
  it doesn't depend on the cycle unit. The first period under the new
  cycle inherits whatever was already accumulated.
- `pending_amount`, if any, is **discarded** (the user implicitly chose
  the cycle change as the new active state).
- `rollover_limit` is **preserved** for the same reason as
  `carry_forward`: it's an absolute dollar cap.

This collapses the cycle-change dialog into a single confirmation
("This will change Groceries from monthly to weekly. The $700 limit
becomes a weekly limit starting now.").

### 4b. Amount-change behaviour — staged, takes effect next period

When the user changes only the amount on a budget (no cycle change):

- The new amount is **staged in `pending_amount`** rather than
  overwriting `amount`. The current period's "spent of budget"
  calculation continues to use the existing `amount` — fair, since
  the user might already be mid-period.
- `rollBudgetsIfDue`, when advancing the period boundary, **commits
  `pending_amount` to `amount` and clears `pending_amount`** as the
  *first* step (before computing rollover). So the new period starts
  with the new limit immediately.
- If the user edits the amount again before the next period
  boundary, `pending_amount` is overwritten — only the latest staged
  value applies.
- If the user wants to undo a pending change, they re-enter the
  current `amount`; `pending_amount` is cleared.

If a user changes **both** cycle and amount in the same edit:

- Treat as a cycle change with `amount = newAmount` applied
  immediately. (§4a wins; `pending_amount` is irrelevant because the
  edit is fundamentally a unit change.) The dialog's confirm text
  mirrors this: "Groceries becomes $500/week starting now."

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

  carry_forward      = newCF
  last_rolled_period = rollFrom

  // Apply any staged amount change as the NEW period (the one we just rolled
  // INTO) begins. This is what makes amount edits affect "the following cycle"
  // as required by §4b. Done after computing rollover so the period we just
  // closed used the in-effect amount.
  if pending_amount != NULL:
    amount         = pending_amount
    pending_amount = NULL
```

So the loop catches up cleanly if the app's been closed for a few
months. Bounded — only the missing periods get processed.

**Budgets with `rollover = 0`** still need the period-advance step so
their `pending_amount` gets activated on schedule. The function runs
the same loop but skips the carry-forward arithmetic — only the
`last_rolled_period` and `pending_amount` updates happen.

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
  yearly) alongside the existing amount field.
  - On submit, derive what changed:
    - **Cycle changed** (with or without amount change) → confirm
      dialog: "Groceries becomes $X/{unit} starting now." On OK,
      cycle change applies immediately per §4a. `pending_amount` is
      cleared.
    - **Amount changed only** → stage in `pending_amount` (§4b). No
      confirmation needed; toast: "New limit takes effect on
      {next-period-label}."
- **Pending-amount indicator**: when `pending_amount != NULL`, the
  budget header shows a small chip "$800 next {period}" next to the
  active "$700/mo" line.
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
- **Multiple amount edits in one period**: only the most-recent
  `pending_amount` survives — earlier ones are overwritten before the
  next period boundary.
- **Pending amount + cycle change in the same edit**: the cycle change
  wins. `pending_amount` is discarded; the new `amount` (as entered
  in the dialog) becomes the active limit under the new cycle.
- **Pending amount when rollover is OFF**: still gets activated at the
  period boundary by the same `rollBudgetsIfDue` pass — that function
  always advances `last_rolled_period` and swaps `pending_amount`,
  even when carry-forward arithmetic is skipped.
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
- Cycle change resets `last_rolled_period` to NULL, **preserves**
  `carry_forward`, **discards** `pending_amount`.
- Setting `pending_amount` and waiting for the next period activates
  it as the new `amount`.
- Setting `pending_amount` twice in the same period keeps only the
  latest.
- Rollover OFF + `pending_amount` set: the next period boundary still
  activates the pending amount.

---

## File touch list

| Path | Change |
|---|---|
| `lib/db/schema.ts` | New datetime migration: `ALTER TABLE budgets ADD COLUMN last_rolled_period TEXT` + `pending_amount REAL` + index. |
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

## 10. Re-application onto named budgets

The named-budgets redesign (`plans/budgets_redesign.md`) already makes each budget
a **row with its own cycle** — `frequency`, `start_date`, `end_date`,
`is_recurring`, `rollover`, `rollover_limit`, `carry_forward` are all per-budget
columns, and the watch set is `account_ids[]` + `category_ids[]` (+ `tag_ids[]`).
That's a *better* fit than the per-category map: each budget row is already the
unit the rollover loop iterates, so no `bud-<categoryId>` indirection.

**Reusable verbatim (recover from `66cff5f`)**
- `lib/budgets/period.ts` — `periodOf` / `periodRange` / `nextPeriod` /
  `prevPeriod` / `periodLabel` / `Frequency`. Pure, no DB dependency, model-
  agnostic. Drop in as-is, plus `period.test.ts`.

**Schema — add to the clean baseline `SCHEMA` (no migration; pre-release)**
- `budgets.last_rolled_period TEXT`, `budgets.pending_amount REAL`, and
  `idx_budget_last_rolled`. Add them straight to the canonical `CREATE TABLE
  budgets` — the clean-slate DB has **no migration framework**, so fresh DBs are
  born with them (bump `SCHEMA_VERSION` only if you want the baseline restamped).

**Engine (`lib/budgets/rollover.ts`) — adapt per-category → per-budget**
- `rollBudgetsIfDue(exec, today)` (signature unchanged): iterate **budget rows**
  instead of categories. Each `rollover`-eligible **expense** budget uses its own
  `frequency` + `start_date` as the period anchor; a period's spend sums confirmed
  `kind='expense'` rows (parent + splits) whose `(account_id, category_id, date)`
  fall inside the budget's `account_ids`/`category_ids` filter and `periodRange`.
  The `carry_forward` / `rollover_limit` / `pending_amount` / `last_rolled_period`
  arithmetic from §5 is unchanged. Income-type budgets are skipped.
- `invalidateRollover(exec, earliestDate, {accountIds, categoryIds})` (§6): reset
  `last_rolled_period` for any budget whose filter intersects the edited txn and
  whose rolled range covers `earliestDate`. **Clean-slate caveat:** spend is
  `kind='expense'` confirmed rows, and delete is now a **hard DELETE** — the
  delete handler must capture the removed row's account/category/date *before*
  deleting so invalidation can still run.

**Reads / projection**
- The redesign projects `budgets: BudgetRow[]` (not the old `budgetByCategory` /
  `budgetRolloverByCategory` maps), so "current period · spent · remaining" is
  computed **per budget** in `queries/budgets.ts` + `reports.ts` via
  `periodOf(today, b.frequency, b.start_date)` → `periodRange`. The §3 changes,
  written for the maps, are obsolete; the §2 period helpers they call are not.

**Wiring (unchanged from #48)**
- Call `rollBudgetsIfDue(exec, todayUtc())` in the server read/mutate path
  (`lib/db/server.ts`), persisting when `rolled > 0`. Call `invalidateRollover`
  from the tx mutation handlers (`addTransaction`, `updateTransaction`,
  `deleteTransaction`, `setTransactionSplits`).

**UI**
- Cycle selector + cycle-change-vs-amount-change semantics (§4a/§4b), the
  pending-amount chip, and the period header (§7) move onto the named-budget
  detail page (`app/(main)/budgets/[id]/page.tsx`), the create/edit dialog
  (`components/budget-form-dialog.tsx`), and the budget list rows.

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
