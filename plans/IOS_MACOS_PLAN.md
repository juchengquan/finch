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
record in `plans/`. Last updated: 2026-06-06._

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

---

## 2. The domain model you are inheriting (the real spec)

This is the most valuable thing the native team is handed. Do not paraphrase it
from screenshots — read the source.

| Concern | Canonical source in `frontend/` | What it is |
|---|---|---|
| Relational schema (tables, indexes, triggers, FTS5) | `lib/db/schema.ts` | The full `CREATE …` SQL string + the version/migration runner |
| Schema rationale & business rules | `plans/database_design_en.md` | The design doc behind the schema (decisions #18–#25 etc.) |
| Server projection contract | `lib/db/repo.ts` (`ProjectedState`) | The exact shape the client consumes |
| Mutations (the write API) | `lib/db/mutations.ts` | Every server-side action and its effects |
| Pure derivations (the read brains) | `lib/select.ts`, `lib/derive.ts` | All computed figures — see §2.4 |
| Rules engine | `lib/rules/{engine,types,describe}.ts` | Condition/Action model + evaluator |
| Reconcile math | `lib/reconcile.ts` | Cleared-balance / difference selector |
| Recurrence math | `lib/recurrence.ts` | Scheduled-template occurrence generation |
| Budget cycles & rollover | `lib/budgets/{period,rollover}.ts`, `lib/select.ts` | Cycle windows, progress, auto-rollover |
| FX conversion | `lib/fx.ts`, `components/use-money.ts` | Rate lookup + base↔display conversion |
| Installments | `lib/installment.ts` | Finite-plan progress derivation |
| Counterparty matching | `lib/matcher/counterparty.ts` | Name-resolution on write |

### 2.1 Entities (and the relationships that matter)

All data is scoped to a **ledger**; ledgers never share rows. The entity set:

- **ledger** — an isolated set of books with its own `base_currency`. Seeded
  ledgers: personal, family, business, travel.
- **account** — typed (`savings | credit_card | investment | cash | fx |
  virtual`), one fixed `currency`, an `opening_balance` (+ a locked
  `opening_balance_base`), a cached `current_balance` (derived — see §2.3), an
  `include_in_net_worth` flag, archive state, and a reconcile checkpoint
  (`last_reconciled_at/_balance`).
- **account_group** / **budget_group** — purely organisational buckets;
  deleting a group SET NULLs its members (they fall into "Ungrouped").
- **category** — a **2-level** tree (`parent_id`, no grandchildren), with
  `kind` (`expense | income | transfer`), icon, colour. Delete promotes
  children to top level.
- **tag** — free labels; many-to-many with transactions via `transaction_tags`.
- **counterparty** (merchant) — canonical payee, `is_verified`. A transaction's
  `counterparty_id` FK lets a rename follow history; SET NULL on delete keeps
  the raw description.
- **transaction** — the core row. Dual amounts (`amount` native +
  `amount_base` ledger-base, with a locked `exchange_rate`), `kind` (`income |
  expense | transfer | adjustment | refund`), `status` (`pending |
  confirmed`), and three independent triage timestamps: `confirmed_at`,
  `cleared_at` (reconcile), `reviewed_at` (review queue). Plus
  `transfer_group_id`, `refunded_transaction_id`, `source_template_id`,
  `applied_rule_ids` (JSON), and FTS-indexed `description`/`notes`.
- **transaction_split** — ad-hoc category splits that override the parent's
  category in aggregations; split amounts MUST sum to the parent's.
- **transfer_group** — the pairing row for a transfer's two legs; carries the
  from/to currencies + locked rate, never duplicating leg amounts.
- **budget** — named expense limit or income target with a cycle
  (`frequency`/`start_date`), optional rollover (+ cap), staged
  `pending_amount` (next-cycle change), `last_rolled_period`, and
  account/category filter sets (JSON).
- **scheduled_template** (+ **scheduled_splits**) — recurring income/expense/
  transfer with cadence, `auto_post`, `next_run`/`last_run`, optional
  `installment_total` (finite plans), `max_executions`.
- **holding** — a position inside an investment account (`shares`,
  `cost_basis`, `last_price`); guarded by a trigger to investment accounts only.
- **exchange_rate** — `(date, currency) → rate`; the locked-rate source.
- **rule** — one if-then rule (JSON `condition` tree + ordered `actions`),
  `priority`, `is_active`, `run_on_edit`.
- **app_state** — small KV slices (mobile tab order, per-ledger display
  currency, transitional queues).
- **db_metadata** — single row: app name, **schema version**, app version,
  export checksum + row counts (the import-integrity guard).

> **Requirement:** the native model MUST represent every entity and every
> column above. Even columns that look "internal" (e.g. `opening_balance_base`,
> `applied_rule_ids`, `last_rolled_period`) carry behaviour or audit value and
> are required for `.db` interop (§8).

### 2.2 The status / triage state machine (don't collapse these)

Four orthogonal axes live on a transaction. They answer different questions and
MUST stay independent:

| Axis | Column | Question | Affects balances? |
|---|---|---|---|
| Lifecycle | `status` (pending→confirmed) | "Is this real yet?" | Confirmed only |
| Statement | `cleared_at` | "Has it appeared on a real statement?" (reconcile) | No |
| Review | `reviewed_at` | "Have I eyeballed it and it's correct?" | No |
| Provenance | `applied_rule_ids` | "Why is it categorised this way?" | No |

A confirmed row can be uncleared and unreviewed; a rule can pre-clear review at
insert. The web app shipped these as separate features (PRs for reconcile, rules,
review queue); the native app MUST not flatten them into one "done" flag.

### 2.3 Money & currency invariants (load-bearing)

These rules are the difference between a correct ledger and a plausible-looking
wrong one. They are non-negotiable.

1. **Two amounts per transaction.** `amount` is the **native** figure in the
   row's own `currency`; `amount_base` is the same value in the **ledger's base
   currency**, computed with a **rate locked at write time** (`exchange_rate`).
   A later edit to the rate table MUST NOT reshape history.
2. **Balances are in the account's currency.** A confirmed insert moves
   `accounts.current_balance` by the native amount when the row currency matches
   the account, else by `amount_base`. `current_balance` is **derived/cached**,
   never the source of truth — it is recomputed from `opening_balance` + Σ
   confirmed rows (`recomputeAccount`).
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
   basis (`opening_balance_base` + Σ `amount_base`). Same-currency-as-base
   accounts are always 0.
7. **Refunds** are `kind='refund'`, positive, and **net against their category**
   (they reduce expense, not add income). Adjustments (`kind='adjustment'`) and
   transfers are excluded from spend/cash-flow/budget math.
8. **Splits override the parent** category in all aggregations and MUST sum to
   the parent (native and base).

> **Direction (money type):** the on-disk format is SQLite `REAL` (a float),
> rounded to 2dp in the app layer — see §4.5 for why the native app should
> still compute in `Decimal`/minor-units and only narrow to `REAL` at the
> storage boundary.

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
| 29 | Categories admin (2-level tree, icon/colour) | Tree editor; create/edit/delete w/ promote-on-delete | Outline/`DisclosureGroup` | 2 | `categories/page.tsx` |
| 30 | Tags admin | Tag CRUD w/ colour | `List` + edit | 2 | `tags/page.tsx` |
| 31 | Rules: list, builder, backfill w/ preview, inline create-rule | Rule list; condition/action builder; backfill preview; "create rule" after manual recat | Form builder; sheet | 2–3 | `rules/page.tsx`, `rule-builder-sheet.tsx`, `lib/rules/*` |
| 32 | Transaction detail: recat, split, tags, refund, review/cleared toggles, FX card, rule provenance, delete | Full detail w/ all inline edits + provenance | Detail sheet; menus; swipe | 1 | `transaction-detail.tsx` |
| 33 | Settings/Account: theme, mobile-tab editor, sample data, DB card, export/import, backup/restore | Appearance, data/backup, export/import `.db`+`.csv` | Settings screen; Files/share | 1–2 | `settings/account/page.tsx` |
| 34 | Settings/Ledger: active ledger, display currency, base-currency change, exchange rates | Ledger settings + FX book + base-change tool | Pickers; warned destructive action | 2 | `settings/ledger/page.tsx`, `exchange-rates.tsx` |
| 35 | Ledger switcher | Switch active ledger (scopes everything) | Sheet / sidebar menu / macOS toolbar | 1 | `ledger-switcher.tsx` |
| 36 | Command palette (⌘K) | Jump-to-anything search | macOS ⌘K; iOS Spotlight (§7) | 2 (mac 1) | `command-palette.tsx` |
| 37 | Responsive shell (sidebar/bottom-bar, breadcrumbs) | Adaptive nav (tab bar vs sidebar/split) | `TabView`/`NavigationSplitView` | 1 | `PageShell.tsx` |
| 38 | Holdings management (add/edit/price/delete) | Position CRUD + price update | Form sheets | 2 | `account-holdings.tsx` |

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

**Direction: A now, with C as a planned later phase; avoid B as the primary
model.** Local-first is the finch-native instinct and the only one that needs
no infrastructure. Phase the sync engine (C) in *after* parity, and design for
it from day one by adopting UUID PKs for native-created rows (§4.6) and keeping
all mutations funnelled through one choke point (so a future sync log can
observe them). The `/api/mutate` action contract (action-name + args → full
`ProjectedState`) is a useful *reference* for that choke point's shape, and
remains available if the team ever wants B for a specific deployment.

> Note: `ProjectedState` returns the **whole** projection on every mutation —
> fine at personal-finance data sizes, and a clean model for "recompute, then
> re-render." The native app SHOULD adopt the same "mutate → re-derive →
> publish" loop (a single `@Observable` store fed by `FinchCore`).

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

### 5.2 Typography (a real decision to make)

The **live web app maps both `--font-sans` and `--font-serif` to Inter** — i.e.
the editorial *serif* in the prototype (`Instrument Serif`) was never actually
shipped. The native app must choose:

- **Option A (recommended): restore the editorial serif** for large display
  numerals and section/hero titles (the prototype's intent — a warm,
  un-banking feel), with the system font for body/UI and a mono for technical
  rows (rates, ids). This is the stronger brand and is trivial on Apple
  platforms (bundle the serif; use it only at display sizes).
- Option B: match the shipped web look (system/Inter everywhere). Safer,
  blander.

Either way: numerals MUST be **tabular/monospaced-figure** for column
alignment, and all type MUST support **Dynamic Type** (§11).

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
  habitual entries (pairs with `recentExpenses`).
- **Widgets (WidgetKit):** Home/Lock-Screen widgets for net worth + sparkline,
  this-month budget rings, the month forecast, and the weekly digest. All are
  existing selectors; widgets read the shared `.db` from an App Group container.
- **Live Activities / Lock Screen:** optional "budget remaining this month"
  glanceable; reconcile-session progress.
- **Share Extension → receipts:** the long-deferred receipt-photo feature
  (`FEATURE_IDEAS §4.1`) is *natural* here — share a photo/PDF into finch to
  create/attach to a transaction. (Needs the `transaction_attachments` table
  the web plan sketched; design it once, shared.)
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

- **`.db` compatibility (primary interop):** because the native app reuses the
  exact schema (§4.2) and version lineage (§4.6), a finch SQLite file is
  portable both directions. Export = `VACUUM INTO` a temp file then hand to the
  share sheet / Files; import = validate `db_metadata` (the checksum + row
  counts integrity guard exists — `lib/db/checksum.ts`), then swap. **Requirement:**
  honour the metadata integrity check on import; refuse a tampered/corrupt file
  with a clear error.
- **CSV export:** reproduce `GET /api/export/transactions` (names + tags
  resolved via joins) for a transactions CSV; offer via share sheet. (See
  `lib/csv.ts`.)
- **Backups:** the web app keeps timestamped backups (`/api/backups`,
  `restore-backup`). Native SHOULD offer the same: periodic local snapshots +
  optional iCloud Drive copy, restore-from-snapshot.
- **No silent schema forks:** any new column/table the native app needs (e.g.
  receipt attachments) MUST be added to the **shared** schema + migration
  lineage so both apps stay file-compatible.

---

## 9. Offline, persistence & backup

- **The file is the source of truth** (as today). On-device SQLite in the app's
  container; WAL mode is fine and matches the web's `better-sqlite3` setup.
- **Persistence is implicit** (it's a local file) — no "request persistent
  storage" dance the PWA needed.
- **iCloud:** offer the `.db` (and backups) as documents in the app's iCloud
  container for cross-device *file* sync — the local-first parallel to the
  web's export/import. (True live multi-device sync is §4.3-C, later.)
- **Crash/atomicity:** mutations run in transactions; the "mutate → re-derive →
  publish" loop should treat a failed write as a no-op and never leave the
  cached `current_balance` diverged (recompute on the same path the web app does).

---

## 10. Security & privacy

- **Local-first = strong default privacy:** no account, no server, no
  telemetry. Preserve this as a product promise.
- **Biometric app lock:** optional Face ID/Touch ID/Optic ID gate on launch and
  on sensitive actions (export, delete-all, base-currency change), with passcode
  fallback (`LocalAuthentication`).
- **Encryption at rest:** evaluate **SQLCipher** (or rely on the iOS
  file-protection class `complete`/`completeUnlessOpen`). **Direction:** at
  minimum set strong file protection; offer SQLCipher as an opt-in for users who
  want at-rest encryption, noting it complicates raw `.db` interop (document the
  trade-off; an encrypted export is still importable by another finch instance
  with the key, but not by the web app).
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
- **Reduce Motion / Increase Contrast / Bold Text** honoured.

---

## 12. Testing & quality direction

- **Parity suite (the headline requirement):** `FinchCore` MUST pass a test
  suite derived from the web app's `bun test lib` cases. Practical path: export
  the existing fixtures/expected values (derive deltas, FX conversions, budget
  progress, reconcile math, anomaly z-scores, forecast figures, rules
  evaluation) as JSON golden files and assert the Swift implementation matches
  to the cent. This is what keeps two implementations honest (§4.4).
- **Golden `.db` fixtures:** check in a sample finch `.db` (or generate from the
  shared seed) and assert open/migrate/project round-trips, plus cross-app
  interop (write on web, read on native).
- **Snapshot tests** for key screens in light/dark, a few Dynamic Type sizes,
  and iPhone/iPad/Mac size classes.
- **Per-increment gate** (mirror CI discipline): build + unit/parity tests +
  UI snapshot smoke, green before merge. Each milestone "ships a working,
  verifiable build" (§1).

---

## 13. Suggested phasing (direction, not a schedule)

Milestones as coherent slices, each independently shippable:

1. **`FinchCore` + read-only mirror.** GRDB on the shared schema; port the
   projection + the §2.4 selectors; parity suite green; a read-only iPhone app
   (Accounts/Activity/Budgets/Insights) over an imported `.db`.
2. **Entry + core CRUD.** Add transaction (all kinds), transaction detail edits,
   pending confirm, budgets, scheduled post-now. Now "usable for real."
3. **Adaptive iPad/macOS.** `NavigationSplitView`, macOS menus/keyboard, ⌘K.
4. **Power features.** Reconcile, rules engine + builder/backfill, transfers,
   merchants/categories/tags admin, saved searches, bulk recategorise, FX/base
   tools.
5. **Native upside (§7).** App Intents, Widgets, Share-Extension receipts,
   Spotlight, notifications, biometric lock.
6. **Sync (§4.3-C), if pursued.** CloudKit or server sync atop the UUID-ready,
   single-choke-point mutation layer.

---

## 14. Open questions

1. **Sync ambition:** local-first only (file portability) for the foreseeable
   future, or commit to §4.3-C and pick CloudKit vs server now (it changes the
   ID + conflict design today)?
2. **Typography:** restore the editorial serif (§5.2-A) or match the shipped
   Inter look (B)?
3. **At-rest encryption:** SQLCipher opt-in vs file-protection-only — and how to
   message the interop trade-off?
4. **Receipt attachments schema:** design `transaction_attachments` now (shared
   across web + native) so the Share Extension has a home, or defer?
5. **Minimum OS versions:** which iOS/iPadOS/macOS floor? (Gates Swift Charts,
   App Intents, Observation, SwiftData-if-ever, WidgetKit features.)
6. **macOS distribution:** App Store only, or also Developer-ID notarised direct
   download (relevant for a local-first, file-portable app)?
7. **Apple Watch & widgets scope:** which selectors get glanceable surfaces in
   the first native-upside pass?
8. **Ledger creation:** the web app never shipped a "New ledger" mutation (4
   seeded ledgers). Does native add ledger CRUD, or inherit the same constraint?

## 15. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Logic drift between TS and Swift implementations | High | Parity suite from web fixtures (§12); shared JSON wire-formats for rules/splits |
| `.db` interop breaks on a schema fork | Medium | Single shared schema + version lineage; golden cross-app round-trip test (§8/§12) |
| Float vs Decimal money discrepancies vs web | Medium | Compute in Decimal, narrow to REAL at the boundary; cent-level parity assertions (§4.5) |
| Reproducing bespoke charts (Sankey, heatmap) | Medium | Swift Charts where it fits; `Canvas` for the rest; snapshot tests (§5.3) |
| SwiftData temptation erodes interop | Medium | Decision recorded: GRDB on the verbatim schema (§4.2) |
| Encryption complicates portability | Low | Make SQLCipher opt-in, document the trade-off (§10) |
| Scope creep into bank import / sync too early | Medium | Hold the §7 boundary; sync is a deliberate later phase (§4.3) |
| macOS feels like a blown-up iPad | Low | NavigationSplitView + real menus/keyboard; Catalyst only as fallback (§4.1) |

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
- **Canonical code references:** schema `frontend/lib/db/schema.ts`; projection
  `frontend/lib/db/repo.ts`; mutations `frontend/lib/db/mutations.ts`;
  derivations `frontend/lib/select.ts`; rules `frontend/lib/rules/*`; money
  `frontend/components/use-money.ts` + `frontend/lib/fx.ts`; reconcile
  `frontend/lib/reconcile.ts`; recurrence `frontend/lib/recurrence.ts`; budgets
  `frontend/lib/budgets/*`; tokens `frontend/app/globals.css`; design intent
  `plans/frontend_design/`.
- **Related plans:** `MASTER_PLAN.md` (what shipped), `RECONCILE_PLAN.md`,
  `RULES_ENGINE_PLAN.md`, `FILE_BACKED_DB_PLAN.md`, `PWA_PLAN.md` (the
  superseded "good enough" judgement), `FEATURE_IDEAS.md` / `INSPIRATION_IDEAS.md`.
