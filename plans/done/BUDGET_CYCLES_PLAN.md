# Budget cycles + automatic period rollover — reimplementation plan

Status: **implemented & merged** on `feat/frontend`. `rollBudgetsIfDue()` in
`lib/budgets/rollover.ts` is driven from `lib/db/server.ts` against the named-
budgets model, with `last_rolled_period` + `pending_amount` columns on
`budgets` and tests in `lib/budgets/rollover.test.ts`. The spec below is kept
as the design rationale; everything described as "to do" / "to implement" is
done.

---

The original engine shipped in PR #48 against the legacy
per-category-amount-map model. The "clean-slate DB + named-budgets"
redesign (`bdd6f47`) dropped that engine and rebuilt budgets as named
entity rows organized in groups. This doc is the spec for putting
cycles + auto-rollover back, against the new model.

The user-facing semantics from the original plan are unchanged:

- **Cycle change is immediate, amount carries over** (no pro-rate, no
  prompt).
- **Amount change is staged** and applies at the next period boundary.
- **Combined cycle+amount edit** treated as cycle change; new amount
  applied immediately under the new cycle.

---

## Current state (post-redesign, what already exists)

### Schema (`lib/db/schema.ts`)
- `budgets` row carries `id`, `ledger_id`, `group_id`, `name`, `type`
  (`income`/`expense`), `amount`, `saved`, `carry_forward`, `frequency`
  (daily/weekly/biweekly/monthly/quarterly/yearly), `start_date`,
  `end_date`, `is_recurring`, `rollover`, `rollover_limit`,
  `account_ids` / `category_ids` / `tag_ids` (JSON arrays), `warning_pct`,
  timestamps.
- `budget_groups` row: `id`, `ledger_id`, `name`, `sort_order`,
  timestamps.
- `SCHEMA_VERSION = '2026-05-31T00:00:00Z'`. **No migration framework** —
  clean-slate model expects fresh DBs born complete; columns are added
  directly to the canonical CREATE.
- **Missing:** `last_rolled_period TEXT`, `pending_amount REAL`. (Both
  are nullable.)

### Queries (`lib/db/queries/budgets.ts`, `lib/db/queries/budgetGroups.ts`)
- `BudgetRow` type mirrors the schema; `listBudgets`, `createBudget`,
  `updateBudget(id, patch)`, `contributeBudget(id, amount)`,
  `deleteBudget(id)`.
- Group CRUD lives in `queries/budgetGroups.ts`.
- **No cycle / rollover logic anywhere on the server.**

### Selectors (`lib/select.ts`)
- **`cycleWindow(frequency, startDate, today, endDate?, isRecurring?)`**
  → `{ from, to }` (lines 488–515). Handles all six frequencies, DST-free
  UTC math, day-of-month clamping for short months, non-recurring single
  windows. Already covers everything `periodOf` would need.
- **`budgetProgress(budget, txns, today)`** → `{ from, to, base, used,
  remaining, pct, over }` (lines 547–576). Period-aware; sums tx amounts
  whose date falls inside the current cycle window, honouring
  `accountIds` / `categoryIds` filters and tx splits.
- Already includes `carry_forward` in `base` for expense budgets.

### State / store (`lib/store.ts`)
- `budgets: BudgetRow[]`, `budgetGroups: BudgetGroupRow[]`.
- Actions: `createBudget`, `updateBudget`, `removeBudget`,
  `contributeBudget`, plus group CRUD. No `setBudget`-style amount-only
  shortcut.

### Mutations (`lib/db/mutations.ts`)
- `createBudget`, `updateBudget`, `removeBudget`, `contributeBudget`,
  and group CRUD. `updateBudget` takes a generic patch and writes it
  through unchanged. **No `updateBudgetCycle`** — the form blasts the
  whole patch at one mutation.

### UI
- `components/budget-form-dialog.tsx`: flat form. Has frequency
  selector + rollover toggle, but no cycle-change-specific path; no
  pending-amount chip; no "takes effect next period" feedback.
- `/budgets/page.tsx`: list of cards grouped by `budgetGroups`. Each
  card shows `{p.from.slice(5)}–{p.to.slice(5)}` (period window).
