# Canonical web facts (transient — delete after drift fixes land)

Verified against the live web code at commit `22c9896` (= `feat/frontend` + the accountGroup
dead-code cleanup), SCHEMA_VERSION `2026-06-14T00:00:00Z`, on 2026-06-13. Use these EXACT facts
when correcting the iOS/macOS plans.

## A. Audit problem classes — `lib/db/core/entries.ts:708-822`
`auditLedger` emits **10** problem codes (the `AuditProblem.code` union):
`unsealed`, `unbalanced`, `too-few-legs`, `no-account-leg`, `currency-mismatch`,
`cross-ledger`, `base-identity`, `kind-shape`, `trial-balance`, `balance-drift`.
Meanings: **unsealed** = entry never sealed (torn write); **unbalanced** = an entry's postings don't
sum to 0; **too-few-legs / no-account-leg** = fewer than 2 legs / no account leg; **currency-mismatch**
= posting not in its account's currency; **cross-ledger** = posting references another ledger;
**base-identity** = `amount != amount_base` in the base currency (I9); **kind-shape** = an entry's legs
don't match its kind's expected shape; **trial-balance** = a ledger's postings don't sum to 0;
**balance-drift** = account cached balance ≠ balance derived from postings.
There is **NO** `missingCategoryLeg / missingCounterparty / duplicatePosting / orphanAttachment /
brokenTransfer / pinnedRateOutOfDate` — those names are fabricated.

## B. Migrations — `lib/db/core/schema.ts`
- `SCHEMA_VERSION` constant = `'2026-06-14T00:00:00Z'` (line 435).
- `MIGRATIONS` is a `Record<string, string[] | ((exec)=>Promise<void>)>` (line 441) with **many** dated
  entries (…`2026-06-05`, `-06`, `-07`, `-08`, `-09`, `-10`, `-11`, `-12`, and the double-entry
  table-creation entry `'2026-06-13T00:00:00Z'`). NOT "one entry."
- Runner = `migrate(exec, { fresh })` (≈ line 688). Fresh DBs: `ensureMetadataRow` stamps SCHEMA_VERSION.
  Existing DBs: replay every MIGRATIONS entry whose key sorts after the recorded version.
- The recorded version lives in the **`db_metadata.schema_version` TABLE column** (schema.ts:344,
  `ensureMetadataRow` :665) — **NOT** `PRAGMA user_version`.
- The `2026-06-14` double-entry **cutover data-move is INTENTIONALLY ABSENT** from MIGRATIONS — removed
  as dead code (no pre-DE databases exist pre-release; the canonical `SCHEMA` already carries the
  post-cutover shape; the cutover code lives only in git history). There is **NO `lib/db/cutover.ts`**
  and **NO `applyMigrations`** symbol — the runner is `migrate`.

## C. Schema shape — `lib/db/core/`
The whole schema is **one `export const SCHEMA` template literal** in `schema.ts` (≈ line 56). The only
split-out DDL constants are `ENTRY_ATTACHMENTS_DDL` (schema.ts:18) and `ENTRIES_FTS_DDL` (schema.ts:37).
The `entries` and `postings` table DDL live in **`lib/db/core/entries-schema.ts`** (lines 8 and 36).
There are **NO** per-table `ENTRIES_DDL` / `POSTINGS_DDL` constants.

## D. Chokepoint / domains (post-cleanup @ `22c9896`)
- Dispatcher `lib/db/mutate.ts` (53 lines) merges handler maps into one `ALL` map → exactly
  **74 entries / 74 unique actions / ZERO duplicates**. The old "77 entries, 3 accountGroup duplicates
  in `accounts/`" is GONE (removed by `22c9896`).
- **12** first-class domains have a `mutations.ts`; the **13th** merged handlers map is **`_app/`**
  (an escape-hatch domain, not first-class). Two first-class domains have NO `mutations.ts`:
  **`attachments`** (queries-only) AND **`budgetGroups`** (its 3 group actions live in `budgets/mutations.ts`).
