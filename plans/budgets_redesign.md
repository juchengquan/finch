# Budgets redesign — named budgets, groups, cycles, and Goals merge

Status: **proposed** (planning only — no code yet)
Author: design notes for the budgets overhaul
Scope: `frontend/` (server-backed SQLite app) + `plans/` doc updates

---

## 1. Goal of this change

Turn "budgets" from a thin per-category monthly limit into a **first-class,
named budget entity** that the user creates and manages, while folding the
separate **Goals** feature into it as the *income* budget type.

Requested behaviour (verbatim, expanded):

1. **Keep the existing per-category budgets** working for now (shown first on the
   page). They may be removed later — treat them as **legacy**, do not delete.
2. The user can **add a new budget with a name**, tracking **a group of accounts**
   and **a group of categories**.
3. Each budget can be filed into **one group** (exactly like accounts → account
   groups).
4. Each budget has its own **cycle** (period).
5. Budgets have **two types**:
   - **Expense** — the current budget behaviour (spend vs. limit).
   - **Income** — the current **Goals** feature, merged in (progress vs. target).
6. The above needs **DB changes**.

---

## 2. Current state (what exists today)

### 2.1 Data layer — the `budgets` table is already rich

`lib/db/schema.ts` already defines a capable table, but the app only uses a
sliver of it:

```sql
CREATE TABLE budgets (
  id, ledger_id, name,
  type           CHECK(type IN ('income','expense')),
  amount, carry_forward,
  frequency      CHECK(frequency IN ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  start_date, end_date, is_recurring,
  rollover, rollover_limit,
  account_ids, category_ids, tag_ids,   -- JSON-encoded TEXT arrays
  warning_pct, created_at, updated_at
);
```

Today the UI/query layer collapses this to **one row per category**, keyed
`bud-<categoryId>`, and only ever sets `amount` + rollover fields. It is
projected to the client as two **maps**, not entities:

- `lib/db/queries/budgets.ts`: `budgetByCategory()` → `Record<categoryId, amount>`,
  `budgetRolloverByCategory()` → `Record<categoryId, BudgetRolloverInfo>`,
  `setCategoryBudget` / `setCategoryBudgetRollover` / `deleteCategoryBudget`.
- `lib/db/state.ts` projects `budgetByCategory` + `budgetRolloverByCategory`.
- Store actions: `setBudget`, `deleteBudget`, `setBudgetRollover`.
- Mutations (`lib/db/mutations.ts`): `setBudget`, `deleteBudget`, `setBudgetRollover`.