- `/budgets/[id]/page.tsx`: ring + window range + "left/over". No
  pending-amount indicator.

### Tests
- `lib/select-budgets.test.ts` covers `cycleWindow` across every
  frequency + edge cases, plus `budgetProgress` (filter combinations,
  carry-forward inclusion, splits). **No rollover, no staging.**
- `lib/db/budgets-entity.test.ts` covers create/update/delete
  round-trips + group cascade behaviour.

---

## Goal

Put the four behaviours from the original plan back on top of the new
named-budget model:

1. **Cycle change is immediate, amount carries over** — same dollar
   number, new unit. `last_rolled_period` resets to NULL.
   `pending_amount` discarded. `carry_forward` + `rollover_limit`
   preserved (cycle-agnostic absolute amounts).
2. **Amount change is staged** in a new `pending_amount` column. The
   current period's `budgetProgress.base` keeps using the existing
   `amount`. The rollover loop commits `pending_amount → amount` as
   the first step of advancing the period boundary.
3. **Automatic carry-forward** — when an expense budget with
   `rollover = 1` crosses a period boundary, last period's leftover
   (capped at `rollover_limit`) becomes `carry_forward`.
4. **Backdated-edit invalidation** — when a transaction edit affects a
   period that was already rolled, reset that budget's rollover state
   so the next request replays cleanly.

---

## Plan

### 1. Schema additions (no migration; canonical CREATE only)

```sql
-- inside CREATE TABLE budgets ...
last_rolled_period TEXT,
pending_amount     REAL,
```

Add the corresponding index:

```sql
CREATE INDEX IF NOT EXISTS idx_budget_last_rolled ON budgets(last_rolled_period);
```

Bump `SCHEMA_VERSION` to a fresh datetime (`'2026-05-31T18:00:00Z'`
or similar) so older exports get rejected by the import validator.
No migration block — clean-slate DBs are born complete.

### 2. Period arithmetic — extract a module

Factor the inlined helpers in `lib/select.ts` into
`lib/budgets/period.ts`:

```ts
export type Frequency = 'daily'|'weekly'|'biweekly'|'monthly'|'quarterly'|'yearly';

/** Canonical period id for the period containing `date`. Sortable by
 *  lex compare. `anchor` = budget.start_date (matters for biweekly). */
export function periodOf(date: string, frequency: Frequency, anchor: string): string;

/** Inclusive YYYY-MM-DD bounds of the period. */
export function periodRange(period: string, frequency: Frequency, anchor: string): { from: string; to: string };

/** Adjacent periods chronologically. */
export function nextPeriod(period: string, frequency: Frequency, anchor: string): string;
export function prevPeriod(period: string, frequency: Frequency, anchor: string): string;

/** Human-readable header label. */
export function periodLabel(period: string, frequency: Frequency): string;
```

Period-id formats (sortable by lex compare):
- daily `2026-04-15`
- weekly `2026-W16` (ISO 8601)
- biweekly `BW-2026-04-13` (Monday of the bucket's first week — anchor
  picks the phasing)
- monthly `2026-04`
- quarterly `2026-Q2`
- yearly `2026`

`cycleWindow` stays in `lib/select.ts` as-is for `budgetProgress`'s
consumption — both modules can share the underlying date helpers, but
we don't need to rewrite the working selector. The rollover loop
(server-side) uses the new period module; the UI display continues to
go through `budgetProgress` which uses `cycleWindow`.

### 3. Rollover module — `lib/budgets/rollover.ts`

```ts
/** Idempotent catch-up. Walks each budget from its last_rolled_period
 *  up to the most-recent already-closed period. Per period: rollover
 *  (if on) computes leftover → cap → new carry_forward; either way,
 *  any pending_amount → amount. Returns the number of period
 *  transitions applied. No-op when nothing's due. */
export async function rollBudgetsIfDue(exec: Exec, today: string): Promise<{ rolled: number }>;

/** Resets last_rolled_period to NULL and carry_forward to 0 for every
 *  budget whose category/account filter overlaps `affected` and whose
 *  last_rolled_period covers earliestDate. The next rollBudgetsIfDue
 *  replays from start_date forward. */
export async function invalidateRollover(
  exec: Exec,
  affected: { categoryIds: string[]; accountIds: string[] },
  earliestDate: string,
): Promise<{ invalidated: number }>;
```