- `lib/db/core/entries.ts` exports **13** callable functions (NOT 12): `ensureSystemCategories`,
  `isAccountLeg`, `dedupHash`, `postEntry`, `postSimple`, `postTransfer`, `postAdjustment`, `postOpening`,
  `recomputeAccountFromPostings`, `rebuildEntry`, `deleteEntry`, `resolveEntryRef`, `auditLedger`.
  (`postEntry` + 4 sugar wrappers `postSimple` / `postTransfer` / `postAdjustment` / `postOpening`.)
- Surviving cross-domain query imports = **4** (NOT 5): `transactions→attachments`,
  `budgets→budgetGroups`, `rules→counterparties`, `scheduled→counterparties`. The
  `accounts→accountGroups` dep was removed by the cleanup.
- `accounts/mutations.ts` is now **51 lines** (was 73). Sum of the 13 `mutations.ts` ≈ **1,313 lines** (was 1,335).

## E. Selector inventory — `lib/select.ts` (33 top-level exports)
Treat **32 as selectors** = all exports EXCEPT the `kindOf` Tx-kind classifier helper.
Canonical partition: **7 in Phase 1.0, 25 in Phase 1.5** (7 + 25 = 32).
**Canonical Phase-1.0 set (use in BOTH Phase 1.0 PLAN and Phase 1 DESIGN):**
`accountBalance, selectTransactions, categorySpend, budgetProgress, cycleWindow, merchantStats, anomalyScore`.
(`balanceSeries` / `netWorthSeries` are chart-series selectors → Phase 1.5, not 1.0.)

**All selectors are PURE.** No selector reads the DB. In particular `monthForecast` does NOT read
FX/RateSnapshot, and `weeklyDigest` does NOT read `app_state` for a configurable week-start (week start
is hardcoded ISO Monday). Any `Selectors.DBContext` / GRDB-reader / `throws` machinery justified by
"2 selectors hit the DB" is unfounded → drop it or restate as "all selectors are pure; no DB access."

**Exact signatures (verbatim from code):**
- `accountBalance(accounts: AccountRow[], accountId: string): number`
- `selectTransactions(txns: Tx[], opts: ListOptions): Tx[]`
- `categorySpend(txns: Tx[], ledgerId: string, month?: string): Record<string, number>`
- `budgetProgress(budget: BudgetRow, txns: Tx[], today: string, categories?: {id; parentId}[]): BudgetProgress`
- `cycleWindow(frequency: string, startDate: string, today: string, endDate?: string|null, isRecurring?: number): CycleWindow`
- `merchantStats(txns: Tx[], ledgerId: string): Map<string, MerchantStats>`
- `anomalyScore(tx: Tx, stats: Map<string, MerchantStats>, opts?: { minCount?=3; threshold?=2.5 }): AnomalyScore | null` — requires `s.count ≥ 2 && s.std ≠ 0`.
- `monthForecast(txns: Tx[], scheduled: ScheduledTemplate[], ledgerId: string, month: string, today: string): MonthForecast | null` — **algorithm: month-to-date actuals + daily-run-rate × days-remaining + upcoming scheduled/recurring; SINGLE month; past months collapse to actuals.** NOT linear regression, NOT 90-day, NOT multi-month, takes NO `accounts` param.
- `unrealizedFx(account: AccountRow, txns: Tx[], toBase: ToBase): number` — **per-account** (not a list; no holdings/exchangeRates params).
- `suggestCategory(txns: Tx[], ledgerId: string, description: string, counterpartyId?: string|null, opts?: { minCount?=1; minConfidence?=0.5 }): CategorySuggestion | null` — returns an object (category + confidence + count), not a bare id.
- `netWorthByMonth(txns: Tx[], accounts: AccountRow[], ledgerId: string, endMonth: string, n: number, toBase?: ToBase): {m; v}[]` — has `ledgerId`.
- `netWorthExplained(txns, accounts, ledgerId, endMonth, n, toBase?): {m,income,expense,adjustment,fx,net}[]`
- `recentExpenses(txns: Tx[], ledgerId: string, limit?=5): RecentExpense[]`
- `weeklyDigest(txns: Tx[], ledgerId: string, anchor: string): WeeklyDigest | null` — pure; ISO-Monday week start.

## F. Renamed symbols / paths
- `lib/db/schema.ts → lib/db/core/schema.ts`; `lib/db/entries.ts → lib/db/core/entries.ts`;
  `lib/db/paths.ts → lib/db/core/paths.ts`; `lib/db/seed.ts → lib/db/core/seed.ts`.
