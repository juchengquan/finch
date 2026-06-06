# Conditional rules engine — scoping plan

Status: **shipped** (PRs #91, #94) — `rules` table + types + query layer, and the
engine hooked into `insertTxRow`. This doc is kept as the design record.

Today finch has two narrow categorisation aids: the **counterparty FK + verify**
loop on Pending (a rename) and the **local-heuristic category suggestion** on
the Add form (PR #73, reactive only). Neither expresses "the same merchant is
two different categories depending on basket size", neither applies retroactively,
and neither captures multi-step actions (add tag + split + rename in one rule).

A rules engine is the smallest abstraction that covers all of that and unlocks
four queued ideas (`INSPIRATION_IDEAS.md` §4.2 find recurring, §4.3 payee-merge
→ rule, §4.4 auto-split on income, §7.4 inline "create rule" prompt). It's a
deterministic decision table — boringly auditable, no model, no network.

## 0. Confirmed product decisions

Decided going in — anything else is an open question (§6).

1. **No LLM, no cloud.** Conditions are a small JSON-encoded boolean tree
   compiled to JS at runtime. No external service is called at any point.
2. **Pure on the read path.** Rule evaluation is a pure function over a
   `Tx` and the rule set; the same input always yields the same patch.
   Storage of the rule set is the only side effect — evaluation isn't.
3. **One rule, multiple actions.** A single rule can set the category,
   add tags, set a counterparty, mark needs-review off, and split the
   transaction in one go. Avoids the N-rule combinatorial mess Lunch
   Money and Monarch users complain about.
4. **Priority is explicit.** Rules apply in priority order; later
   rules can override earlier ones. The UI shows the chain so a user
   can debug "why did this end up in Snacks?".
5. **Runs at insert AND on demand.** Auto-applies during the
   transaction-insert path so new rows arrive pre-categorised; a "Run
   rules on existing transactions" button replays the entire ruleset
   against history, with a preview-then-apply confirmation step.

## 1. What changes vs. what doesn't

| Layer | Changes? |
|---|---|
| Schema | New `rules` table; one column added to `transactions` (see §5). |
| Insert pipeline | `insertTxRow` (the consolidated helper from PR #70) calls `applyRules` after building the row, before writing. |
| Read path | Nothing changes. Rules write into the existing columns. |
| Existing UIs | Add form, Pending matcher, transaction detail all keep working; the user just sees fewer manual edits. |
| New UIs | `/rules` page (list + edit + reorder), inline "create rule" prompt after a manual edit. |

## 2. Data model

### 2.1 The `rules` table

```sql
CREATE TABLE rules (
  id           TEXT PRIMARY KEY,
  ledger_id    TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name         TEXT,                          -- optional human label
  priority     INTEGER NOT NULL DEFAULT 100,  -- lower runs first
  condition    TEXT NOT NULL,                 -- JSON: condition tree (see §3)
  actions      TEXT NOT NULL,                 -- JSON: ordered actions (see §4)
  is_active    INTEGER NOT NULL DEFAULT 1,
  last_applied_at TEXT,                       -- for "ran on backfill" UI
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
CREATE INDEX idx_rules_ledger_active ON rules(ledger_id, is_active);
```

### 2.2 The transactions hook

Add **one** column to `transactions`:

```sql
ALTER TABLE transactions ADD COLUMN applied_rule_ids TEXT;  -- JSON array of rule ids
```

When `applyRules` modifies a row, the matching rule ids land here. This
makes "why did X become Groceries?" answerable directly from the row,
and the `/rules` page can show "applied to 247 transactions". Optional;
the engine works without it, this is just observability.

## 3. Condition language

A condition is a recursive JSON tree of **leaf comparators** glued
together with `{ all: [...] }` (AND) or `{ any: [...] }` (OR):

```ts
type Condition =
  | { all: Condition[] }
  | { any: Condition[] }
  | { not: Condition }
  | Leaf;

type Leaf =
  | { field: 'merchant';      op: 'is' | 'contains' | 'startsWith' | 'matches'; value: string }
  | { field: 'amount';        op: 'gt' | 'gte' | 'lt' | 'lte' | 'eq' | 'between'; value: number | [number, number] }
  | { field: 'account_id';    op: 'is' | 'in'; value: string | string[] }
  | { field: 'category_id';   op: 'is' | 'in' | 'is_null'; value?: string | string[] }
  | { field: 'counterparty_id'; op: 'is' | 'is_null'; value?: string }
  | { field: 'currency';      op: 'is'; value: string }
  | { field: 'date_dow';      op: 'in'; value: number[] }                  // 0=Sun..6=Sat
  | { field: 'date_dom';      op: 'eq' | 'gte' | 'lte'; value: number }    // day of month
  | { field: 'kind';          op: 'is' | 'in'; value: TxKind | TxKind[] }
  | { field: 'tag_id';        op: 'has' | 'has_any' | 'has_all'; value: string | string[] }
  | { field: 'note';          op: 'contains' | 'matches'; value: string };
```

- `merchant.matches` is a **safe substring match** with optional
  case-folding flag; we do not expose raw regex (escape hatch for later).
- All amount comparisons use **native** amount (the same currency as
  the account), not amount_base — users think about price in the
  currency they paid in.
- `date_dow` and `date_dom` derive cheaply from `t.date`; no extra
  columns needed.

### Worked examples

```json
// "Shell under $10 → Snacks"
{ "all": [
  { "field": "merchant", "op": "contains", "value": "shell" },
  { "field": "amount", "op": "lt", "value": 10 }
] }
```

```json
// "Whole Foods on a Saturday → tag 'date night'"
{ "all": [
  { "field": "merchant", "op": "contains", "value": "whole foods" },
  { "field": "date_dow", "op": "in", "value": [6] }
] }
```

```json
// "Apple paid with my Visa AND amount > $100"
{ "all": [
  { "field": "merchant", "op": "contains", "value": "apple" },
  { "field": "account_id", "op": "is", "value": "visa-personal" },
  { "field": "amount", "op": "gt", "value": 100 }
] }
```

## 4. Action language

An ordered array of patches. Each action applies in order; later
actions see the results of earlier ones (so you can split first, then
tag the parent).

```ts
type Action =
  | { set: 'category_id';    value: string | null }
  | { set: 'counterparty_id'; value: string | null }
  | { set: 'merchant';       value: string }                  // canonical rename
  | { set: 'note';           value: string }
  | { set: 'kind';           value: TxKind }
  | { tag_add';              tag_id: string }
  | { tag_remove';           tag_id: string }
  | { mark_reviewed: true }
  | { split: SplitTemplate[] };                               // per-split fractions

type SplitTemplate = {
  /** Fraction of the parent amount (0..1). Must sum to 1 across the array. */
  fraction: number;
  category_id: string | null;
  description?: string;
};
```

`split` is the most powerful action: a $200 Target run can auto-split
into 60% Groceries / 40% Household. Sum-to-one validation is the same
rule the existing Split UI enforces.

## 5. Engine implementation

```ts
// lib/rules/engine.ts
export interface RulePatch {
  category_id?: string | null;
  counterparty_id?: string | null;
  merchant?: string;
  note?: string;
  kind?: TxKind;
  tag_ids_add?: string[];
  tag_ids_remove?: string[];
  reviewed?: boolean;
  splits?: SplitTemplate[];
  applied_rule_ids: string[];
}

export function evaluateCondition(tx: Tx, cond: Condition): boolean;
export function applyRules(tx: Tx, rules: Rule[]): RulePatch;
```

- `applyRules` iterates the active rule set in priority order, OR-ing
  every matching rule's `actions` array into a merged patch. The merged
  patch is what `insertTxRow` consumes.
- For conflicts (two rules set category), **later priority wins**; the
  losing rule still goes into `applied_rule_ids` so it's traceable.
- Splits are mutually exclusive — first matching `split` action wins,
  subsequent ones are ignored (and noted in `applied_rule_ids`).

### Where it hooks in

1. **Insert (`insertTxRow`)** — after building the new row, call
   `applyRules`; merge the patch into the row before the INSERT runs.
   Single SQL roundtrip.
2. **Manual backfill (`backfillRule(ruleId)`)** — a new mutation that
   loads every transaction in the rule's ledger, runs only that rule
   against each, and updates the matching subset in a single SQL
   batch. Preview returns the count + a sample of 10 affected rows
   before the user commits.
3. **Bulk replay (`replayRules()`)** — same as #2 but for every active
   rule. Hidden behind a confirm; intended for "I just imported 500
   rows from CSV, sort them".

## 6. UI surfaces

### `/rules` page (new)

- List of rules grouped by ledger, draggable to reorder priority.
- Per row: name · condition summary ("Shell under $10") · actions
  summary ("→ Snacks · tag Snacks") · enabled toggle · ⋯ menu (edit /
  duplicate / delete / "Apply to existing").
- "+ New rule" opens a sheet with the condition builder + action picker.

### Condition builder

- Top-level AND/OR group with a `+ Condition` button.
- Each leaf is a `field` select → `op` select → `value` input. Value
  input type adapts (number for amount; date-DOW chips for `date_dow`;
  account picker for `account_id`).
- "Test" panel beside the builder: against the last 100 transactions,
  show count of matches + the first three.

### Action picker

- Stacked rows: pick action kind from a dropdown → fill in the
  parameters. Split has its own composer (fractions sum to 100%).

### Inline "create rule" prompt (in scope; ships with the engine)

- When the user manually recategorizes a row, a small non-blocking pill
  appears at the top of the detail sheet: "Always categorize {Merchant}
  as {Category}?" → one tap promotes the edit into a rule with
  `merchant.contains` + `set category_id`. Builds the same `Condition` +
  `Action` shape; user can refine before saving.

## 7. Shipping order

Each step is independently mergeable:

1. **Schema + types** — `rules` table, `applied_rule_ids` column,
   migration. `Rule` / `Condition` / `Action` types in `lib/rules/`.
   Tests: schema shape + null defaults.
2. **Pure engine** — `evaluateCondition` + `applyRules` in
   `lib/rules/engine.ts`. Tests against ~30 canonical cases (each leaf
   comparator, AND/OR/NOT nesting, conflict resolution, splits).
   *No UI yet.*
3. **Hook into insert** — `insertTxRow` calls `applyRules` and merges
   the patch. Tests: a new tx with a matching rule lands with the right
   category + tags + applied_rule_ids.
4. **`/rules` page (read-only)** — list + view rules; no edit. Useful
   for early dogfooding (the user hand-edits a row in the DB to test).
5. **Rule builder UI** — condition + action editors, test panel.
6. **Backfill mutation + UI** — "Apply to existing" with preview.
7. **Inline "create rule" prompt** — quick win once the schema is in.
8. **Find-recurring scanner** (`INSPIRATION_IDEAS.md` §4.2) — pure
   selector over txns proposes rules the user accepts. Builds on this
   foundation.

PR slice that maximises early value: **1+2+3** ship together so the
engine works against the existing DB even without a UI. **4-7** in a
follow-up PR. Find-recurring is its own PR.

## 8. Open questions

The shape above commits to the easy decisions; these are the ones the
user should weigh in on:

1. **Per-ledger or global rules?** Current proposal: per-ledger
   (`ledger_id` FK). Alternative: a `null` ledger_id for "applies
   everywhere". Most other apps go per-ledger; users with separate
   personal vs business ledgers don't want cross-pollination.
2. **Rule ordering UI: priority numbers or drag-to-reorder?** Drag is
   nicer but ties priority semantics to position. Numbers let users
   leave gaps ("100, 200, 300" so an inserted rule between 100 and 200
   doesn't shift). Recommendation: drag, with priority computed at save
   time.
3. **Backfill safety net?** The "Apply to existing" button can touch
   thousands of rows. Wrap in a single SQL transaction so it's
   atomic? Show a one-line undo in a toast? Both?
4. **Should rules fire on edited transactions, not just inserts?**
   If I rename "WHOLEFDS" to "Whole Foods", should rules that match
   "Whole Foods" auto-apply? Lunch Money says yes. Risk: a typo in an
   edit re-triggers a chain. Recommendation: yes by default, with a
   per-rule "only on insert" flag for the cautious.
5. **Rule import/export?** Lets users share rule sets across ledgers
   (personal + family). Out of scope for v1; a JSON blob in
   `app_state` if it's ever asked for.

## 9. Out of scope

These are explicitly NOT in v1; they're easier to add later than to
remove:

- **Regex in `merchant.matches`** — adds escape semantics + DoS risk.
  Keep substring matching only; the few power users can wait.
- **Time-based conditions** (hour-of-day, etc.) — `t.time` is optional
  and inconsistently populated; not worth the complexity yet.
- **Cross-transaction conditions** ("if total Groceries this month >
  $500") — needs aggregation, breaks pure-function semantics. Belongs
  in the insights engine, not the rules engine.
- **Notifications on match** — once a rule fires, the only feedback is
  the changed row. Push/digest comes with the PWA work.
- **Conflict warnings** during rule editing — "this rule overlaps with
  rule #7, last one wins". Nice-to-have, but the priority list already
  makes the resolution obvious.

## 10. Acceptance criteria

For the engine itself (PRs 1-3):

- `bun test lib/rules/*` covers every comparator + AND/OR/NOT and the
  conflict-resolution rules.
- A transaction insert with a matching rule lands with the right
  category, tags, and `applied_rule_ids`, with no extra SQL roundtrip.
- Backfilling a single rule against 1000 seeded transactions completes
  in <250ms on the dev DB.
- The Pending matcher and the Add form keep working unchanged.

For the UI (PRs 4-7):

- A user can build a rule from scratch in <30 seconds for the canonical
  "Shell under $10 → Snacks" example.
- The "Test" panel surfaces the match count before the user commits.
- Deleting a rule offers a one-tap "also revert affected rows" option.