Implementation notes:

- **Rollover is for `is_recurring = 1` only.** One-shot budgets
  (`is_recurring = 0`) skip the loop entirely — they don't have
  repeating period boundaries.
- **Past `end_date`?** Skip — the budget is closed.
- **`start_date` in the future?** Skip — dormant.
- **Rollover off but `pending_amount` set?** Still walk forward so
  `pending_amount → amount` activates at the boundary. Skip the
  carry-forward arithmetic.
- **Filter overlap for invalidation:**
  - `categoryIds = []` on a budget = "matches every category" → that
    budget is always overlapped by any tx with a category.
  - Same for `accountIds = []`.
  - Otherwise: intersect with the affected tx's category + account.
- **Spent in a period:** reuse the same SQL idiom `budgetProgress` uses
  (LEFT JOIN `transaction_splits` + COALESCE so splits override the
  parent category) but scope by the period's date range +
  account/category filter.

### 4. Mutation cases

The form is one dialog; the mutation router needs to detect what
changed. Two paths:

**Path A — cycle / start_date changed (immediate):**

```ts
case 'updateBudgetCycle': {
  // patch may include frequency, startDate, amount (all three optional;
  // at least frequency or startDate must differ from the row).
  // Reads the row, computes the next state:
  //   amount         = patch.amount ?? row.amount
  //   frequency      = patch.frequency ?? row.frequency
  //   start_date     = patch.startDate ?? row.start_date
  //   pending_amount = NULL              (discard)
  //   last_rolled_period = NULL          (new cycle's clock starts fresh)
  // carry_forward + rollover_limit preserved.
}
```

**Path B — only `amount` changed (staged):**

We have two reasonable shapes:

- **Reuse `updateBudget` with a staging convention** — when the patch
  contains *only* `amount` (no frequency / start_date / recurring /
  rollover / filters), the handler writes to `pending_amount` instead
  of `amount`. Otherwise it patches `amount` directly.
- **OR add `setBudgetAmount` as a distinct case.**

Recommendation: **the first**. Keeps the client-side patch surface
unchanged. The store action stays one mutation; the form just calls
`updateBudget(patch)` and the server figures out whether to stage.

**One subtlety:** if the patch touches `category_ids` /
`account_ids` / `tag_ids` / `name` / `warning_pct` (filter or display
edits), the amount still patches through immediately — staging only
applies when the *amount* field is the only material change.

The form's UI logic derives whether to call `updateBudgetCycle` or
`updateBudget` based on the diff:

| Field changed | Route |
|---|---|
| frequency or startDate | `updateBudgetCycle` (carries amount if also changed) |
| amount only | `updateBudget` (stages via the above rule) |
| amount + filter / name / etc. | `updateBudget` (amount applies immediately because the patch isn't amount-only) |
| filter / name / etc. only | `updateBudget` (no amount staging) |

Document this decision in the dialog's description text so the user
sees what's about to happen ("Amount change takes effect next period" /
"Cycle change applies now").

**Other mutation cases that need adjustment:**

- `removeBudget` — no change.
- `contributeBudget` — no change (one-shot income flow).
- `createBudget` — no change. New budgets start with `pending_amount =
  NULL`, `last_rolled_period = NULL`. The first
  `rollBudgetsIfDue` after creation starts the clock.

### 5. Wiring

**`lib/db/server.ts`:**

```ts
// Inside the existing serialize() write-chain mutex.
export async function readState(): Promise<ProjectedState> {
  return serialize(async () => {
    const db = await getServerDb();
    const { rolled } = await rollBudgetsIfDue(db.exec, todayUtc());
    if (rolled > 0) await db.persist();
    return projectState(db.exec);
  });
}

export function withWrite(fn: (exec: Exec) => Promise<void>): Promise<ProjectedState> {
  return serialize(async () => {
    const db = await getServerDb();
    await fn(db.exec);
    await rollBudgetsIfDue(db.exec, todayUtc());
    await db.persist();
    return projectState(db.exec);
  });
}
```