- `recomputeAccount → recomputeAccountFromPostings` (`entries.ts:507`).
- `components/merchant-picker-sheet.tsx → components/merchant-picker-dialog.tsx`;
  `components/rule-builder-sheet.tsx → components/rule-builder-dialog.tsx`;
  `refund-badge.tsx → components/ui/refund-badge.tsx`.
- DB indexes `idx_attach_entry / idx_attach_ledger → idx_eattach_entry / idx_eattach_ledger`.
- **`Tx.account` holds the account ID**, not the account name (`projectState` sets
  `account: String(p.account_id)`, `lib/db/state.ts:71`).
- Pack attachment on-disk path = `attachments/<entry_id>/<att_id>.<ext>` — built in `app/api/attachments/route.ts` as `path.posix.join('attachments', entryId, ...)`, and `entry_attachments.entry_id` is the FK. So plans using `<entry_id>` are CORRECT. (The `pack.ts:6` *comment* says `<transaction_id>` but it is itself stale — leftover from the dropped pre-DE `transaction_attachments` table. Do NOT "correct" `<entry_id>` to `<transaction_id>`.)
- Pack manifest is **NESTED**: `{ db: { sha256, row_counts, byte_size }, attachments: { … },
  pack_format_version, app_name, … }` (`pack.ts:43-60`) — NOT flat `db_sha256` / `attachment_count`.
- i18n: `lib/i18n-error.ts` holds the `I18nError` CLASS + wire helpers ONLY (no codes). Error code
  constants live in per-domain `errors.ts` files (≈ 14 distinct code constants; ≈ 65 total `error.*`
  strings across `lib/`). "~30 codes in `i18n-error.ts`" is wrong on both location and count.
- rollover coercion: `budgets/mutations.ts:50` → `rollover: args.rollover ? 1 : 0` (truthy → 0/1),
  NOT `Number(args.rollover)` at line 88.
- display-currency setter: the handler lives in `lib/db/domain/_app/mutations.ts` (writes the single
  `app_state` key `'displayCurrencyByLedger'`, a JSON map). `ledgers/mutations.ts:58-64` is
  `deleteLedger`'s cleanup of that same key, not the setter.
- `r2` helper is defined at `lib/db/core/entries.ts:18` (not line 24).
- `scripts/export-fixtures.ts` does NOT exist yet — it is a Phase 1.0 artifact **to be created**. Refer
  to it in the future/imperative, never as already existing.

## G. Fixture-export harness redesign (Phase 1.5 §4)
The old design (scrape a `CASES` array out of `lib/select.test.ts`) cannot work: that file is **74 flat
`test('…', () => {…})` calls** with inline literals and `Math.random()`-generated ids — there is no
structured, deterministic source to extract.
**New design:** introduce a standalone **`lib/select.fixtures.ts`** that exports
`export const CASES: SelectorFixture[]` — deterministic (fixed ids, no `Math.random`), each case
`{ name, selector, input, expected, seed? }`. It becomes the **single source of truth**, consumed by:
1. `lib/select.test.ts` — iterates `CASES` and asserts each (the web-side oracle), and
2. `scripts/export-fixtures.ts` (Phase 1.0 artifact) — imports `CASES` and serializes each to the
   JSON the Swift parity target reads.
This decouples fixtures from bun-test mechanics and guarantees the Swift side checks the exact same
expected values. (Refactoring the existing 74 inline tests onto `CASES` is part of the Phase 1.5 work.)

## H. Insights cards (Phase 1.5 §5.2) — intentional native divergence (NOT drift)
The web surfaces Holdings + Unrealized-FX (and `recentExpenses`, `netWorthSeries`) on **Account Detail**,
not Insights. The native app **intentionally** also surfaces them on the Insights tab. Keep them on
Insights, but **relabel** the section as a deliberate native enhancement (note the web's home for these
selectors is Account Detail) so it isn't mistaken for a mis-citation in future passes.