What the schema is **missing** for the redesign:
- No **budget group** concept (no `budget_groups` table, no `budgets.group_id`).
- No **progress accumulator** for income/goal-style budgets (goals' `saved`).

> Note: `accounts` already has an unused `primary_budget_id TEXT` column — a
> pre-existing hook for account↔budget linkage we can ignore for v1.

### 2.2 Goals — a separate, manual feature

`goals` table: `id, ledger_id, name, target, saved, eta (TEXT), hue, sort_order`.
- `lib/db/queries/goals.ts`: `listGoals`, `updateGoal`, `deleteGoal`.
- `createGoal` / `contributeGoal` live in `mutations.ts` (direct SQL).
- Projected as `goals: Goal[]`. UI: `app/(main)/goals/page.tsx` (manual "Add"
  contributions accumulate `saved`; `eta` is free text like "Dec 2026").
- Goals are **not** tied to transactions, accounts, categories, or a cycle.

### 2.3 Frontend budgets pages

- `app/(main)/budgets/page.tsx` — header totals + a flat list of category rows
  (`components/CategoryRow.tsx`), each linking to a detail page.
- `app/(main)/budgets/[id]/page.tsx` — keys off `MOCK.categories` by id; shows a
  ring, spent/limit, edit-budget + rollover dialogs, and matching transactions.

### 2.4 Migration mechanism

`lib/db/schema.ts`:
- Fresh DBs are built from the `CREATE TABLE` statements at `BOOTSTRAP_VERSION`
  (ISO-8601 datetime string); `SCHEMA_VERSION = BOOTSTRAP_VERSION`.
- Existing DBs run `MIGRATIONS: Record<datetime, string[]>` — every key strictly
  greater than the stored `schema_version`, applied in lexicographic (=chrono)
  order, recorded in `db_metadata`.
- **To ship a schema change:** (a) edit the `CREATE TABLE` statements so new DBs
  are born correct, (b) add a `MIGRATIONS['<new-datetime>']` entry of `ALTER`/
  `CREATE`/`INSERT` SQL for existing DBs, (c) bump `BOOTSTRAP_VERSION` &
  `SCHEMA_VERSION` to that datetime. Keep migration SQL idempotent
  (`IF NOT EXISTS`, guarded inserts). SQLite `ALTER TABLE ADD COLUMN` allows a
  nullable `... REFERENCES ...` FK and `NOT NULL DEFAULT <const>`.

---

## 3. Target model

### 3.1 A "budget" becomes an entity

A budget is a named tracker with:

| Field | Meaning |
|-------|---------|
| `name` | User label (e.g. "Groceries", "Salary", "New car"). |
| `type` | `expense` (spend vs limit) or `income` (progress vs target — the old Goals). |
| `group_id` | One budget group (nullable → "Ungrouped"). Mirrors accounts. |
| `amount` | The limit (expense) or target (income/goal). |
| `frequency` + `start_date` + `end_date` + `is_recurring` | The **cycle**. |
| `account_ids[]` | Accounts this budget watches (empty = all accounts). |
| `category_ids[]` | Categories this budget watches (empty = all categories). |
| `rollover` / `rollover_limit` / `carry_forward` | Unused-budget carry (expense). |
| `saved` *(new)* | Manual progress accumulator for income/goal budgets. |
| `warning_pct` | Threshold for the "near limit" warning chip. |

### 3.2 Cycle semantics

A budget's **current period** = `cycleWindow(frequency, start_date, today)`:
the `[from, to]` date range of the active cycle. `monthly`/`weekly`/etc. roll
forward from `start_date`. Non-recurring budgets (`is_recurring = 0`, e.g. a
savings goal with an `end_date`) have a single open window `[start_date,
end_date]`.

### 3.3 Spend / earn matching

A confirmed, non-transfer, non-adjustment transaction counts toward a budget
when **all** of:
- its `date` ∈ the budget's current cycle window, **and**
- (`account_ids` empty **or** `tx.account` ∈ `account_ids`), **and**
- (`category_ids` empty **or** `tx.category` ∈ `category_ids` — honour splits like
  `categorySpend` does), **and**
- sign matches type: `expense` → outflow (`amount < 0`); `income` → inflow
  (`amount > 0`).

Progress:
- **Expense:** `spent = Σ |matched outflow|`; remaining = `amount + carry_forward − spent`.
- **Income (transaction-driven):** `earned = Σ matched inflow`.
- **Income (manual / goal):** `saved` accumulator (old Goals behaviour). The two
  income modes are reconciled in **Decision D2** below.

---

## 4. Schema changes (DB)

New migration key, e.g. `MIGRATIONS['2026-06-01T00:00:00Z']` (pick the real ship
datetime), plus matching edits to the bootstrap `CREATE TABLE`s.

### 4.1 New table: `budget_groups` (mirror of `account_groups`)

```sql
CREATE TABLE IF NOT EXISTS budget_groups (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_budget_groups_ledger ON budget_groups(ledger_id);
```

### 4.2 Alter `budgets`

```sql
ALTER TABLE budgets ADD COLUMN group_id TEXT REFERENCES budget_groups(id) ON DELETE SET NULL;
ALTER TABLE budgets ADD COLUMN saved    REAL NOT NULL DEFAULT 0;   -- income/goal progress
```

(Add the same two columns to the bootstrap `CREATE TABLE budgets` so fresh DBs
match.)

### 4.3 Data migration: Goals → income budgets

For every `goals` row, insert a `budgets` row:

```sql
INSERT INTO budgets (id, ledger_id, name, type, amount, saved, carry_forward,
                     frequency, start_date, end_date, is_recurring,
                     rollover, account_ids, category_ids, tag_ids,
                     warning_pct, created_at, updated_at)
SELECT 'bud-goal-' || g.id, g.ledger_id, g.name, 'income', g.target, g.saved, 0,
       'monthly', date('now'), NULL, 0,            -- one-shot goal: is_recurring = 0
       0, NULL, NULL, NULL, 80, datetime('now'), datetime('now')
FROM goals g
WHERE NOT EXISTS (SELECT 1 FROM budgets b WHERE b.id = 'bud-goal-' || g.id);
```

- `eta` (free text like "Dec 2026") can't be mapped cleanly to `end_date`; store
  it best-effort or drop it (see **Decision D3**).
- **Keep the `goals` table intact** (legacy, read path turned off) so the change
  is reversible; remove in a later cleanup migration once the income-budget UI is
  trusted. This mirrors the "keep category budgets first" instruction.

### 4.4 Legacy category budgets

No schema change. The existing `bud-<categoryId>` rows keep working through the
existing `budgetByCategory` projection. New named budgets get their own ids
(`bud-<rand>`), so the two coexist without collision.

---

## 5. Query / projection / store changes

### 5.1 New queries — `lib/db/queries/budgets.ts`

Add the **entity** API alongside the existing legacy map functions:

```ts
export interface BudgetRow {
  id; ledgerId; name; type: 'expense' | 'income';
  groupId: string | null;
  amount: number; saved: number; carryForward: number;
  frequency; startDate; endDate: string | null; isRecurring: number;
  rollover: number; rolloverLimit: number | null;
  accountIds: string[]; categoryIds: string[]; tagIds: string[];
  warningPct: number;
}
listBudgets(exec, ledgerId?) : BudgetRow[]      // parse JSON arrays, skip legacy bud-<catId>? see D1
createBudget(exec, input)                        // serialise arrays to JSON TEXT
updateBudget(exec, id, patch)
deleteBudget(exec, id)
contributeBudget(exec, id, amount)               // income/goal: saved += amount
```

> **Decision D1 — how to separate legacy vs named budgets in the same table.**
> Options: (a) filter by id prefix (`bud-` legacy single-category vs `budx-` new);
> (b) add a boolean column `is_named`/`managed`; (c) treat any row with a `name`
> as named (legacy category rows have `name = NULL`). **Recommended: (c)** —
> `listBudgets` returns rows with a non-null `name`; the legacy `budgetByCategory`
> functions keep selecting the `name IS NULL` rows. Zero new columns, clean split.

### 5.2 New queries — `lib/db/queries/budgetGroups.ts`

Copy `accountGroups.ts` almost verbatim: `BudgetGroupRow`, `listBudgetGroups`,
`createBudgetGroup`, `updateBudgetGroup`, `deleteBudgetGroup` (delete sets
`budgets.group_id = NULL`).

### 5.3 Projection — `lib/db/state.ts` + `lib/db/repo.ts`

Add to `projectState` and `ProjectedState`:
- `budgets: BudgetRow[]`
- `budgetGroups: BudgetGroupRow[]`

Keep `budgetByCategory` / `budgetRolloverByCategory` (legacy) and `goals` (legacy,
until removed) so nothing breaks mid-migration.

### 5.4 Mutations — `lib/db/mutations.ts`

Add cases: `createBudget`, `updateBudget`, `deleteBudget` (named — careful not to
clash with the legacy category `deleteBudget`; rename legacy to
`deleteCategoryBudget` at the action layer or namespace the new ones, e.g.
`createNamedBudget`), `contributeBudget`, `createBudgetGroup`,
`updateBudgetGroup`, `deleteBudgetGroup`.

> **Naming caution:** the store/mutations already expose `deleteBudget`
> (category). Use distinct action names for the entity API to avoid ambiguity —
> suggested: `createBudget`, `updateBudget`, `removeBudget`, `contributeBudget`,
> `createBudgetGroup`, `updateBudgetGroup`, `deleteBudgetGroup`.

### 5.5 Store — `lib/store.ts`

- New state: `budgets: BudgetRow[]`, `budgetGroups: BudgetGroupRow[]`.
- New actions mirroring §5.4 (optimistic update + `syncMutation`). Follow the
  existing account-group action shape for groups.

### 5.6 Selectors — `lib/select.ts`

- `cycleWindow(frequency, startDate, today, endDate?, isRecurring?) → { from, to }`.
- `budgetProgress(budget, txns) → { spent | earned, base, remaining, pct, over }`
  using §3.3 matching (reuse the split-aware logic from `categorySpend`).
- Helper to resolve a budget's accounts/categories to display chips.

---

## 6. Frontend changes

### 6.1 Budgets list — `app/(main)/budgets/page.tsx`

Redesign into sections:
1. **Named budgets, grouped** — an accordion by budget group (reuse the
   `Accordion` + group pattern from `app/(main)/accounts/page.tsx`, including the
   group "⋯" menu and the `action` slot on `AccordionTrigger`). Each budget row
   shows name, type badge (Expense/Income), cycle, progress bar/ring, and
   spent/limit or earned/target. Expense and income can be two top-level tabs or
   two sub-sections (**Decision D4**).
2. **Categories (legacy)** — keep the current category list, clearly labelled
   "Categories" and shown **first or last** per the user's "keep them first"
   note (recommend a labelled legacy section, collapsible).
3. **"New budget"** entry (header `+` menu, like Accounts' New account / New
   group) → opens the create dialog; plus **"New group"**.

### 6.2 Create / edit budget dialog (new component)

Fields: name; type (Expense/Income toggle); group (select, + create-new); cycle
(frequency select + start date; for income/goal allow non-recurring + target
date); amount/target; **accounts multi-select**; **categories multi-select**;
expense-only rollover toggle + cap. Use existing `Select`, `Dialog`, `Input`,
and a multi-select (build a small chip multi-select or reuse a popover+checkbox
list).

### 6.3 Budget detail — `app/(main)/budgets/[id]/page.tsx`

Branch on id:
- **Named budget** (`name != null`): show entity detail — progress ring, cycle
  window, account/category chips, matched transactions in the window, edit/delete,
  and (income) a "Contribute" action.
- **Legacy category** (existing behaviour): unchanged.

Update `BREADCRUMB_SECTIONS` in `PageShell.tsx` (`budgets` crumb) to resolve a
named budget's display name (currently uses `catById`).

### 6.4 Goals → income budgets (RESOLVED: full merge, no Goals sub-page)

Goals are folded entirely into the Budgets **Income tab** — there is **no
standalone Goals page** afterward.

- **Remove** `app/(main)/goals/page.tsx` as a real screen. Replace
  `/goals` with a **redirect** to `/budgets` (Income tab) so old links/bookmarks
  still resolve — a redirect, not a sub-page (matches the `/settings` →
  `/settings/account` redirect pattern we just shipped).
- **Drop the "Goals" nav entry** from `MAIN_TAB_CATALOG` (`mobile-tabs.ts`),
  `DEFAULT_MOBILE_TAB_IDS` if present, `app/(main)/layout.tsx`, and the command
  palette `PAGES` (`components/command-palette.tsx`). Income budgets are reached
  via Budgets → Income.
- The goal CRUD/contribute actions move to the budget entity API
  (`createBudget` w/ `type='income'`, `contributeBudget`); the legacy `goals`
  store actions/projection are retired once the income UI is trusted (phase 6).

### 6.5 Money formatting

Reuse `useMoney().fmt` (full) — consistent with the recent budgets "show full
amounts" change. `CategoryRow` stays for the legacy section.

---

## 7. Decisions

Resolved (locked):

- **D2 — income progress model: HYBRID.** One-shot goals (`is_recurring = 0`) use
  a manual `saved` accumulator (old Goals behaviour, "Contribute" button);
  recurring income budgets (`is_recurring = 1`) auto-track matching income
  transactions in the cycle. The detail UI shows whichever applies.
- **D4 — list layout: TABS.** Two top tabs — **Expense / Income** — each showing
  that type's budgets grouped by budget group. Mirrors Settings Account/Ledger.
- **D5 — Goals route: FULL MERGE, no sub-page.** Remove the Goals screen; `/goals`
  becomes a redirect to `/budgets` (Income tab); drop the Goals nav entry. See
  §6.4.

Still open (recommendations stand; confirm during build):

- **D1 — legacy vs named split:** recommend "named = `name IS NOT NULL`" (§5.1).
- **D3 — goal `eta`:** drop the free-text eta, or parse best-effort into
  `end_date`? Recommend storing nothing structured in v1.
- **D6 — match overlap:** if a transaction matches multiple budgets, it counts
  toward each independently (no exclusivity). Confirm that's acceptable.

---

## 8. Suggested phasing (each phase ships green: typecheck + lint + build)

1. **Schema + migration** — `budget_groups`, `budgets.group_id` + `saved`, goals→
   income-budget data migration; bump versions. No UI yet. Verify projection.
2. **Query/projection/store/mutations** — entity + group APIs; `budgets` &
   `budgetGroups` in `ProjectedState`; selectors (`cycleWindow`,
   `budgetProgress`). Unit tests in `lib/*.test.ts`.
3. **Budgets list redesign** — grouped named budgets + legacy category section +
   create/edit dialog + groups CRUD.
4. **Budget detail redesign** — entity detail w/ branching; breadcrumb fix.
5. **Goals merge** — income budgets surfaced; `/goals` becomes the income view;
   nav/labels updated.
6. **Cleanup (later)** — once trusted: remove legacy category-budget UI and/or the
   `goals` table via a follow-up migration.

## 9. File-by-file checklist

- `lib/db/schema.ts` — bootstrap `CREATE TABLE budget_groups`; add `group_id`,
  `saved` to `budgets`; `MIGRATIONS` entry + version bump; goals→budgets INSERT.
- `lib/db/queries/budgets.ts` — `BudgetRow`, `listBudgets`, `createBudget`,
  `updateBudget`, `deleteBudget`, `contributeBudget` (keep legacy fns).
- `lib/db/queries/budgetGroups.ts` — new (copy `accountGroups.ts`).
- `lib/db/state.ts` — project `budgets`, `budgetGroups`.
- `lib/db/repo.ts` — extend `ProjectedState`.
- `lib/db/mutations.ts` — entity + group action cases (distinct names).
- `lib/store.ts` — state + actions.
- `lib/select.ts` — `cycleWindow`, `budgetProgress`, chip resolvers (+ tests).
- `app/(main)/budgets/page.tsx` — grouped list + legacy section + create entry.
- `app/(main)/budgets/[id]/page.tsx` — entity vs legacy branch.
- `components/` — new `BudgetCreateDialog`, budget-group accordion bits, maybe a
  multi-select; reuse `Accordion`, `CategoryRow` (legacy).
- `app/(main)/goals/page.tsx` + nav (`mobile-tabs.ts`, `app/(main)/layout.tsx`,
  `components/command-palette.tsx`) — income view / relabel.
- `components/PageShell.tsx` — `BREADCRUMB_SECTIONS.budgets` resolves named budgets.
- `plans/database_design_en.md` — document the new `budget_groups` table, the new
  `budgets` columns, and the Goals deprecation.
- `plans/MASTER_PLAN.md` — log the redesign.

---

## 10. Risks / notes

- **Action-name collision** on `deleteBudget` (legacy category vs entity) — use
  distinct names (§5.4).
- **JSON array columns** (`account_ids` etc.) are TEXT; always parse/serialise at
  the query boundary and tolerate `NULL`/malformed (sanitize like
  `mobile-tabs.ts` does for stored ids).
- **Cycle math** is the trickiest part — cover `cycleWindow` with unit tests
  across each frequency and around month/year boundaries before wiring the UI.
- **Reversibility** — keep `goals` and legacy category budgets until the new UI is
  trusted; the only destructive step (dropping them) is deferred to phase 6.
