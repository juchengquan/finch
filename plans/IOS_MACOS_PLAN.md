# finch for iOS & macOS — product & architecture direction

> **Status: direction brief — NOT an implementation plan.**
>
> This document does **not** tell anyone "create this file, write that
> function, in this order." It is the layer *above* that: it defines **what the
> native apps must do** (functional requirements) and **the direction the
> implementation should take** (architecture choices, trade-offs, and
> recommendations). A future team uses it to write their own detailed
> functional specs and to make build decisions with the rationale already
> mapped out.
>
> Requirement strength uses RFC-2119 words: **MUST** / **SHOULD** / **MAY**.
> Architecture guidance is marked **Direction:** and always presents the
> option(s), the trade-off, and a recommendation — the recommendation is a
> default to argue *against*, not a mandate.

_Audience: the engineers and designers who will build finch's native Apple
apps. Assumes familiarity with the web app in `frontend/` and the design
record in `plans/`. Last updated: 2026-06-12._

> **What changed since the 2026-06-07 revision:**
>
> - 3-level categories shipped (PR #112) — see prior revision.
> - i18n shipped (PRs #113 + #115) — see prior revision.
> - Double-entry storage migration shipped (PRs #114 + #116) — see prior revision.
> - **DB layer refactored into `core/` + `domain/` + `queries/` (PRs #124-#129)** — the write chokepoint + checksum + entries-schema + pack + paths + repo + schema + sealed-entry + server + storage + seed all live under `frontend/lib/db/core/`; user-facing actions are now 14 per-domain files under `frontend/lib/db/domain/<x>/{mutations,queries,types,errors}.ts`; reads are exposed via thin re-export shims under `frontend/lib/db/queries/<x>.ts`; everything routes through the 53-line `frontend/lib/db/mutate.ts` dispatcher. The DE cutover that used to live in `lib/db/cutover.ts` is inlined into the `MIGRATIONS` entry stamped `2026-06-14T00:00:00Z` inside `lib/db/core/entries.ts`. The `lib/db/mutations.ts` file is gone — replaced by per-domain `mutations.ts` files. Architecture intent and interop contract are unchanged. §2.1 code-reference table, §4.6 cutover path, §4.9 chokepoint path, §8 cross-app implications, and the canonical-references glossary all updated.
> - **Frontend refactored: typed icons + per-domain store + split shells + primitive consolidation + post-refactor cleanup + doc sweep + final cleanup + pre-existing fixes (PRs #130-#138)** — typed `lucide-react` barrel at `components/icons.tsx`; zustand store split into 14 per-domain slices at `lib/store/<x>/{state,actions}.ts` wired by `lib/store/index.ts`; `PageShell.tsx` is now a 21-line dispatcher that renders once and switches chrome by CSS (sidebar on `md+`, bottom bar below); 12 promoted primitives consolidated into `components/ui/` + `components/primitives.tsx`; `components/MobileComponents.tsx` deleted (its content moved to `components/mobile-page.tsx`); `components/currency-provider.tsx` renamed to `components/use-currency.ts` (exports the `useCurrency` hook + `Currency` type). 534/0 tests preserved; no behavior change. §3 row 37 (responsive shell) and §4.1 architecture-direction prose updated to reflect the dispatcher pattern.
>
> Cross-app interop is unchanged by all of the above — the `.finch` pack format and the shared `SCHEMA_VERSION` lineage are the contract (§8).

---

## 0. How to use this document

1. **Treat §2 (the domain model) as inherited, not negotiable.** finch already
   has a complete, tested relational schema and a complete set of pure
   financial derivations. The native apps re-express that model on Apple
   platforms; they do not redesign it. The canonical sources of truth are the
   files named throughout — read them before writing the matching Swift spec.
2. **Turn §3 (the parity matrix) into per-feature requirement docs.** Each row
   is the seed of a feature spec. The "native direction" column is guidance,
   not the spec — flesh each into acceptance criteria.
3. **Resolve the §4 architecture decisions first.** They gate everything else
   (especially the sync model in §4.3 and the money type in §4.5). Pick, record
   the decision, and move the open question to "resolved."
4. **Keep parity honest.** The web app's `bun test lib` suite (≈400 tests over
   `lib/`) is the behavioural oracle. Anywhere this doc says "port a selector,"
   it also means "port its tests" (§12).

---

## 1. Product vision & first principles

finch is a **single-user / single-household personal finance ledger** with an
editorial, un-corporate aesthetic. The native apps inherit its DNA:

- **Local-first, no mandatory cloud.** The web app's authoritative store is a
  single SQLite file; "backup = copy the file, sync = export/import the file."
  The native apps MUST work fully offline with no account and no server. (This
  is a sharper version of the same instinct that produced `PWA_PLAN.md`.)
- **Deterministic, model-free intelligence.** Every "smart" feature
  (categorisation suggestions, anomaly flags, spending-pattern insights,
  forecasts, the rules engine) is a *pure function over the user's own data*.
  No LLM, no network calls, no telemetry. The native apps MUST preserve this —
  it is a privacy guarantee, not just an implementation detail.
- **Money is sacred and easy to get wrong.** Dual amount storage, locked FX
  rates, per-ledger base currency, per-ledger display currency. §4.5 and §2.3
  are the load-bearing sections; read them twice.
- **Editorial warmth over banking sterility.** Warm "paper" light theme, "noir"
  dark theme, generous whitespace, large display numerals (§5).
- **Each release is a working, verifiable build.** Mirror the web app's
  discipline: a green test/lint/build gate per increment (§12).

### 1.1 Why native, and why now

`PWA_PLAN.md §8` explicitly listed "native wrappers (Capacitor, Tauri)" as a
non-goal because a PWA was "good enough" for install-to-home-screen. **This
document supersedes that judgement on purpose.** The reason to build *truly
native* (not a wrapper) is the platform surface a web view cannot reach and
which maps almost 1:1 onto features finch already has (§7): App Intents/Siri
for "add expense," Home/Lock-Screen widgets for budgets and net worth, a Share
Extension for receipts, biometric lock, Spotlight, Handoff, a real macOS menu
bar and keyboard model, and Apple-grade accessibility. A wrapper gets none of
these well. **Direction: build native (SwiftUI), not a wrapped web view.**

The same native posture unlocks the sync model the product wants —
periodic zip "packs" of the database + receipt attachments dropped into
**iCloud Drive** (§4.3 + §2.5.3) — which a web view can only approximate.

> **DE note:** the double-entry storage migration (PRs #114 + #116,
> `plans/done/DOUBLE_ENTRY_PLAN.md`) doesn't change the cross-app interop
> contract — the `.finch` pack still carries a SQLite DB on the shared
> `SCHEMA_VERSION` lineage; the canonical tables inside are `entries` /
> `postings` / `entry_tags` / `entry_attachments` instead of the legacy
> `transactions` / `transfer_groups` / `transaction_splits` /
> `transaction_tags` / `transaction_attachments` trio. Migrations run when
> a swapped-in file is opened (§4.6), so pre-DE packs still import.
> Native inherits the DE-era schema as canonical; §2 is rewritten storage-
> first to reflect it.

---

## 2. The domain model you are inheriting (the real spec)

This is the most valuable thing the native team is handed. Do not paraphrase it
from screenshots — read the source.

| Concern | Canonical source in `frontend/` | What it is |
|---|---|---|
| Relational schema (tables, indexes, triggers, FTS5) | `lib/db/schema.ts` (canonical; DE additions folded in) + `lib/db/core/entries-schema.ts` (PR-A standalone, kept as a historical reference) | The full `CREATE …` SQL string + the version/migration runner; under DE the entries/postings tables + the seal/posting/balance triggers live here |
| Schema rationale & business rules | `plans/database_design_en.md` + `plans/done/DOUBLE_ENTRY_PLAN.md` | The design doc behind the schema (decisions #18–#25 etc.) + the double-entry rewrite (§2-§3 invariants, §8 migration) |
| Server projection contract (the `Tx` shape) | `lib/db/state.ts` (`projectState`) | The exact `Tx` / `AccountRow` shape the client consumes — see §2.6 |
| **Write chokepoint** | `lib/db/core/entries.ts` | The single write path: `postEntry` / `rebuildEntry` / `deleteEntry` / `resolveEntryRef` / `auditLedger` / `ensureSystemCategories` + the `MIGRATIONS` array + `applyMigrations` runner — see §4.9 |
| **Cutover (the migration)** | `lib/db/core/entries.ts` (`MIGRATIONS` entry stamped `2026-06-14T00:00:00Z`) + `lib/db/core/sealed-entry.ts` (per-entry sealed-write helper) | The DOUBLE_ENTRY_PLAN §8.2 data-move builder: manual sealed inserts for id-fidelity, torn-write repair, per-entry idempotence guard. Replayed inside the `MIGRATIONS` entry; the sealed-write helper carries the id-fidelity table and the torn-write repair rationale. — see §4.6 |
| Mutations (the user-facing write API) | `lib/db/mutate.ts` (the 53-line dispatcher) → `lib/db/domain/<x>/mutations.ts` (per-domain handlers) | Every server-side action and its effects; under DE these delegate to the chokepoint. The `lib/db/domain/_args.ts` map is the central action-name → Args-type registry, smoke-tested at `lib/db/domain/_args.test.ts`. |
| Pure derivations (the read brains) | `lib/select.ts` | All computed figures — see §2.4 |
| Rules engine | `lib/rules/{engine,types,describe}.ts` | Condition/Action model + evaluator |
| Reconcile math | `lib/reconcile.ts` | Cleared-balance / difference selector |
| Recurrence math | `lib/recurrence.ts` | Scheduled-template occurrence generation |
| Budget cycles & rollover | `lib/budgets/{period,rollover}.ts`, `lib/select.ts` | Cycle windows, progress, auto-rollover |
| FX conversion | `lib/fx.ts`, `components/use-money.ts` | Rate lookup + base↔display conversion |
| Installments | `lib/installment.ts` | Finite-plan progress derivation |
| Counterparty matching | `lib/matcher/counterparty.ts` | Name-resolution on write |
| **Migration discipline** | `lib/db/schema.ts` (`SCHEMA_VERSION` + `MIGRATIONS`) | ISO-datetime version lineage + additive-migration runner; the DE cutover stamps `2026-06-14T00:00:00Z` — see §4.6 |

### 2.1 Entities (and the relationships that matter)

All data is scoped to a **ledger**; ledgers never share rows. The entity set
below reflects the **double-entry storage model** (`plans/done/DOUBLE_ENTRY_PLAN.md`);
the user-facing `Tx` shape that surfaces in selectors and the UI is described
separately in §2.6.

- **ledger** — an isolated set of books with its own `base_currency`. Seeded
  ledgers: personal, family, business, travel. Users can **create, rename,
  and delete** ledgers; ledger creation calls
  `ensureSystemCategories(exec, ledgerId)` to seed the three system equity
  categories (see **category** below). Web-side CRUD ✅ shipped via
  `plans/done/LEDGER_CRUD_PLAN.md` (PR #109); §8 cross-app implication closed.
- **account** — typed (`savings | credit_card | investment | cash | fx |
  virtual`), one fixed `currency`, a cached `current_balance` (derived — see
  §2.3), an `include_in_net_worth` flag, archive state, and a reconcile
  checkpoint (`last_reconciled_at/_balance`). **DE change:** the legacy
  `opening_balance` + `opening_balance_base` columns are gone; an account's
  opening figure is now an **opening entry** (kind=`opening`, equity-balanced
  by the per-ledger `sys:opening-balance` category). `current_balance` is
  recomputed from `Σ confirmed account-leg postings` (the opening leg is in
  the sum — no separate seed term).
- **account_group** / **budget_group** — purely organisational buckets;
  deleting a group SET NULLs its members (they fall into "Ungrouped").
- **category** — a **3-level** tree (`parent_id`, max depth enforced in the
  mutation layer via `assertCanBeParent` / `assertSubtreeFitsUnder` — no
  schema change; web-side ✅ shipped via `plans/done/CATEGORIES_LEVEL3_PLAN.md`
  PR #112). `kind ∈ ('expense','income','equity')` — gains `'equity'` for the
  system rows and **drops `'transfer'`** under DE (a transfer is two account
  legs with no category leg, so a transfer-kind category is unreferenceable
  by construction). Icon + colour as before; colour inheritance walks up the
  chain to the nearest non-null ancestor. Delete promotes children one level
  up (recursively safe). **DE addition:** a nullable
  `system ∈ ('opening','adjustment','fx')` column flags the three per-ledger
  system rows (**Opening balance** · **Balance adjustment** · **FX
  gain/loss**), seeded by `ensureSystemCategories` (called from seed, the
  DE migration, and `createLedger`); a UNIQUE `(ledger_id, system)` index
  prevents duplicates. System rows are resolved by `system`, never by id or
  name (rename-safe); category pickers and the categories admin hide them.
- **tag** — free labels; many-to-many with **entries** via `entry_tags`
  (renamed from `transaction_tags` under DE; a transfer's two account legs
  share tags by construction — no per-leg divergence).
- **counterparty** (merchant) — canonical payee, `is_verified`. An entry's
  `counterparty_id` FK lets a rename follow history; SET NULL on delete keeps
  the raw description.
- **entry** (the journal header — replaces `transactions`) — one row per user
  action. Columns: `date`, `time`, `description` (FTS-indexed via
  `entries_fts`), `kind ∈ ('opening','income','expense','transfer','adjustment','refund')`,
  `status ∈ ('pending','confirmed')`, `confirmed_at`, `counterparty_id`,
  `refunded_entry_id`, `source_template_id`, `notes` (FTS-indexed),
  `applied_rule_ids` (JSON), `reviewed_at`, plus two DE-only columns:
  **`dedup_hash`** (sha256 over `date|time|description|sorted(account:amount)`,
  computed at the chokepoint; UNIQUE per `(ledger_id, dedup_hash)` when not
  NULL — replaces the legacy column-tuple dedup index) and **`sealed`** (the
  two-phase-write flag — see §2.2 + §3 of `DOUBLE_ENTRY_PLAN.md`). `kind` is
  a cached classification label; **the postings shape is the truth** (audit
  I7 in §2.3.1 enforces they agree).
- **posting** (the money leg — replaces `transaction_splits` + the
  amount/currency/`amount_base` columns of legacy `transactions`) — per
  entry: ≥ 2 postings, ≥ 1 account leg, `Σ amount_base = 0` (exact, with
  the FX residue leg, §2.3.1 I1). Each posting is **XOR** an account leg
  (`account_id` set, `category_id` NULL) **or** a category leg (other way
  around; `category_id` may itself be NULL = "uncategorized", preserving
  the legacy SET-NULL-on-category-delete semantics). Account-leg `currency`
  MUST equal the account's currency (schema trigger guard, §2.3.1 I3);
  category-leg `currency` is the ledger base. Both legs carry `amount`
  (signed, in `currency`), `amount_base` (signed, locked at the entry's
  date), and `exchange_rate` (locked). Optional `orig_amount` /
  `orig_currency` carry the user-typed original figure when the entry was
  entered in a currency other than the account's (the "JPY hotel on the
  SGD card" display case; §5.2 of DE plan). Per-leg `cleared_at`
  (reconcile clearing is per account leg; account legs only).
- **entry_attachment** (renamed from `transaction_attachment`) — pointer rows
  (`rel_path`, `sha256`, mime, size) for receipt photos/PDFs attached to an
  entry. **Actual files are NEVER stored in the SQLite database** — they live
  in an `attachments/<entry_id>/` folder on disk and travel inside the
  `.finch` pack (§2.5.3) alongside the DB. The DE migration **reuses the
  legacy transaction id as the entry id** (§4.6), so the on-disk path
  `attachments/<entry_id>/...` is identical to the pre-DE
  `attachments/<transaction_id>/...` for any row that existed before the
  cutover — packs round-trip across the cutover unchanged.
- **budget** — named expense limit or income target with a cycle
  (`frequency`/`start_date`), optional rollover (+ cap), staged
  `pending_amount` (next-cycle change), `last_rolled_period`, and
  account/category filter sets (JSON).
- **scheduled_template** (+ **scheduled_splits**) — recurring income/expense/
  transfer with cadence, `auto_post`, `next_run`/`last_run`, optional
  `installment_total` (finite plans), `max_executions`. Posts via the entries
  chokepoint; a transfer template posts as one entry (two account legs), not
  two rows.
- **holding** — a position inside an investment account (`shares`,
  `cost_basis`, `last_price`); guarded by a trigger to investment accounts only.
  **DE non-change:** decision #23 stands — no commodity/lot accounting; cash
  flows through ordinary account-leg postings as before.
- **exchange_rate** — `(date, currency) → rate`; the locked-rate source.
- **rule** — one if-then rule (JSON `condition` tree + ordered `actions`),
  `priority`, `is_active`, `run_on_edit`. Engine runs inside the chokepoint
  for income/expense/refund kinds (`postEntry` parity with the legacy
  `insertTxRow` hook); a rule's `split` action becomes N category legs.
- **app_state** — small KV slices (mobile tab order, per-ledger display
  currency, transitional queues).
- **db_metadata** — single row: app name, **schema version**, app version,
  export checksum + row counts (the import-integrity guard). **DE row_counts
  keys change:** `transactions` / `transfer_groups` / `transaction_splits` /
  `transaction_tags` / `transaction_attachments` → `entries` / `postings` /
  `entry_tags` / `entry_attachments` (the manifest in §2.5.3 follows the
  same renaming).

> **What dies under DE:** `transfer_groups` (a transfer is just an entry with
> two account legs; its locked from→to rate is derivable as `|toAmount /
> fromAmount|`), `transaction_splits` (splits are just N category legs),
> `accounts.opening_balance` + `accounts.opening_balance_base` (become
> opening entries). What survives unchanged: every other entity above, every
> selector in §2.4, the rules engine, budgets, holdings, scheduled templates,
> FX rate model, pending/confirmed semantics, `current_balance` cache pattern,
> the attachment pipeline, autobackup/pack/import machinery (table lists
> updated). See `DOUBLE_ENTRY_PLAN.md §2.5` for the full survives/dies list.

> **Requirement:** the native model MUST represent every entity and every
> column above. Even columns that look "internal" (`dedup_hash`, `sealed`,
> `applied_rule_ids`, `last_rolled_period`) carry behaviour or audit value
> and are required for `.db` / `.finch` interop (§8).

### 2.2 The status / triage state machine (don't collapse these)

Four orthogonal user-facing axes live on an entry, plus a fifth internal
write-state flag added by DE. They answer different questions and MUST stay
independent:

| Axis | Column | Where | Question | Affects balances? |
|---|---|---|---|---|
| Lifecycle | `status` (pending→confirmed) | entry | "Is this real yet?" | Confirmed only |
| Statement | `cleared_at` | **posting** (account legs only) | "Has it appeared on a real statement?" (reconcile) | No |
| Review | `reviewed_at` | entry | "Have I eyeballed it and it's correct?" | No |
| Provenance | `applied_rule_ids` | entry | "Why is it categorised this way?" | No |
| **Write-state (DE)** | `sealed` | entry | "Is this entry currently being rewritten?" (internal — two-phase write: postings inserted while sealed=0, then `UPDATE … SET sealed=1` fires the balance-check trigger; postings of a sealed entry are immutable, edits unseal → rewrite → reseal) | No |

A confirmed entry can be uncleared and unreviewed; a rule can pre-clear
review at insert. The web app shipped the first four axes as separate
features (PRs for reconcile, rules, review queue), and the DE cutover added
`sealed` as a load-bearing internal flag. The native app MUST not flatten
them into one "done" flag.

**Per-leg clearing under DE:** `cleared_at` lives on the posting (account
legs only), not the entry — clearing account A's leg of a transfer must
not clear account B's leg. This preserves the legacy semantics exactly;
reconcile UI continues to operate per account.

### 2.3 Money & currency invariants (load-bearing)

These rules are the difference between a correct ledger and a plausible-looking
wrong one. They are non-negotiable.

1. **Two amounts per transaction.** `amount` is the **native** figure in the
   row's own `currency`; `amount_base` is the same value in the **ledger's base
   currency**, computed with a **rate locked at write time** (`exchange_rate`).
   A later edit to the rate table MUST NOT reshape history.
2. **Balances are in the account's currency.** A confirmed insert moves
   `accounts.current_balance` by the native amount (under DE, this is
   `posting.amount` for any account leg — currency mismatch is impossible
   by §2.3.1 invariant I3). `current_balance` is **derived/cached**, never
   the source of truth — under DE it is recomputed from `Σ confirmed
   account-leg amounts of postings` (`recomputeAccount`; the opening entry's
   account leg is in the sum, so there is no separate opening-balance seed
   term).
3. **Display ≠ storage.** Amounts are stored in ledger base; the UI converts to
   the user's **per-ledger display currency** for presentation. Two formatters
   exist and MUST be kept distinct: convert-then-format (store/MOCK amounts) vs
   format-an-already-native-amount (FX rows, transfer legs). See `use-money.ts`
   (`fmt`/`short`/`toBase`/`fmtFrom`) and `lib/data.ts` (`fmtNative`).
4. **Display currency is per-ledger**, persisted (DB-backed), defaulting to the
   ledger's base until the user picks one.
5. **Net worth** sums each account's native balance re-expressed in ledger base
   via the live rate, honouring `include_in_net_worth`. Pending rows never count.
6. **Unrealized FX** = live value (`current_balance × today's rate`) − cost
   basis (`Σ confirmed account-leg amount_base` — the opening entry's leg is
   in the sum; under the legacy schema this was
   `opening_balance_base + Σ amount_base` of confirmed transactions). Same-
   currency-as-base accounts are always 0.
7. **Refunds** are `kind='refund'`, positive, and **net against their category**
   (they reduce expense, not add income). Adjustments (`kind='adjustment'`) and
   transfers are excluded from spend/cash-flow/budget math.
8. **Splits override the parent** category in all aggregations and MUST sum to
   the parent (native and base).

> **Direction (money type):** the on-disk format is SQLite `REAL` (a float),
> rounded to 2dp in the app layer — see §4.5 for why the native app should
> still compute in `Decimal`/minor-units and only narrow to `REAL` at the
> storage boundary. **Backstopped by DE:** the balanced-entry invariants
> (§2.3.1 below) make float drift *detectable* at the storage layer — if the
> Swift-side Decimal-to-REAL discipline ever slips, `auditLedger` (§4.9)
> catches it instead of silently corrupting balances.

### 2.3.1 The balanced-entry invariants

Under double-entry the eight invariants above stay true; nine more land at the
storage layer, mirroring `plans/done/DOUBLE_ENTRY_PLAN.md §2.4`. These are
**enforced by schema triggers** (the seal trigger fires when the chokepoint
UPDATEs `sealed = 1`; the posting triggers guard currency + sealed-
immutability), so a native port that reuses the verbatim schema (§4.2)
inherits the enforcement for free. The remaining identities (global trial
balance, cached-balance drift) are checked by `auditLedger` (§4.9).

| # | Invariant | Enforced by |
|---|---|---|
| I1 | Per entry: `ROUND(Σ amount_base, 2) = 0`, **exact** (residue is an explicit `sys:fx-gain` leg, §5.1 of DE plan) | chokepoint + seal trigger |
| I2 | Per entry: ≥ 2 postings, ≥ 1 account leg | chokepoint + seal trigger |
| I3 | Account-leg `currency` = the account's `currency`; category-leg `currency` = ledger base (this is the trigger guard that **kills the long-standing currency-mixing class of bug** by construction) | chokepoint + posting trigger |
| I4 | Postings of a sealed entry are immutable; postings never exist without their entry (FK CASCADE); legs are never written/edited/deleted individually | seal + posting triggers |
| I5 | Every posting's account/category belongs to the entry's ledger | chokepoint + `auditLedger` |
| I6 | Only `status='confirmed'` entries move cached balances; `current_balance = Σ confirmed account-leg amounts` (the opening leg is in the sum — no separate seed term) | trigger + `recomputeAccount` |
| I7 | `entries.kind` matches the postings shape: `transfer` ⟺ 2 account legs; `opening`/`adjustment` ⟺ equity leg with matching `system`; `refund` ⟹ positive account leg (+ optional `refunded_entry_id`) | chokepoint + `auditLedger` |
| I8 | Global trial balance: `Σ all postings.amount_base = 0` per ledger | `auditLedger` (§4.9) |
| I9 | Display-currency identity: `amount = amount_base` exactly when `currency` = ledger base | chokepoint + `auditLedger` |

> **Requirement:** native MUST honour I1-I9 at the storage layer. The
> recommended path (§4.2) is to reuse the verbatim schema + triggers via
> GRDB — that gets I1-I4 + I6 for free; the remaining identities require the
> `auditLedger` port (§4.9). Native MUST NOT bypass the chokepoint to write
> postings directly — there is no other place where the residue leg is
> derived or the dedup hash is computed.

### 2.4 The derivations you must reproduce (the brains)

`lib/select.ts` is, in effect, the functional spec for every number finch
shows. The native app MUST reproduce these to the cent. Treat each as a named,
independently-testable pure function:

- **Lists/feed:** `selectTransactions` (filter/sort), FTS search, `selectTransfers`.
- **Spend & income:** `categorySpend` (split-aware), `monthlySpending`,
  `dailySpending`, `monthlyCashflow`, `incomeCategoryFlow` (Sankey),
  `topCategoryDeltas`.
- **Net worth & balances:** `accountBalance`, `balanceSeries`, `netWorthSeries`,
  `netWorthByMonth`.
- **Budgets:** `cycleWindow`, `budgetProgress` (limit/target, carry-forward,
  account/category filters), auto-rollover (`lib/budgets/rollover.ts`).
- **Forecasting:** `monthForecast` (MTD + run-rate + scheduled), `accountForecast`
  (per-account 30/60/90-day projection with trough detection).
- **Intelligence (heuristic):** `suggestCategory`, `merchantStats` +
  `anomalyScore` (per-merchant z-score), `weeklyDigest`, `findDuplicate`
  (soft dup nudge), and the spending-pattern rules in `lib/insights.ts`.
- **Investments:** `holdingValue`, `holdingGainLoss`, `investmentAccountTotal`,
  `unrealizedFx`.
- **Recurrence/installments:** `occurrencesUpTo`, installment "paid" derivation.

> **Requirement:** these MUST be implemented as a pure, UI-independent layer
> (the "finch-core" of §4.4), not inlined into views — so the parity test
> suite (§12) can verify them against the TS originals.

> **DE note:** under double-entry the **selector list is unchanged in shape**
> (same names, same return types, same semantics), but the underlying SQL is
> now over `postings ⋈ entries` rather than `transactions ⋈
> transaction_splits`. Two simplifications fall out: refund netting collapses
> into the entry-kind buckets (no per-selector `kind IN ('expense','refund')`
> widening across SQL + TS — entries already classify), and the split-vs-
> parent COALESCE gymnastics in `categorySpend` disappear (a category leg is
> a category leg). See `DOUBLE_ENTRY_PLAN.md §7` for the per-selector read-
> path rewires the native port must mirror.

### 2.5 Receipt attachments + the `.finch` pack format (designed here; ✅ shipped on the web)

> **Status:** designed in this section; ✅ shipped on the web end-to-end —
> the attachments table (`entry_attachments` under DE; see §2.5.1), the
> on-disk layout (`attachments/<entry_id>/...`; see §2.5.2), and the
> `.finch` pack format with manifest validation + atomic swap (§2.5.3)
> all match this section verbatim. Native apps inherit the schema as-
> designed; the web-side implementation is the *canonical reference* for
> shape (`frontend/lib/db/schema.ts`, `frontend/lib/db/core/pack.ts`,
> `frontend/lib/db/paths.ts`). The DE cutover (PRs #114 + #116) reused
> legacy transaction ids as entry ids per `DOUBLE_ENTRY_PLAN §8.3`, so
> on-disk attachment paths are byte-identical across the cutover and
> pre-DE packs round-trip on either app unchanged after migration.
> Companion design records: `plans/done/RECEIPT_PHOTOS_PLAN.md` (web-
> side attachments, PR #106), `plans/done/PACK_FORMAT_PLAN.md` (`.finch`
> format, PR #107).

This section originally **decided the shape** so both apps + the file-pack
sync model (§4.3) would inherit a consistent structure from day one. The
web has now adopted it; native must match.

**Key rule, called out emphatically: photos and PDFs are NEVER stored as
blobs inside the SQLite file.** The DB stores **pointers** (relative path +
integrity hash); the bytes live in a sibling `attachments/` folder on disk
and travel inside the `.finch` pack zip alongside the DB.

#### 2.5.1 The attachments table (added to the shared schema, both apps)

```sql
CREATE TABLE entry_attachments (
  id                TEXT PRIMARY KEY,         -- UUID
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  entry_id          TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  kind              TEXT NOT NULL CHECK(kind IN ('image','pdf')),
  -- Path inside the pack AND inside the live attachments folder:
  -- 'attachments/<entry_id>/<id>.<ext>'. Bytes are NEVER in the DB.
  rel_path          TEXT NOT NULL,
  mime_type         TEXT NOT NULL,
  byte_size         INTEGER NOT NULL,
  sha256            TEXT NOT NULL,            -- integrity check on read
  original_filename TEXT,                     -- preserved for UI
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE INDEX idx_attach_entry  ON entry_attachments(entry_id);
CREATE INDEX idx_attach_ledger ON entry_attachments(ledger_id);
```

> The legacy `transaction_attachments` table + `idx_attach_txn` index were
> the pre-DE shape; the DE migration renames the table + the FK column +
> the index in place, preserving every row id (see §4.6 + `DOUBLE_ENTRY_PLAN.md
> §8.2`). Both apps land at the renamed shape on the same `SCHEMA_VERSION`
> stamp.

- **Cascade behaviour:** deleting a transaction removes the DB row by
  cascade; the orphaned file on disk is swept by the pack-builder (which
  knows the live row set) and on a periodic vacuum, so every pack is
  self-consistent (DB rows ↔ file inventory).
- **Integrity:** `sha256` lets the app refuse a tampered or missing file
  rather than silently render the wrong receipt.
- **Shared schema:** this table lands in **both** the native app and the
  web app's `lib/db/schema.ts`, on the same `SCHEMA_VERSION` lineage, so
  packs round-trip cleanly. See §8 cross-app implications.

#### 2.5.2 On-disk layout (live working files on a device)

```
<app-container>/
├── finch.sqlite3
├── finch.sqlite3-wal
├── finch.sqlite3-shm
└── attachments/
    └── <entry_id>/
        ├── <attachment_id>.jpg
        └── <attachment_id>.pdf
```

The native app writes attachments here directly (e.g. from the Share
Extension or the photo picker); the web app's server-side equivalent
stores them under a configured directory next to the DB. Either runtime
produces the same shape.

#### 2.5.3 The `.finch` pack format

The unit of iCloud Drive sync (§4.3) and of cross-platform interop (§8).
Plain ZIP container, with a `.finch` extension registered as a document
type on iOS/macOS so Files and Finder open it in the app.

```
my-ledger.finch       (ZIP container)
├── manifest.json     -- pack metadata + checksum + file inventory
├── finch.sqlite3     -- VACUUM INTO'd before packing
└── attachments/
    └── <entry_id>/
        └── <attachment_id>.<ext>
```

`manifest.json` carries: pack-format version, `app_name`, `app_version`,
`schema_version`, `exported_at`, `exported_from` (device id + name),
`db_sha256`, `row_counts` (mirroring the existing `db_metadata`
integrity guard — `lib/db/core/checksum.ts` generalises straight into this),
and `attachment_count` + total bytes. **DE `row_counts` keys:** the
manifest enumerates the post-DE canonical tables (`entries`, `postings`,
`entry_tags`, `entry_attachments`, ...) — packs exported before the
cutover still import because migrations run when the swapped file is
opened (§4.6).

- **Atomic swap on receive:** the receiving device unpacks to a tmp
  directory, validates the manifest + every attachment's sha256, then
  renames the working files into place. A failed validation leaves the
  device's current data untouched.
- **Conflict policy:** last-writer-wins at the pack level; iCloud Drive
  surfaces a conflict copy when two devices wrote offline (§4.3).
- **Size note:** packs include all attachments, so they can grow into the
  tens of MB. iCloud Drive handles this fine; the cadence (§4.3) is
  debounced to avoid thrashing.
- **Backups doubles as the pack history.** Successive packs in a dated
  folder are also the user's restore points (§9).

### 2.6 The `Tx` projection contract (single-entry skin)

Storage is double-entry (§2.1); consumption is single-entry. This subsection
records the **projection contract** native MUST emit so every consumer in §2.4
keeps the same arithmetic and a `.finch` pack written by either app projects
identically on the other.

The web projection lives in `frontend/lib/db/state.ts` (`projectState`) and
emits **one `Tx` per account posting**, so a transfer is two `Tx` rows
(exactly as today, exactly as `selectTransfers` expects). The shape native
MUST reproduce:

| `Tx` field | Source under DE |
|---|---|
| `id` | the **account posting id** (DE migration reuses the legacy `transactions.id` here, so client ids are bit-identical across the cutover — §4.6) |
| `amount` | the account leg's `amount_base` (signed) |
| `nativeAmount` / `currency` | leg `orig_amount ?? amount` / `orig_currency ?? currency` |
| `account` | leg `account_id` |
| `category` | the entry's single category leg's `category_id`; with ≥ 2 category legs, the largest-`abs(amount)` leg's (display default; aggregations use `splits`). Equity legs are never projected as `Tx.category` |
| `splits` | ≥ 2 category legs → `[{ id, categoryId, amount: −leg.amount, amountBase: −leg.amount_base, description: memo }]` — **negated** back to the parent-signed convention the consumer expects. Equity legs are never projected as splits |
| `kind` | `entries.kind`; **`kind='opening'` entries are filtered out** of the `Tx` list entirely and projected into `AccountRow.openingBalance` / `openingBalanceBase` instead |
| `transferGroupId` | the entry id, when the entry has ≥ 2 account legs (`selectTransfers`' grouping works verbatim) |
| `refundedTransactionId` | the refunded entry's account-posting id, via join |
| `clearedAt` | the leg's `cleared_at` (per-account clearing preserved) |
| `tags` | `entry_tags` (transfer legs share tags by construction) |
| `merchant`, `date`, `time`, `note`, `pending`, `ledgerId`, `sourceTemplateId`, `counterpartyId`, `appliedRuleIds`, `reviewedAt` | `entries` columns (merchant = description with the counterparty-canonical override) |

> **Requirement:** native MUST emit this projection shape. `FinchCore` (§4.4)
> exposes the projection as a pure function over an open SQLite handle,
> returning the same `Tx` / `AccountRow` shapes the web's `Tx` type defines.
> The parity suite (§12) verifies a Swift projection of a golden DB matches
> the TS projection row-for-row. This is what lets every selector in §2.4
> keep its current arithmetic — and what lets a `.finch` pack written by
> either app project identically on the other.

> **Equity legs are invisible to the consumer.** The three system equity
> categories (`opening` / `adjustment` / `fx`) appear in postings but never
> as `Tx.category` or as a `Tx.splits` entry — they are filtered out by the
> projection. The categories admin and category pickers MUST hide them too
> (resolve by the `system` column, never by id or name; rename-safe).

> **Adapter preconditions for `rebuildEntry`** — code-level disciplines
> enforced in `frontend/lib/db/core/entries.ts` (and its consumers in
> the per-domain `frontend/lib/db/domain/<x>/mutations.ts` files, dispatched
> through `lib/db/mutate.ts`). When a mutation rewrites legs via the chokepoint's
> `rebuildEntry`, it MUST: (a) forward each account leg's `cleared_at` —
> omission silently un-clears a reconciled row — and (b) pass explicit
> `amountBase` values when the entry carries user-pinned rates that a date
> edit must preserve (the default re-locks from the rates table). Native
> ports of `updateTransfer` and `updateTransaction` MUST honour both.

---

## 3. Feature parity matrix

Every user-facing surface in the web app → native requirement + Apple idiom +
parity tier. **Tier 1** = required for a credible first release; **Tier 2** =
fast-follow; **Tier 3** = native-only upside (detailed in §7). "Source" points
at where the behaviour lives today.

| # | Feature (web) | Native requirement | Apple idiom | Tier | Source |
|---|---|---|---|---|---|
| 1 | Accounts list: net-worth hero, grouped accounts, sparklines | Net-worth header + collapsible grouped accounts, per-account balance & sparkline | `List` w/ sections; large title; Swift Charts | 1 | `accounts/page.tsx` |
| 2 | Account detail: balance hero, FX g/l, holdings, forecast, tx list | Hero card (native + ≈display, FX line), holdings panel, forecast card, recent tx | Nav stack push / iPad split detail | 1 | `accounts/[id]/page.tsx`, `account-forecast.tsx`, `account-holdings.tsx` |
| 3 | Reconcile-to-statement (cleared toggles, running tally, quick-add, finish/adjust) | Reconcile session over the account tx list w/ cleared checkboxes + tally + finish | Edit-mode list w/ selection; sheet | 2 | `reconcile-status.tsx`, `lib/reconcile.ts` |
| 4 | Adjust-balance dialog | One-shot balance adjustment posting a marked delta | Form sheet | 2 | `accounts/[id]` |
| 5 | Activity feed: day groups, direction tabs, search | Date-sectioned feed, All/Out/In, search | `List` + `.searchable`; segmented control | 1 | `activity/page.tsx` |
| 6 | Activity filters (date/amount range), saved searches | Filter sheet (date/amount); saved-search chips (device-local) | Filter sheet; chips; `@AppStorage` | 2 | `use-saved-searches.ts` |
| 7 | Select-mode bulk recategorise | Multi-select → apply one category | Edit-mode multi-select + toolbar | 2 | `activity/page.tsx` |
| 8 | Needs-review filter + mark-all-reviewed | "Needs review · N" filter + bulk clear + per-row dot | Filter chip; swipe action | 2 | `activity/page.tsx`, `setReviewed`/`markAllReviewed` |
| 9 | Per-row badges: refund, anomaly, needs-review | Inline badges on rows | SwiftUI label styles | 1–2 | `refund-badge.tsx`, `anomaly-badge.tsx` |
| 10 | Add transaction: type toggle, big amount, recent chips | Expense/Income/Transfer; large amount keypad; recent chips | Modal sheet; decimal pad; FAB entry | 1 | `add-expense-form.tsx` |
| 11 | Category suggestion + duplicate nudge | Suggested-category chip; soft dup warning | Inline chip; non-blocking banner | 2 | `suggestCategory`, `findDuplicate` |
| 12 | Multi-currency entry + cross-currency transfer (rate lock) | Currency follows account; received-amount locks rate | Inline secondary field | 2 | `add-expense-form.tsx`, `createTransfer` |
| 13 | Merchant picker | Counterparty search/create on entry | Searchable picker sheet | 2 | `merchant-picker-sheet.tsx` |
| 14 | Budgets list: rings, groups, tabs (expense/income) | Grouped budget cards w/ progress rings; type tabs | `List`/grid; Swift Charts ring | 1 | `budgets/page.tsx` |
| 15 | Budget detail: ring, carry-forward, contribute, cycle tx list | Ring + figures + cycle tx list; contribute (income); edit cycle | Detail view; form sheet | 1 | `budgets/[id]/page.tsx` |
| 16 | Budget rollover + staged amount change | Rollover toggle/cap; next-cycle amount staging | Toggle + stepper | 2 | `lib/budgets/*` |
| 17 | Insights: metric tabs (spend/income/cashflow/net worth) + ranges | Trend charts w/ metric + 3M/6M/1Y range | Swift Charts; segmented controls | 1 | `insights/page.tsx` |
| 18 | Weekly digest card | Sunday recap (spent/income/net, vs prev & 12-wk avg, top cats) | Card; also a Widget (§7) | 2 | `weekly-digest-card.tsx`, `weeklyDigest` |
| 19 | Month-forecast card | Stacked projection (MTD + run-rate + scheduled) | Card + Swift Charts | 2 | `monthForecast` |
| 20 | Income→categories Sankey | Flow chart income→top categories+saved | Custom `Canvas`/`Path` | 2 | `incomeCategoryFlow` |
| 21 | Category deltas / spending-pattern insights | MoM deltas + descriptive insight cards | Cards | 2 | `topCategoryDeltas`, `lib/insights.ts` |
| 22 | Calendar heatmap (daily spend) | 12-week intensity grid | `LazyVGrid`/`Canvas` | 2 | `dailySpending` |
| 23 | Reports / breakdown (donut + category list + CSV) | Month breakdown + export | Donut chart; share sheet for CSV | 1 | `reports/page.tsx` |
| 24 | Scheduled: calendar grid + upcoming list, post-now | Month calendar w/ event dots; upcoming list; post-now | Calendar view; context menu | 1 | `scheduled/page.tsx`, `lib/recurrence.ts` |
| 25 | Installment tracking | paid/total badge; cap enforcement | Badge | 2 | `lib/installment.ts` |
| 26 | Pending review: confirm/edit/cancel/confirm-all + matcher | Pending queue w/ per-row + bulk actions; counterparty match on confirm | Swipe actions; bulk toolbar | 1 | `pending/page.tsx`, `pending-row.tsx` |
| 27 | Transfers list + detail (two legs, locked rate) | Transfer list + detail showing both legs + rate | Detail view | 2 | `transfers/*` |
| 28 | Merchants/counterparties admin (verify/rename/delete) | Counterparty manager w/ verify + CRUD + search | `List` + edit | 2 | `merchants/page.tsx` |
| 29 | Categories admin (≤ 3-level tree, icon/colour) | Tree editor; create/edit/delete w/ promote-on-delete; depth cap enforced in mutation layer (mirror the web's `assertCanBeParent` / `assertSubtreeFitsUnder` in `Categories.addCategory(parentId:)`); recursive rollup + recursive budget category match | Outline/`DisclosureGroup` | 2 | `categories/page.tsx`; design: `plans/done/CATEGORIES_LEVEL3_PLAN.md` (✅ shipped on web) |
| 30 | Tags admin | Tag CRUD w/ colour | `List` + edit | 2 | `tags/page.tsx` |
| 31 | Rules: list, builder, backfill w/ preview, inline create-rule | Rule list; condition/action builder; backfill preview; "create rule" after manual recat | Form builder; sheet | 2–3 | `rules/page.tsx`, `rule-builder-sheet.tsx`, `lib/rules/*` |
| 32 | Transaction detail: recat, split, tags, refund, review/cleared toggles, FX card, rule provenance, delete | Full detail w/ all inline edits + provenance | Detail sheet; menus; swipe | 1 | `transaction-detail.tsx` |
| 33 | Settings/Account: theme, mobile-tab editor, sample data, DB card, export/import, backup/restore, backup-frequency + backups-kept | Appearance, data/backup, export/import `.finch` + `.csv`; auto-backups are `.finch.bak` packs; user-configurable frequency + retention persisted in app_state | Settings screen; Files/share | 1–2 | `settings/account/page.tsx` |
| 34 | Settings/Ledger: active ledger, display currency, base-currency change, exchange rates | Ledger settings + FX book + base-change tool | Pickers; warned destructive action | 2 | `settings/ledger/page.tsx`, `exchange-rates.tsx` |
| 35 | Ledger switcher | Switch active ledger (scopes everything) | Sheet / sidebar menu / macOS toolbar | 1 | `ledger-switcher.tsx` |
| 36 | Command palette (⌘K) | Jump-to-anything search | macOS ⌘K; iOS Spotlight (§7) | 2 (mac 1) | `command-palette.tsx` |
| 37 | Responsive shell (sidebar/bottom-bar, breadcrumbs) | Adaptive nav (tab bar vs sidebar/split) | `TabView`/`NavigationSplitView` | 1 | `PageShell.tsx` |
| 38 | Holdings management (add/edit/price/delete) | Position CRUD + price update | Form sheets | 2 | `account-holdings.tsx` |
| 39 | Ledger CRUD (create / rename / restyle / set-default / delete) | Full ledger CRUD on both apps; mutations on the shared schema | Form sheet; settings row | 1 | `lib/db/queries/ledgers.ts`; `lib/db/domain/ledgers/mutations.ts` (createLedger / updateLedger / setDefaultLedger / deleteLedger); `components/ledger-switcher.tsx`; `app/(main)/settings/ledger/page.tsx`. Web ✅ shipped via `plans/done/LEDGER_CRUD_PLAN.md`. |
| 40 | **NEW — Receipt attachments** (capture / attach photo or PDF; view; delete) | Share Extension + in-app photo/PDF picker; thumbnail + viewer in tx detail | Share extension; `PhotosPicker`; `QuickLook` | 2 | §2.5; (web also adds attachment UI + a server-side attachments dir) |

> Tiering is direction, not contract — the team MAY re-tier, but SHOULD keep
> Tier 1 as a coherent "you can run your finances in this" slice.

---

## 4. Architecture direction

These are the decisions that shape everything. Each is **Direction:** with
options, trade-offs, and a recommendation.

### 4.1 App structure: one codebase or several?

| Option | Pros | Cons |
|---|---|---|
| **A. SwiftUI multiplatform target** (one app, iOS+iPadOS+macOS) sharing a Swift core package | One codebase; idiomatic on each platform via size classes & platform `#if`; least duplication | Some per-platform view divergence to manage |
| B. Mac Catalyst (iPad app on Mac) | Fastest path to "a Mac app" | Mac result feels iPad-ish; weaker macOS idioms (menus, windows) |
| C. Separate UIKit/AppKit apps | Maximum native fidelity per platform | 2–3× the UI work; defeats the shared-core advantage |

**Direction: A.** A SwiftUI app with a shared **`FinchCore`** Swift package
(model + DB + derivations + money/FX + rules) and thin per-platform view layers.
The web app already proved a *single responsive surface* can serve phone and
desktop (`PageShell`); SwiftUI's adaptive containers (`TabView` ↔
`NavigationSplitView`) are the native analogue (§6). Reserve Catalyst only as a
fallback if macOS-specific SwiftUI gaps bite.

### 4.2 Data layer on device

| Option | Pros | Cons |
|---|---|---|
| **A. SQLite via GRDB.swift**, reusing the exact `schema.ts` SQL | 1:1 schema parity incl. triggers + FTS5; trivial `.db` interop (§8); battle-tested | A dependency; must port query/mutation logic to Swift |
| B. SwiftData / Core Data | First-party; nice SwiftUI bindings | Its own store format → breaks `.db` interop; can't reuse triggers/FTS/SQL; impedance vs the relational design |
| C. Raw SQLite C API | No deps | Reinventing GRDB badly |

**Direction: A (GRDB).** The schema — including the balance-update trigger, the
FTS5 virtual table + sync triggers, and the holdings-guard triggers — is a
designed asset. Reuse the `CREATE …` SQL **verbatim** so a finch `.db` written
by the web app opens unchanged on device and vice-versa. SwiftData's separate
store would forfeit interop and the trigger/FTS work for binding sugar finch
doesn't need (the store is read through pure selectors, not object graphs).

### 4.3 The sync question (the crux)

How does a native install relate to the user's data and to the existing web app?

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **A. Standalone local-first** | Port schema+logic to Swift; the on-device `.db` is the source of truth; interop = export/import the file (incl. iCloud Drive) | Fully offline; no backend; matches today's single-device model exactly; simplest privacy story | No automatic cross-device sync; user moves the file |
| B. Thin client of the existing server | Consume `GET /api/state` + `POST /api/mutate`; server stays the source of truth | Reuses *all* server logic; near-zero logic re-implementation | Requires a hosted server + auth (neither exists); offline needs a cached mirror anyway; not "local-first" |
| C. Local-first + optional sync | A on device, plus an opt-in sync engine (CloudKit private DB, or the existing server as a sync target) | Best UX; offline + multi-device | Most work; conflict resolution; the schema's string PKs complicate merge (§4.6) |

**Decision: local-first + iCloud Drive *file-pack* sync (a hybrid of A + a
specific form of C).** The on-device working files (SQLite DB +
`attachments/` folder, §2.5) stay the source of truth. On a debounced
schedule and on app background, the app **packs** them into a single
`.finch` zip and writes the pack to a user-visible folder in the app's
iCloud Drive container; iCloud Drive replicates the pack to the user's
other devices; finch on the other device detects the newer pack (by
`manifest.json`), validates it, and atomically swaps in the unpacked
contents.

- **Granularity:** the pack is the sync unit (one pack = the whole DB
  with all ledgers + all attachments — see §2.5.3 for layout). Conflicts
  are resolved at the pack level — **last-writer-wins**; iCloud surfaces
  a "conflict copy" if two devices wrote offline. No row-level merge in v1.
- **Cadence:** auto-pack on a debounce (e.g. ~30 s idle after a mutation,
  and on background); a manual "Sync now" affordance is always available.
- **What we trade away:** simultaneous offline edits on two devices means
  one device's session is preserved as a conflict copy rather than merged.
  Acceptable for a single-user product.
- **Why not CloudKit row-level sync (the full option C):** more code, more
  privacy surface, more conflict-merge edge cases. The file-pack approach
  uses iCloud purely as a dumb file mover and keeps the "the file is the
  source of truth" instinct intact.
- **Why not the server (B):** there is no server to be a thin client of,
  and standing one up would conflict with the no-account, no-infrastructure
  product promise.

UUID primary keys (§4.6) are still required — they keep a future
row-level sync model possible without a schema break and reduce id
collisions if two devices briefly diverge.

> Note: the projection (`projectState` in `lib/db/state.ts`) returns the
> **whole** projection on every mutation — fine at personal-finance data
> sizes, and a clean model for "recompute, then re-render." The native app
> SHOULD adopt the same "mutate → re-derive → publish" loop (a single
> `@Observable` store fed by `FinchCore`).

### 4.4 Shared logic: port to Swift, don't bridge JS

| Option | Pros | Cons |
|---|---|---|
| **A. Re-implement `select.ts`/engine in Swift** as `FinchCore`, with a parity test suite | Idiomatic, fast, debuggable, no JS runtime; one obvious home for the rules | Must keep two implementations in sync |
| B. Embed the TS via JavaScriptCore / a WASM build | One source of truth for logic | Bridging cost; perf; type marshalling; non-idiomatic; hard to test in Swift |

**Direction: A.** Port the derivations and the rules engine to Swift. Make the
existing `bun test lib` cases the **parity oracle**: export their fixtures and
assert the Swift output matches the TS output to the cent (§12). This keeps the
two implementations honest without coupling runtimes. The `Condition`/`Action`
JSON shapes (`lib/rules/types.ts`) are already serialisable — decode them into
Swift enums and keep the JSON wire-format identical for `.db` interop.

### 4.5 Money type direction

The web app stores money as `REAL` and rounds to 2dp in app code — pragmatic for
JS, but float drift is a real risk in a ledger.

**Direction:** compute money in **`Decimal`** (or integer **minor units**)
inside `FinchCore`; narrow to `REAL` only at the SQLite storage boundary, with
explicit 2dp rounding (the same `ROUND(x,2)` discipline the schema documents).
This is *stricter* than the web app while remaining `.db`-compatible on disk.
Currency formatting MUST use `Decimal` + locale-aware
`Decimal.FormatStyle.Currency` (not string hacks), and MUST honour the
**per-ledger display currency** and the convert-vs-native distinction in §2.3.
Rate lookup mirrors `lib/fx.ts` (nearest on-or-before `date`).

### 4.6 Schema versioning & IDs

- **Version lineage:** keep the `db_metadata.schema_version` ISO-datetime
  lineage and the additive-migration discipline from `schema.ts` (idempotent
  `ADD COLUMN`, "already applied" swallow). A native install reads the version,
  runs only newer migrations, then re-stamps. **Requirement:** native and web
  MUST agree on the version string so a shared `.db` migrates once, consistently.
- **IDs:** the web app uses short string PKs (`'food'`, `cc-…`) for legacy
  lookups; the *original* design (`database_design_en.md §3.1`) called for
  **UUIDv4** precisely for a multi-device sync model. **Direction:** native
  app generates **UUIDs** for new rows (PKs are `TEXT`, so they coexist with
  legacy ids), paying forward the §4.3-C sync option at no cost today.
- **The double-entry migration.** `SCHEMA_VERSION` is bumped to
  `2026-06-14T00:00:00Z` by the DE cutover (PRs #114 + #116,
  `plans/done/DOUBLE_ENTRY_PLAN.md §8`). A native install that opens a
  pre-DE `.finch` pack from the web (or vice versa) runs the same
  `MIGRATIONS` entry — defensive `VACUUM INTO '<file>.pre-de.bak'`
  snapshot, fresh entries / postings / entry_tags / entry_attachments /
  entries_fts tables + indexes + triggers, category-table rebuild for the
  new CHECK + `system` column, per-ledger `ensureSystemCategories`, then
  the §8.2 data-move via the `MIGRATIONS` entry inside
  `frontend/lib/db/core/entries.ts` (per-entry sealed-write, id-preserving
  so client ids stay bit-identical across the cutover — id-stability table
  at `DOUBLE_ENTRY_PLAN §8.3`; sealed-write helper at
  `frontend/lib/db/core/sealed-entry.ts`),
  `entries_fts` backfill, drop legacy tables, recompute every account,
  `auditLedger` clean-or-abort. The `.pre-de.bak` snapshot is the
  rollback. Native and web MUST run a byte-identical migration step so
  the same DB migrates once, consistently, regardless of which app opens
  it first; the migration is idempotent on a DB already at the new
  version. Implementation reference: `frontend/lib/db/core/entries.ts`
  (the `MIGRATIONS` array + `applyMigrations` runner) and
  `frontend/lib/db/core/sealed-entry.ts` (top-of-file comment carries the
  id-fidelity table and the torn-write repair rationale).

### 4.7 Platform baselines (decided)

- **OS floor: iOS 26+, iPadOS 26+, macOS 26+.** A modern floor lets the app
  use Swift Charts, App Intents, `@Observable`, `NavigationSplitView`, and
  WidgetKit (when widgets are added — §7) without compatibility shims. Drops
  users on older devices; acceptable in trade for a leaner codebase and the
  full native surface in §7.

### 4.8 macOS distribution (decided)

- **Ship to the Mac App Store *and* as a notarised direct download.** Single
  Xcode target, two distribution paths. App Store gives discovery and
  auto-update; a notarised `.dmg`/`.pkg` direct download fits a local-first,
  file-portable app and lets users who prefer non-store binaries install
  without an Apple ID. (Direct distribution is also the friendlier story for
  users wary of any app-store data policies on a finance app.)

### 4.9 The audit invariant (`auditLedger`)

**Direction (required):** native MUST implement `auditLedger` in `FinchCore`,
ported from `lib/db/core/entries.ts::auditLedger`
(`plans/done/DOUBLE_ENTRY_PLAN.md §3.3`). It is a read-only sweep returning typed
problems:

- Unbalanced entries (I1 violations beyond rounding) and unsealed entries
  (torn writes).
- Under-2-leg or 0-account-leg entries (I2).
- Kind ⇔ shape mismatches (I7 — e.g. `kind='transfer'` with one account leg,
  `kind='adjustment'` with no equity leg).
- Account-leg currency mismatches (I3 — the long-standing currency-mixing
  bug class, now schema-enforced; the audit catches any historical row that
  slipped through pre-DE).
- Cross-ledger postings (I5) and `amount ≠ amount_base` on base-currency
  legs (I9).
- Non-zero global trial balance per ledger (I8).
- Cached `current_balance` drift vs the `recomputeAccount` sum.

**When it runs (parity with the web — `DOUBLE_ENTRY_PLAN.md §3.3`):**

1. On every **import** of a `.finch` pack — after the manifest's byte
   checksum, before the atomic swap. A failing audit refuses the import
   with the typed problem set; the device's current data is untouched.
2. On the native equivalent of `/api/db-info` — surface the count + a
   "View report" affordance in the Settings ▸ Data section.
3. As a **test-suite hook** at the end of every parity-suite scenario
   (cheap; catches regressions broadly).
4. As the **migration's abort condition** (§4.6).

**Why this is load-bearing.** The seal + posting + balance triggers (§2.3.1)
enforce *most* invariants at the schema level — a native port that reuses
the verbatim schema (§4.2) inherits I1-I4 + I6 for free. But the trial-
balance identity (I8) and the cached-balance-vs-recompute drift check are
global sweeps that have to be ported. A native install that ever drifts
from the web on these is, by definition, a `.db` interop break (§8).

**Parity expectation.** Native and web MUST return the same typed problem
set on the same DB. Golden DB fixtures with seeded corruptions (one per
problem class) assert this in both test suites (§12 audit parity).

---

## 5. Design system → native mapping

The look is part of the product. Map tokens, don't reinvent them. The
authoritative *current* tokens are the CSS variables in `app/globals.css`; the
richer design intent (and the editorial serif) is in
`plans/frontend_design/theme.jsx`.

### 5.1 Colour tokens (ship these as an Asset Catalog with light/dark)

| Token | Light ("warm editorial") | Dark ("noir") | Use |
|---|---|---|---|
| background | `#f5f1ea` | `#0e0d0c` | App canvas |
| card / popover | `#faf7f1` | `#1c1a17` | Cards, sheets |
| foreground | `#1a1614` | `#f1ece2` | Primary text |
| primary | `#c96442` | `#e07856` | Accent / primary action |
| secondary / muted / accent (bg) | `#ece5d9` | `#1a1816` / `#2a2722` | Fills |
| muted-foreground | `#8a7e6e` | `#9a8f7e` | Secondary text (AA-tuned) |
| success | `#5e7d5e` | `#9bb89b` | Income / positive |
| warning | `#c89a3e` | `#d8b366` | Pending / caution |
| destructive | `#c96442` | `#e07856` | Negative / delete |
| border / input | `#d8cfc1` | `#2a2722` | Hairlines |
| chart-1…5 | `#c96442 #5e7d5e #c89a3e #6b8ab0 #8a6ba8` | `#e07856 #9bb89b #d8b366 #7da0c4 #a98cc4` | Series colours |

- Corner radius base **14px** (`--radius: 0.875rem`) with the sm/md/lg/xl
  derivations from `globals.css`.
- Category/tag colours are user-chosen hex from a curated swatch palette
  (`lib/colors.ts`) — port the same palette so colours match across apps.
- **Requirement:** semantic mapping MUST match (income=success, expense/delete=
  destructive, pending=warning), and both themes MUST follow the system
  light/dark setting by default with a manual override (mirrors `next-themes`).

### 5.2 Typography (decided: plain font)

The **live web app maps both `--font-sans` and `--font-serif` to Inter** — i.e.
the editorial *serif* in the prototype (`Instrument Serif`) was never actually
shipped.

**Decision: plain font (system sans-serif) in v1, matching the live web look.**
Use the system font (San Francisco on Apple platforms — the same role Inter
plays on web) for everything, with a system mono for technical rows (rates,
ids). The editorial serif from the prototype is not in v1; it remains an option
to revisit later as a deliberate brand-polish move.

Regardless of the family choice: numerals MUST be **tabular/monospaced-figure**
for column alignment, and all type MUST support **Dynamic Type** (§11).

### 5.3 Charts & primitives

The web app hand-rolls SVG primitives (`components/primitives.tsx`): sparkline,
bar, donut, ring, stacked area, Sankey, calendar heatmap, plus the `Icon`
(lucide) shim and `Money`. **Direction:** reproduce these with **Swift Charts**
where it fits (sparkline, bar, area, donut/ring) and `Canvas`/`Path` for the
bespoke ones (Sankey, calendar heatmap). Keep the same restrained styling: thin
strokes, low-opacity fills, the chart-1…5 palette, decorative charts marked
accessibility-hidden with a text alternative (§11). The lucide icon set should
map to SF Symbols where a clean equivalent exists, falling back to bundled
vectors to preserve exact glyphs.

---

## 6. Navigation & platform UX

Mirror `PageShell`'s single-model-two-chromes idea with native containers.

- **iPhone:** a `TabView` of the primary sections (Accounts, Budgets,
  Scheduled, Insights — user-reorderable, mirroring the mobile-tab editor) with
  a prominent center **Add** action (the FAB in the prototype). Ledger-admin
  sections (Pending, Transfers, Merchants, Categories, Tags, Rules, FX) are
  reachable via the ledger/overflow menu and Spotlight/⌘K, not the tab bar —
  exactly the web app's "not in the bottom bar" decision.
- **iPad / macOS:** `NavigationSplitView` — sidebar (primary sections +
  "Ledger" group), content, detail. This is the native form of the desktop
  sidebar + breadcrumb model. Detail routes (`/<section>/<id>`) become the
  detail column.
- **Large titles** on iOS for top-level sections; **breadcrumb-equivalent**
  via the split-view hierarchy on iPad/Mac.
- **Sheets** for Add / transaction detail / form dialogs (the web uses
  Sheet/Dialog throughout). Use detents on iPhone; right-hand inspector or
  panel on iPad/Mac.
- **Context menus & swipe actions** replace the web `RowActions` (⋯) menu:
  swipe-to-confirm/cancel on Pending, swipe-to-review on Activity,
  long-press/right-click for edit/delete/refund.
- **Ledger switcher** as a sheet (iPhone) / sidebar menu (iPad) / toolbar
  popover (Mac). Switching MUST re-scope everything, like today.
- **macOS specifics:** real menu bar (File ▸ New Transaction/Ledger, ▸
  Export…; Edit; View ▸ switch ledger), full keyboard model, ⌘K command
  palette (already designed — port `command-palette.tsx`), multiple windows
  (e.g. a window per ledger), and Touch ID for the biometric lock (§10).

---

## 7. Native opportunities (the payoff for going native)

These are Tier 3 — the reason a wrapper isn't enough. Each maps onto a feature
finch already computes, so the data work is mostly done.

- **App Intents / Siri / Shortcuts:** "Add a $6 coffee to Personal" → an
  `AddTransaction` intent over `FinchCore`; "What did I spend this week?" →
  surfaces `weeklyDigest`. Donate intents so Siri Suggestions learn the user's
  habitual entries (pairs with `recentExpenses`). **The intent dispatches
  through the Swift port of `postEntry` (the chokepoint, §2.6), so the
  balanced-entry invariants and the rules engine apply to Siri-created
  entries automatically — there is no other write path.**
- **Widgets (WidgetKit) — deferred to a later phase (decision §14).** The
  widget candidates (net-worth sparkline, this-month budget ring,
  month-forecast tile, weekly digest) all sit on top of existing selectors,
  so the cost is UI + an App Group, not new logic. Held back to keep the
  v1 native surface focused. Picked up in §13 phase 7.
- **Live Activities / Lock Screen — deferred with widgets.** Same reasoning.
- **Share Extension → receipts:** the long-deferred receipt-photo feature
  (`FEATURE_IDEAS §4.1`) is *natural* here — share a photo/PDF into finch to
  create/attach to an entry. The web-side `entry_attachments` table + on-
  disk pipeline is ✅ shipped (PR #106; renamed from `transaction_attachments`
  by the DE migration — §2.5.1); native reuses the same schema + on-disk
  layout (§2.5.2) and just adds the iOS intake (Share Extension +
  `PhotosPicker`).
- **Spotlight indexing:** index transactions/merchants/accounts via
  `CoreSpotlight` so system search jumps into finch — the iOS analogue of ⌘K.
- **Notifications:** local notifications for scheduled items due, budget
  warning thresholds (`warning_pct`), anomaly flags, and the Sunday weekly
  digest. All derive from existing logic; no server/push needed.
- **Biometric lock & Face/Touch ID:** gate app open + sensitive actions (§10).
- **Handoff & Universal Clipboard:** continue an in-progress Add across devices.
- **Focus filters:** e.g. show only the "Business" ledger during Work Focus.
- **Apple Watch (MAY, later):** glance net worth / budget rings; quick-add a
  recent expense.
- **Files app integration:** the `.db` and CSV exports as first-class documents
  (§8) — open-in-place, iCloud Drive.

> **Boundary to hold:** finch does **not** do bank/statement *import* or live
> feeds (a standing product line — see `database_design_en` and the reconcile
> plan). Apple Wallet/bank connections are **out of scope** for the same
> reason; reconcile + manual/share-extension entry is the model.

---

## 8. Interop with the web app & data portability

> **DE note (added 2026-06-07):** the double-entry storage migration in
> progress on the web (`plans/done/DOUBLE_ENTRY_PLAN.md`) does NOT change the
> cross-app interop contract. The `.finch` pack is still a SQLite DB on the
> shared `SCHEMA_VERSION` lineage; the canonical tables inside are now
> `entries` / `postings` / `entry_tags` / `entry_attachments` instead of
> `transactions` / `transfer_groups` / `transaction_splits` / `transaction_tags`
> / `transaction_attachments`. The pack manifest's `row_counts` keys
> follow that rename. Pre-DE packs still import on either app — migrations
> run when the swapped-in file is opened (§4.6).

- **The `.finch` pack is the primary interop unit (§2.5.3).** A device
  exports a pack to the share sheet or iCloud Drive; another device — or
  the web app — opens that pack to import. The pack format is portable
  in both directions and is the same artifact iCloud Drive replicates for
  sync (§4.3). On import, the receiver MUST validate `manifest.json` (incl.
  the existing checksum + row-counts guard, generalised from
  `lib/db/core/checksum.ts`) and every attachment's sha256, **then run
  `auditLedger` for semantic integrity (§4.9)**, then atomically swap into
  place; refuse a tampered, partial, or audit-failing pack with a clear
  error.
- **Raw `.db` interop still works.** Users who only want the database (no
  attachments) can export a bare `.sqlite3` via `VACUUM INTO` and import it
  on either side; the `entry_attachments` table is simply empty.
- **CSV export:** reproduce `GET /api/export/transactions` (names + tags
  resolved via joins); offer via the share sheet (`lib/csv.ts`).
- **Backups:** the web app keeps timestamped **`.finch.bak` packs** under
  `${FINCH_DB_DIR}/finch-<ts>.finch.bak` (`/api/backups`, `restore-backup`).
  Restoring a backup brings the database AND every receipt back. Frequency
  + retention are user-configurable in Settings (persisted in `app_state`
  → travel with the database in every pack). Native SHOULD offer the same
  shape — periodic local pack snapshots in a dated folder, restore-from-
  snapshot, same two settings exposed in the app's Settings.
- **No silent schema forks.** Any new column or table either app needs
  (notably **receipt attachments**, §2.5) MUST land in the shared
  `lib/db/schema.ts` with a coordinated migration so packs round-trip
  unchanged between web and native.
- **Cross-app implications for the web app.** Shipping this native plan
  required three coordinated web-app changes so the apps stay file-
  compatible. **Two are now shipped; one remains open.**
  1. ✅ **Add the `transaction_attachments` table** + a server-side
     attachments directory (§2.5) — **shipped via PR #106**
     (`plans/done/RECEIPT_PHOTOS_PLAN.md`). Schema in
     `frontend/lib/db/schema.ts`; resolved on-disk under `FINCH_DB_DIR`
     via `frontend/lib/db/paths.ts`. _(Subsequently renamed to
     `entry_attachments` by the DE migration — §2.5.1.)_
  2. ✅ **Add ledger CRUD** to the web app — **shipped via
     `plans/done/LEDGER_CRUD_PLAN.md`** (2026-06-06). Four new
     mutations + matching store actions + DB-backed cosmetics + live
     counts + per-device persisted active ledger + ordered cascade
     delete with on-disk attachment sweep. The switcher's "New ledger"
     dialog + Settings › Ledger edit/default/danger-zone-delete dialogs
     surface them. Decision §14.8 satisfied; both apps will now have the
     same CRUD surface on the shared schema.
  3. ✅ **Teach `/api/export` and `/api/import` the `.finch` pack format**
     (formerly raw `.db` only) — **shipped via PR #107**
     (`plans/done/PACK_FORMAT_PLAN.md`). `GET /api/export?withAttachments=1`
     emits a pack; `POST /api/import` magic-byte-routes packs vs bare DBs.
     End-to-end byte-identical round-trip verified.

---

## 9. Offline, persistence & backup

- **Local working files are the source of truth** (web-app style). On-device
  SQLite + an `attachments/` folder in the app's container; WAL mode (matches
  the web's `better-sqlite3` setup).
- **Persistence is implicit** (it's a local file) — no "request persistent
  storage" dance the PWA needed.
- **Sync via iCloud Drive packs (§4.3).** The auto-packer writes a `.finch`
  pack to a user-visible folder in the app's iCloud Drive container on a
  debounced schedule (~30 s idle after a mutation, and on app background)
  and on an explicit "Sync now." iCloud Drive replicates the file; the
  receiving device validates and atomically swaps in the unpacked contents.
- **Backups doubled into the pack history.** Successive packs in a dated
  folder are also the user's restore points — the same artifact serves
  cross-device sync + local backup. The web ships the same idea today
  via `.finch.bak` files (frequency + retention persisted in `app_state`
  so they travel with the database; see `done/PACK_FORMAT_PLAN.md`).
- **Crash/atomicity:** mutations run in transactions; the "mutate →
  re-derive → publish" loop treats a failed write as a no-op and never
  leaves the cached `current_balance` diverged (recompute on the same path
  the web app does). The pack swap is **atomic** — write to tmp, validate,
  rename — so a half-finished sync never overwrites the working files.

---

## 10. Security & privacy

- **Local-first = strong default privacy:** no account, no server, no
  telemetry. Preserve this as a product promise.
- **Biometric app lock:** optional Face ID/Touch ID/Optic ID gate on launch and
  on sensitive actions (export, delete-all, base-currency change), with passcode
  fallback (`LocalAuthentication`).
- **Encryption at rest:** **Decision — file-protection only in v1.** Write
  the live DB with `completeUnlessOpen` (readable while the app runs;
  protected at rest when the device is locked + idle) and the pack with
  `complete` (protected whenever the device is locked). No SQLCipher in
  v1 — it complicates `.db` and pack interop with the web app, and no
  threat model has been raised that justifies it. Revisit if one ever is.
- **App Store privacy:** the nutrition label should be able to say "no data
  collected." Keep it that way — any future analytics MUST be opt-in and local.
- **Exports leave the sandbox:** treat share/export as the moment data leaves
  finch's control; confirm destructive/outbound actions.

---

## 11. Accessibility & localization

- **Dynamic Type** across all text incl. the big display numerals (scale, don't
  truncate). **VoiceOver** labels on every control (the web app already did an
  a11y pass — icon-only buttons have labels; carry the same rigor). Decorative
  charts are accessibility-hidden **with** a text summary (e.g. "Spending trend:
  up 8% vs last month").
- **Contrast:** the dark `muted-foreground` was tuned to ~6:1 (WCAG AA) in the
  web app — preserve that when porting tokens.
- **Localization & formatting:** all money via locale + currency-aware
  formatters; dates via `Date.FormatStyle`. Multi-currency is core, so never
  hard-code symbols. **RTL** layout support. The seed data is multi-currency
  (USD/SGD/CNY/JPY) — use it to test formatting breadth.
  > **Cross-app note (updated 2026-06-07):** the web app's i18n approach
  > is ✅ **shipped via PR #113 (foundation) + PR #115 (mass extraction +
  > `zh-CN` coverage)**; design record `plans/done/I18N_PLAN.md`. Stack:
  > `next-intl` + `messages/<locale>.json` catalogs, English base + Simplified
  > Chinese (`zh-CN`) for v1, ICU MessageFormat plurals, structured server-
  > error shape `{ code, params }` so mutation errors translate client-
  > side. The web's *data* layer is locale-neutral: translations live in
  > app chrome only, **never in the database or in `.finch` packs**. A pack
  > built on Apple in Japanese opens on the web in Chinese with no
  > translation churn (only user-typed category names etc. cross over,
  > which is correct).
  >
  > **The Apple side is independent** — use the platform's native i18n
  > (`Localizable.strings` / `Localizable.stringsdict` for chrome; CLDR
  > plurals via `Foundation`; `Date.FormatStyle` / `Decimal.FormatStyle`
  > for formatting). Catalogues don't need to mirror the web's JSON
  > shape — keep them idiomatic Apple. **Decision to confirm during
  > native build**: which locales ship on day 1. Web's `en + zh-CN`
  > picks a floor; native MAY ship more from the start since Apple
  > makes adding a locale cheap (just a new `.strings` bundle).
- **Reduce Motion / Increase Contrast / Bold Text** honoured.

---

## 12. Testing & quality direction

- **Parity suite (the headline requirement):** `FinchCore` MUST pass a test
  suite derived from the web app's `bun test lib` cases. Practical path: export
  the existing fixtures/expected values (derive deltas, FX conversions, budget
  progress, reconcile math, anomaly z-scores, forecast figures, rules
  evaluation) as JSON golden files and assert the Swift implementation matches
  to the cent. This is what keeps two implementations honest (§4.4).
- **Projection parity (DE):** for every golden DB fixture, native's
  `projectState` MUST emit the same `Tx` / `AccountRow` rows as the TS
  projection — same ids (the migration's id-reuse policy makes this
  byte-identical for pre-DE fixtures), same `splits` sign convention, same
  filtering of opening / equity legs (§2.6). One ported case per row of the
  projection-contract table covers it.
- **Audit parity (DE):** for every fixture DB (golden + property-generated),
  native's `auditLedger` (§4.9) MUST return the same typed problem set as the
  TS implementation — empty for clean DBs, matching outcomes for seeded-
  corruption fixtures (one per problem class: unbalanced, unsealed,
  currency-mismatch, kind-shape mismatch, cross-ledger leg, global TB ≠ 0,
  cached-balance drift, `amount ≠ amount_base` on a base-currency leg).
- **Golden `.db` fixtures:** check in a sample finch `.db` (or generate from the
  shared seed) and assert open/migrate/project round-trips, plus cross-app
  interop (write on web, read on native). The migration must be a no-op on a
  DB already at `2026-06-14T00:00:00Z`; `auditLedger` must report clean after
  every round-trip.
- **Snapshot tests** for key screens in light/dark, a few Dynamic Type sizes,
  and iPhone/iPad/Mac size classes.
- **Per-increment gate** (mirror CI discipline): build + unit/parity tests +
  UI snapshot smoke, green before merge. Each milestone "ships a working,
  verifiable build" (§1).

---

## 13. Suggested phasing (direction, not a schedule)

Milestones as coherent slices, each independently shippable:

1. **`FinchCore` + read-only mirror over the DE schema.** GRDB on the verbatim
   shared schema (entries + postings + entry_tags + entry_attachments +
   entries_fts + the seal/posting/balance triggers, §2.1) at
   `SCHEMA_VERSION = 2026-06-14T00:00:00Z`. Seed the three system equity
   categories per ledger via `ensureSystemCategories`. Port the `Tx`
   projection (§2.6), the §2.4 selectors, and `auditLedger` (§4.9). Parity
   suite green incl. projection-parity + audit-parity (§12). A read-only
   iPhone app (Accounts/Activity/Budgets/Insights) over an imported `.finch`
   pack.
2. **Entry + core CRUD.** Add transaction (all kinds), transaction detail
   edits, pending confirm, budgets, scheduled post-now, **ledger CRUD**
   (§2.1; web-side ✅ shipped via `plans/done/LEDGER_CRUD_PLAN.md` PR #109).
    Entry CRUD goes through a Swift port of the `lib/db/core/entries.ts`
    chokepoint (`postEntry` / `rebuildEntry` / `deleteEntry`) — the same
   single write path the web uses. The two `rebuildEntry` adapter
   preconditions called out in §2.6 (forward `cleared_at`; pass explicit
   `amountBase` for pinned rates) apply verbatim. Now "usable for real."
3. **Adaptive iPad/macOS.** `NavigationSplitView`, macOS menus/keyboard, ⌘K;
   both distribution paths set up (§4.8).
4. **Power features.** Reconcile, rules engine + builder/backfill, transfers,
   merchants/categories/tags admin, saved searches, bulk recategorise,
   FX/base tools.
5. **Pack engine + iCloud Drive sync (§4.3, §2.5.3).** Implement the
   `.finch` pack format end-to-end on the native side: build, validate,
   atomic swap, debounced auto-pack, manual "Sync now," conflict-copy UX.
   **Web-side status (2026-06-07):** all three §8 cross-app implications
   are ✅ shipped — receipt attachments (PR #106), `.finch` pack format
   (PR #107), ledger CRUD (PR #109). The web is the canonical reference
   for both the on-disk shape and the manifest contract. Pack manifest
   `row_counts` keys are the DE-era keys (`entries` / `postings` /
   `entry_tags` / `entry_attachments`); old packs still import because
   migrations run on the swapped-in file (§4.6).
6. **Native upside — part 1 (§7).** App Intents/Siri (dispatching through
   `postEntry`, §7), Share-Extension receipts (writes to
   `attachments/<entry_id>/...` — the rename from §2.5; ids are reused by
   the DE migration, so the path structure is stable across the cutover),
   Spotlight, notifications, biometric lock.
7. **Native upside — part 2: Widgets / Live Activities / Watch.** Deferred
   from phase 6 by decision (§14); same data layer, mostly UI on top.
8. **Row-level sync (the full §4.3-C), if ever pursued.** CloudKit or
   server sync atop the UUID-ready, single-choke-point mutation layer.
   Not on the current roadmap; the pack model in phase 5 is the answer
   for the foreseeable future.

---

## 14. Resolved decisions (2026-06-06)

The eight open questions from the prior revision are answered here in plain
language. Each points at the sections of the doc that now reflect it.

1. **Sync via iCloud Drive *file packs* — not row-level sync.** The app
   periodically zips the SQLite database + the `attachments/` folder into a
   single `.finch` pack and writes it to a user-visible folder in the app's
   iCloud Drive container. iCloud replicates the file; the other device
   validates it and unpacks. iCloud is used purely as a dumb file mover.
   Conflicts are last-writer-wins at the pack level (iCloud keeps a conflict
   copy if both devices wrote offline). → §4.3, §8, §9, §2.5.3.
   **Pack format itself: ✅ shipped on the web (PR #107)** — the native
   app reuses the same format end-to-end (build, parse, atomic-swap, manifest
   schema, sha256 integrity). What remains for native is the **iCloud Drive
   *delivery* layer** (the auto-pack debounce + folder-watcher + conflict-
    copy UX). Reference implementation: `frontend/lib/db/core/pack.ts`.

2. **Plain font, no editorial serif in v1.** Use the system sans-serif on
   Apple platforms (matching the live web look). Numerals tabular, Dynamic
   Type throughout. The prototype's editorial serif remains an option to
   revisit later. → §5.2.

3. **Keep encryption simple.** Rely on the platform's file-protection
   classes (`completeUnlessOpen` for the live DB, `complete` for the pack at
   rest). No SQLCipher in v1; revisit only if a real threat model is
   raised. → §10.

4. **Receipt attachments are designed *now*, and the files live *outside*
   the SQLite database.** A new `transaction_attachments` table stores
   pointers only (`rel_path`, `sha256`, mime, size); the actual photos and
   PDFs live under `attachments/<transaction_id>/<attachment_id>.<ext>` and
   travel alongside the DB inside every `.finch` pack. This table is added
   to the shared schema so both apps adopt it together. → §2.5 (whole
   subsection), §3 row 40, §8 cross-app implications. **✅ Shipped on the
   web (PR #106)** — schema, upload + serve routes, EXIF-strip + HEIC→JPEG
   transcode pipeline, transaction-detail UI + lightbox all live. Native
   adopts the schema verbatim; the file pipeline (Share Extension intake +
   PhotosPicker on iOS) is the part native still needs to build.

5. **OS floor: iOS 26 / iPadOS 26 / macOS 26.** A modern floor lets the app
   use Swift Charts, App Intents, `@Observable`, `NavigationSplitView`, and
   WidgetKit without compatibility shims. → §4.7.

6. **Mac distribution: both the Mac App Store *and* a notarised direct
   download.** Single Xcode target, two distribution paths — App Store for
   discovery and auto-update, notarised direct download for a local-first,
   file-portable app and users who prefer non-store binaries. → §4.8.

7. **Widgets deferred.** Native upside in v1 leads with App Intents/Siri,
   Share-Extension receipts, Spotlight, notifications, and the biometric
   lock. Widgets, Live Activities, and the Watch app come in a later
   phase. → §7 (widgets bullet), §13 phase 7.

8. **Ledger CRUD — *for both apps*.** Users can create, rename, and delete
   ledgers. The web app currently ships with 4 seeded ledgers and no
   creation path; that gap is closed as a coordinated cross-app change so
   packs continue to round-trip. → §2.1 (ledger entity), §3 row 39, §8
   cross-app implications.

### 14.1 Smaller follow-up questions opened up by these decisions

Recorded so they don't get lost — none are blockers; all can be settled
during the relevant phase.

- **Pack cadence + sweep policy.** What's the right idle-debounce (~30 s?)
  before auto-packing, and how often do we sweep orphaned attachment files
  off disk (every pack? a periodic vacuum?). Tune after first usage.
- **Conflict-copy UX.** When iCloud surfaces a conflict copy, what does
  the user see and what's the merge-or-discard affordance? An "open both,
  compare counts, pick one" sheet is the natural first cut.
- **`.finch` UTI + extension registration.** Register the document type as
  a child of `UTType.zip` so Files/Finder/Quick Look know what to do.
  Confirm during phase 5 (pack engine).
- **Web-app pack support timing.** When does the web app gain pack
  export/import + ledger CRUD + the attachments table — alongside native
  phase 5, or earlier? A small product/release call.
- **iCloud folder naming + visibility.** Show the folder in Files (so
  users can copy a pack out) but keep it under the app's container — a
  clear `finch/` subfolder. Confirm with a brief design pass.

## 15. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Logic drift between TS and Swift implementations | High | Parity suite from web fixtures (§12); shared JSON wire-formats for rules/splits |
| `.db` interop breaks on a schema fork | Medium | Single shared schema + version lineage; golden cross-app round-trip test (§8/§12) |
| Float vs Decimal money discrepancies vs web | Medium | Compute in Decimal, narrow to REAL at the boundary; cent-level parity assertions (§4.5) |
| Reproducing bespoke charts (Sankey, heatmap) | Medium | Swift Charts where it fits; `Canvas` for the rest; snapshot tests (§5.3) |
| SwiftData temptation erodes interop | Medium | Decision recorded: GRDB on the verbatim schema (§4.2) |
| Encryption choice constrains interop | Low | Decision recorded: file-protection only in v1 (§10); SQLCipher reconsidered only if a real threat model lands |
| Scope creep into bank import / row-level sync too early | Medium | Hold the §7 boundary; pack-based sync (§4.3) is the answer for the foreseeable future |
| Pack format drifts between web and native | Medium | Single shared `manifest.json` schema; checksum + per-file sha256; cross-app round-trip test (§8, §12) |
| Orphaned attachment files accumulate on disk | Low | Pack-builder sweep + periodic vacuum keep on-disk files ↔ DB rows in sync (§2.5.1) |
| macOS feels like a blown-up iPad | Low | NavigationSplitView + real menus/keyboard; Catalyst only as fallback (§4.1) |
| DE migration outcome divergence between web and native | Medium | Single shared `MIGRATIONS` lineage stamped `2026-06-14T00:00:00Z`; cross-app round-trip test (§8 + §12) opens a web-migrated DB on native (and vice versa) and asserts the second-side migration is a no-op + `auditLedger` clean. Defensive `VACUUM INTO '<file>.pre-de.bak'` snapshot is the rollback (§4.6). |
| `auditLedger` divergence between web and native | Low | Single Swift port of the audit SQL; golden DB fixtures with seeded corruptions (one per problem class) assert the same typed problem set on both sides (§4.9 + §12 audit parity). |
| Native write path bypasses the entries chokepoint | Medium | All write surfaces (CRUD, App Intents, Share Extension, scheduled posting) MUST go through the Swift port of `postEntry` / `rebuildEntry` / `deleteEntry` (§2.6, §7); the schema triggers + audit are the second line of defence, but architecting around the chokepoint is the first. |

## 16. Out of scope / non-goals

- **Bank / statement / OFX / CSV *import* & live feeds.** Manual + Share-
  Extension entry + reconcile is the model (carried over from the web product).
- **Apple Wallet / bank account linking.** Same reason.
- **A mandatory cloud account or server-side multi-user.** finch is single-
  user/household, local-first.
- **Telemetry / analytics by default.** "No data collected."
- **A web-view wrapper.** The whole point is native surfaces (§1.1, §7).
- **Redesigning the domain model.** It is inherited (§2).

## 17. Glossary & references

- **Ledger / base currency / display currency / amount vs amount_base / locked
  rate / pending vs confirmed / cleared vs reviewed / transfer group / split /
  counterparty / holding / rule** — defined in §2 and, authoritatively, in
  `plans/database_design_en.md`.
- **Entry / posting / sealed / dedup_hash / residue leg / system equity
  category / `auditLedger` / chokepoint** — the double-entry vocabulary.
  Defined in §2.1, §2.2, §2.3.1, §2.6, and §4.9 of this brief; canonically
  in `plans/done/DOUBLE_ENTRY_PLAN.md §2-§3`.
- **Canonical code references:** canonical schema `frontend/lib/db/schema.ts`
  (DE additions folded in; the historical `frontend/lib/db/core/entries-schema.ts`
  is the PR-A standalone kept as a reference); write chokepoint
  `frontend/lib/db/core/entries.ts` (`postEntry` / `rebuildEntry` / `deleteEntry`
  / `auditLedger` / `ensureSystemCategories` + the `MIGRATIONS` array +
  `applyMigrations` runner); sealed-write helper `frontend/lib/db/core/sealed-entry.ts`;
  pack engine `frontend/lib/db/core/pack.ts`; checksum
  `frontend/lib/db/core/checksum.ts`; projection
  `frontend/lib/db/state.ts` (`projectState`); mutations
  `frontend/lib/db/mutate.ts` (the 53-line dispatcher) → per-domain handlers
  at `frontend/lib/db/domain/<x>/mutations.ts` (delegate to the chokepoint
  under DE); central action-name → Args-type registry
  `frontend/lib/db/domain/_args.ts`; read-side shims `frontend/lib/db/queries/<x>.ts`;
  derivations `frontend/lib/select.ts`; rules `frontend/lib/rules/*`; money
  `frontend/components/use-money.ts` + `frontend/components/use-currency.ts`
  (the display-currency hook; renamed from `currency-provider.tsx` in
  PR #137) + `frontend/lib/fx.ts`; reconcile
  `frontend/lib/reconcile.ts`; recurrence `frontend/lib/recurrence.ts`;
  budgets `frontend/lib/budgets/*`; tokens `frontend/app/globals.css`;
  design intent `plans/frontend_design/`.
- **Related plans:** `MASTER_PLAN.md` (what shipped); `DOUBLE_ENTRY_PLAN.md`
  (the storage rewrite this brief now inherits); `I18N_PLAN.md` (the web
  i18n approach; Apple side is orthogonal — §11); `PWA_PLAN.md`
  (superseded by §1.1 of this brief, kept as a fork-in-the-road record);
  `FEATURE_IDEAS.md` / `INSPIRATION_IDEAS.md` (idea catalogs); and the
  shipped design records in `plans/done/` —
  `done/RECEIPT_PHOTOS_PLAN.md` (web-side attachments built on §2.5 of
  this brief), `done/PACK_FORMAT_PLAN.md` (web-side `.finch` export/import),
  `done/LEDGER_CRUD_PLAN.md` (web-side ledger CRUD — closes the last §8
  cross-app implication), `done/CATEGORIES_LEVEL3_PLAN.md` (web-side
  3-level taxonomy), `done/RECONCILE_PLAN.md`, `done/RULES_ENGINE_PLAN.md`,
  `done/FILE_BACKED_DB_PLAN.md`.