## I. Additional verified facts (phases 3–8 pass)
- **autoBackup cadence**: web default `frequencyMs` = **3,600,000 ms (1 hour)** (`lib/db/state.ts:211`); it's a **throttle** (gates by age-since-newest-backup), NOT a 30s debounce (`server.ts:642`).
- **Backup retention**: web default = **14** packs (`lib/db/state.ts:216`, `backup-config.ts:16`), not 7.
- **No orphan sweep**: `autoBackup` does NOT scan disk + diff vs `entry_attachments.rel_path`. The only attachment-file cleanup is per-mutation best-effort `unlinkAttachmentFiles` (`_shared/attachment-cleanup.ts`) — no disk scan, no 1-hour safety window.
- **Pack functions**: `buildPack(input)→{bytes,manifest}` (`pack.ts:99`), `parsePack(zipBytes)→{manifest,zip}` (`pack.ts:179`), `extractPack`, `detectFileKind` (`pack.ts:310`). Server orchestrator `exportPackBytes()` (`server.ts:714`). NOT `Pack.export`/`Pack.parse`.
- **Manifest field names** (nested, snake_case): `db.sha256`, `db.row_counts`, `db.byte_size`, `db.filename`, `attachments.count`, `attachments.total_bytes`, `attachments.items[]`, `exported_at`, `pack_format_version`, `app_name`. NOT flat `db_sha256`/`attachment_count`, NOT camelCase `rowCounts`/`exportedAt`.
- **No pre-DE migration path**: the DE cutover data-move is absent from MIGRATIONS (dead code in git history only); a "import a pre-DE pack and migrate" test has no web codepath — restate as a generic schema-version-replay test.
- **addTransaction arg** is **`merchant`** (`transactions/types.ts:32`), NOT `description`.
- **createBudget args**: **`amount`** + **`frequency?`** (`_args.ts:89`), NOT `limit`/`period`.
- **setCleared** `{ id, cleared: boolean }` (`_args.ts:44`); **postScheduled** `{ templateId }` (`_args.ts:176`) — both confirmed.
- **WeeklyDigest fields** (`lib/select.ts:567`): `spent, income, net, prevSpent, vsPrevPct, avgSpent, avgWeeks, vsAvgPct, topCategories: {categoryId, amount}[], biggestExpense, txCount`. NOT `totalSpent`/`topCategory`/`topCategoryAmount` (top categories is an ARRAY).
- **Budget warning default**: **`warningPct` = 80** (`budgets/mutations.ts:54`), NOT 90%.
- **anomalyScore returns an object** `AnomalyScore {zScore, mean, count, isAnomaly}` or `null` (`select.ts:779`), NOT a bare number — use the `isAnomaly` field, don't `abs(score) > 2.5`.
- **budgetProgress signature**: `budgetProgress(budget, txns, today, categories?)` (`select.ts:1336`) — 4th arg is `categories`; there is NO `accounts` param.
- **Scheduled templates have NO stored `dueDate`** — fields are `frequency, dayOfMonth, weekDay, startDate, endDate`; due dates are derived via `cycleWindow`/`generateDueScheduled` (`scheduled/types.ts:22`).
- **setEntryAttachment (75th, to be added)** arg names should echo DB columns (`relPath`/`byteSize` ↔ `rel_path`/`byte_size`), not `fileSize`.