**`lib/db/mutations.ts`:**

In every transaction-touching case (`addTransaction`,
`updateTransaction`, `deleteTransaction`, `setTransactionSplits`),
collect `{ categoryIds, accountIds, earliestDate }` from the affected
row (before + after for updates) and call `invalidateRollover`.

Helper:
```ts
async function txTouches(exec, id): Promise<{ date, accountId, categoryIds: string[] } | null>
```

### 6. UI

**`components/budget-form-dialog.tsx`:**

- Compute the diff between the form draft and the source `BudgetRow`
  on submit; route to `updateBudgetCycle` vs `updateBudget`
  accordingly.
- Render a small descriptive line above the Save button that mirrors
  the routing decision:
  - "Cycle change applies immediately."
  - "Amount change takes effect on {next-period-label}."
  - default "Save changes."
- Surface the staged pending amount: when `row.pendingAmount != null`,
  show a chip ("$800 starting {next-period-label}") near the amount
  field with a small "Clear pending" button (calls `updateBudget` with
  the original `amount`, which detects the diff as "amount only" and
  stages the prior value — wait, this round-trips back to staging.
  Cleaner: a dedicated `clearPendingAmount` mutation that sets
  `pending_amount = NULL` directly).

**`/budgets/[id]/page.tsx`:**

- Add a "Period" line under the existing window range that uses
  `periodLabel(periodOf(today, ...), ...)` for a human-readable header
  (e.g., "April 2026", "Q2 2026").
- When `row.pendingAmount != null`, show the same staged-amount chip as
  the form.
- When `carryForward > 0`, the existing display already includes it in
  `base`; add a small italic note "(+$X carried forward)".

**`/budgets/page.tsx` (list):**

- Card unchanged structurally. Add a small badge dot on cards with
  `pendingAmount != null` so the list signals staged changes.

### 7. Edge cases

- **One-shot (`is_recurring = 0`):** never rolls, never stages. Amount
  edit takes effect immediately via `updateBudget`. Cycle edit doesn't
  apply (the form should disable the frequency selector for one-shot
  income).
- **Dormant (`start_date > today`):** rollover loop skips.
- **Past `end_date`:** rollover loop skips. The budget shows
  "ended {date}" in the header.
- **`category_ids = []`:** budget matches any tx — `invalidateRollover`
  treats this as "always overlapping".
- **`account_ids = []`:** same.
- **`rollover_limit = NULL`:** uncapped — leftover rolls in full.
- **Backdated cancel:** `deleteTransaction` reads the row before
  cancel; if any covered budget is affected, invalidation runs.
- **Combined edit (cycle + amount + filters):** all routed through
  `updateBudgetCycle`. The cycle path writes amount + frequency +
  start_date in one shot. Filters / name patched in the same mutation
  before the cycle reset.
- **Negative `pending_amount` or zero amount:** mutation-boundary
  validation rejects.
- **`carry_forward` after a backdated edit invalidation:** reset to 0
  alongside `last_rolled_period`; the replay rebuilds it from
  start_date forward.

### 8. Tests

`lib/budgets/period.test.ts` (new):
- `periodOf` for every frequency including year-boundary edge cases.
- `periodRange(periodOf(date)).contains(date)` round-trip.
- Known monthly / quarterly / leap-month bounds.
- Biweekly bucket alignment.
- `nextPeriod` / `prevPeriod` chronological + invertible.

`lib/budgets/rollover.test.ts` (new):
- No-op when nothing's due.
- Single closed period: rollover off → advances marker only.
- Single closed period: rollover on → April leftover becomes May
  carry-forward.
- `rollover_limit` caps the carry-forward.
- Catches up multiple missed periods.
- `pending_amount` activates at the boundary (with rollover both on
  and off).
- `invalidateRollover` resets state for backdated edits affecting a
  rolled period.
- `invalidateRollover` skips edits in periods not yet rolled.
- Filter overlap: empty `categoryIds` is treated as "matches all".
- One-shot budget (`is_recurring = 0`) is skipped entirely.
- Idempotent second call rolls 0.