## J. Phase 1.0 reconciliation — canonical values (all of PLAN/DESIGN/WIRE_FORMAT must agree)
Resolves the PLAN↔DESIGN↔WIRE_FORMAT drift the re-verification round found. These are the single source of truth:
- **Package/module layout:** ONE `FinchCore` SwiftPM module with flat folders (`Storage/`, `Project/`, `Selectors/`). The **7 selectors ARE Phase 1.0** (Task 6). NO 6-module layered split (DB/Schema/Money/Pack/Audit/Project), NO `FinchCoreArchitectureTests` in Phase 1.0. (DESIGN §3 saying "Selectors is Phase 1.5" is WRONG — fix it.)
- **`AuditProblem` type:** a **struct** `{ code: String; entryId: String?; detail: String }` (entryId nil for `trial-balance`/`balance-drift`). NOT an enum-with-associated-values. (Fix DESIGN §4/§6.)
- **Pack API (Swift):** `Pack.build(_ input) -> (bytes, manifest)`, `Pack.parse(_ bytes) -> ParsedPack`, `Pack.extract(_ parsed: ParsedPack, to destDir: URL) -> ExtractedPack`. NOT `Pack.import(url:)`/`Pack.export(to:)`/`Pack.extract(url:)`. (Fix DESIGN §4.)
- **Fixtures path (one spelling):** `ios/FinchCore/Tests/ParityTests/Fixtures/...` (the `.copy("Fixtures")` resource is on the `ParityTests` target). NOT `ios/FinchCore/Tests/Fixtures/`. (Fix DESIGN §1/§8.4/§9 + WIRE_FORMAT §5.1.)
- **`SelectorFixture` shape:** `{ name: string; selector: string; input: Record<string, unknown>; expected: unknown; seed?: string }`. `selector` ∈ the 7 Phase-1.0 selectors ONLY (accountBalance, selectTransactions, categorySpend, budgetProgress, cycleWindow, merchantStats, anomalyScore) — NOT balanceSeries/netWorthSeries (fix WIRE_FORMAT §5.3). Fixtures are GENERATED by `scripts/export-fixtures.ts` from `lib/select.fixtures.ts` `CASES` — NOT scraped from `select.test.ts` (fix WIRE_FORMAT §5.4).
- **`export-fixtures.ts` generator MUST normalize `Map`→object** before `JSON.stringify` (e.g. a replacer converting any `Map` to a plain object). `merchantStats` returns `Map<string, MerchantStats>` and `anomalyScore` consumes one — `JSON.stringify(map)` is `{}` without normalization, silently breaking those two fixtures.
- **CI:** ONE job, runner `macos-15`, Xcode `16.3`, steps = Bun install + `export-fixtures.ts` + `swift test` (FinchCore + ParityTests) + `xcodegen generate` + `xcodebuild` (FinchApp build/test). NOT a scheme-based `xcodebuild -scheme FinchCore` job, NOT `macos-latest`+`setup-xcode`. (Fix DESIGN §9.)
- **`rowCounts` keys = the 15-table `CANONICAL_TABLES`** (`lib/db/queries/metadata.ts:47`): `ledgers, account_groups, accounts, categories, counterparties, entries, postings, entry_tags, entry_attachments, budgets, tags, scheduled_templates, scheduled_splits, exchange_rates, app_state`. NOT the 7-table subset. (Fix PLAN Task 9 + DESIGN §4 step 2.)
- **`postings` columns (no `side`!):** `id, entry_id, account_id, category_id, amount, currency, amount_base, exchange_rate, orig_amount, orig_currency, memo, cleared_at, sort_order`. The leg type is implied by which of `account_id`/`category_id` is set — there is **NO `side` column**. (Fix PLAN Task 3 seed + Task 2 R1 prose.)
- **`BudgetProgress.pct` is an INTEGER percent 0–100** (`Math.round((used/base)*100)`, select.ts:1373), NOT a 0–1 fraction. SwiftUI `ProgressView(value:)` needs `pct/100`; thresholds compare against 70/90. (Fix PLAN Task 8.)
- **`today` for budget windows = the max confirmed-transaction date** (the web derives it from the data, not the wall clock). `FinchStore.today` must be defined this way so budget cycle windows match the oracle. (Fix PLAN Task 9.)
- **Budget green/yellow/red banding + "N days left" are NATIVE choices, NOT web parity** — the web bar is 2-state (`over ? destructive : primary`) and shows remaining-amount text, no day countdown. Relabel them as intentional native enhancements (fix PLAN Task 8 + DESIGN §5).
- **`buildPack` must actually stamp + checksum (code, not comments):** add `exportedFrom { device: "ios" }` and a `checksum` field to the build input/`PackMetadata`; `Pack.build` runs `stampExport` + `computeChecksum` + `wal_checkpoint(TRUNCATE)` on the VACUUM'd clone BEFORE reading bytes (mirror `exportPackBytes`, server.ts:732-738). (Fix PLAN Task 4/11.)
- **`forceImportCurrentPack` must retain the rejected pack's staged DB** so it can actually import an audit-failing pack (loadPack throws pre-swap; stash the staging dir/ParsedPack so force-import can swap it in). (Fix PLAN Task 9.)

## Stamp to add near the top of each fixed file (under the H1 / first blockquote)
> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._