`lib/db/budgets-entity.test.ts` (extend):
- `updateBudgetCycle` applies immediately, clears `pending_amount`,
  resets `last_rolled_period`, preserves `carry_forward`.
- `updateBudget` with amount-only patch stages to `pending_amount`.
- `updateBudget` with amount + filters patches amount immediately.

`lib/db/mutations.test.ts` (extend):
- Transaction backdated into a rolled period → matching budget's
  `last_rolled_period` reset.
- Transaction in the current period → no invalidation.

---

## Suggested commit split

1. **Schema + period module + tests.** Add the two columns + index to
   the canonical CREATE, bump `SCHEMA_VERSION`, ship
   `lib/budgets/period.ts` with the five exports + the unit test file.
   No behaviour change in the live app.
2. **Rollover module + tests.** Ship `lib/budgets/rollover.ts` with
   `rollBudgetsIfDue` + `invalidateRollover` + the unit test file. Not
   wired into the live app yet.
3. **Mutation routing + cycle/amount split + UI feedback.** Add the
   `updateBudgetCycle` case + the amount-only staging rule in
   `updateBudget`; teach `budget-form-dialog.tsx` to route based on the
   diff; surface the pending-amount chip + period header. Extend
   `budgets-entity.test.ts`.
4. **Wiring + backdated-edit invalidation.** Call `rollBudgetsIfDue` in
   `readState` / `withWrite`; call `invalidateRollover` from the four
   tx mutation handlers. Extend `mutations.test.ts`.

Each commit is independently green.

---

## File touch list

| Path | Status | Change |
|---|---|---|
| `lib/db/schema.ts` | edit | `+ last_rolled_period TEXT`, `+ pending_amount REAL`, `+ idx_budget_last_rolled` index; bump `SCHEMA_VERSION` |
| `lib/budgets/period.ts` | new | `periodOf`, `periodRange`, `nextPeriod`, `prevPeriod`, `periodLabel` |
| `lib/budgets/period.test.ts` | new | Unit tests across every frequency |
| `lib/budgets/rollover.ts` | new | `rollBudgetsIfDue`, `invalidateRollover` |
| `lib/budgets/rollover.test.ts` | new | Catch-up, cap, backdated-edit, idempotency |
| `lib/db/queries/budgets.ts` | edit | `BudgetRow` carries `lastRolledPeriod` + `pendingAmount`; `updateBudget(patch)` stages amount when patch is amount-only; new `updateBudgetCycle(id, patch)` |
| `lib/db/mutations.ts` | edit | `updateBudgetCycle` case; `invalidateRollover` call in the 4 tx cases; `txTouches` helper |
| `lib/db/server.ts` | edit | `readState` / `withWrite` call `rollBudgetsIfDue` |
| `lib/store.ts` | edit | `updateBudgetCycle` store action; expose `pendingAmount` on `BudgetRow` |
| `lib/select.ts` | edit | `budgetProgress` UI display can show pending-amount (no logic change to the active base) |
| `components/budget-form-dialog.tsx` | edit | Detect cycle vs amount-only diff on submit; route accordingly; descriptive text; pending-amount chip + "Clear pending" |
| `app/(main)/budgets/[id]/page.tsx` | edit | Period header (`periodLabel`); pending-amount chip; "+$X carried forward" note when applicable |
| `app/(main)/budgets/page.tsx` | edit | Small badge dot on cards with `pendingAmount != null` |
| `lib/db/budgets-entity.test.ts` | edit | New tests for cycle change + amount staging |
| `lib/db/mutations.test.ts` | edit | New tests for backdated-edit invalidation |
| `plans/BUDGET_CYCLES_PLAN.md` | rewrite | this file |

---

## Out of scope

- ❌ Restoring the legacy per-category amount-map model. The new
  named-budget shape stays.
- ❌ Cycle / rollover on `is_recurring = 0` (one-shot) budgets.
- ❌ Per-account-only or per-tag-only budgets with no category filter
  — the rollover spend SQL already handles these via the category
  filter being empty, but no UI affordance is added in this PR.
- ❌ Historical carry-forward visualisation per period. Only the
  current carry-forward + `last_rolled_period` are stored.
- ❌ Manual "close out this period now" button — the period boundary
  trigger is purely time-based.
