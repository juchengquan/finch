# finch for iOS & macOS — Phase 1.0 Implementation Design

> **Status**: design spec — not yet an implementation plan. Once approved, this
> becomes the input to `writing-plans` to produce a step-by-step implementation
> plan for Phase 1.0. Phase 1.5 and Phase 2 get their own specs.
>
> _Audience: the engineers who will build the iOS app. Assumes familiarity with
> the web app in `frontend/`, the direction brief in `plans/IOS_MACOS_PLAN.md`
> (last updated 2026-06-12 via PR #139), and the double-entry design in
> `plans/done/DOUBLE_ENTRY_PLAN.md`._

## §1. Goal & non-goals

**Goal** — Ship a working, verifiable iOS app (iPhone 15 simulator, iOS 26+)
that opens a `.finch` pack via the system file picker, displays read-only
**Accounts / Activity / Budgets / Settings**, and exports a fresh `.finch` via
the system share sheet. The four tabs cover the parity surface that exercises
the Swift port of the write-chokepoint-less read path: schema load, projection,
audit, pack build/validate/swap, GRDB round-trip, Money Decimal, iCloud
container, file picker, share sheet, SwiftUI, Swift Charts. The Swift port and
the TypeScript web app must agree to the cent on the audit and the
projection — that's the parity gate.

**Phase 1.5 (separate spec)** adds the Insights tab + the remaining 25
selectors (out of 32 in `lib/select.ts`; the 7 listed in §1 land in
Phase 1.0) + the JSON-golden parity test infrastructure.

**Phase 2 (separate spec)** adds the 74-action write chokepoint (`postEntry` /
`rebuildEntry` / `deleteEntry` ported from `frontend/lib/db/core/entries.ts`).

**Non-goals (firm)**:

- Write paths — no `postEntry` / `rebuildEntry` / `deleteEntry` in FinchCore
  yet. The 74-action chokepoint is Phase 2. The Settings tab's "Import .finch"
  is the only mutation in Phase 1.0, and it doesn't go through the chokepoint
  — it goes through `Pack.import(url:)` (read-only validate/audit/swap).
- iPad/macOS adaptive layout (Phase 3)
- Auto-pack debounce + iCloud folder-watcher + auto-import (Phase 5)
- App Intents / Siri / Share Extension receipts / Spotlight / notifications /
  biometric lock (Phase 6)
- Widgets / Watch / Live Activities (Phase 7)
- Row-level sync (Phase 8; future roadmap item, committed to building per Q22)
- An Inbox tab (the web has no Inbox page; the system file picker is the only
  import UX in Phase 1.0)
- Per-ledger display-currency override (the user can switch active ledger, but
  the display currency for the new ledger is the ledger's base currency — no
  per-ledger override UI in Phase 1.0)
- In-app theme override (follows the system light/dark setting; no in-app
  toggle)

**Repo layout**: `ios/` at the repo root with the Xcode project + FinchCore
SwiftPM package + FinchApp target + tests. Shared `docs/plans/` for
cross-cutting design docs. The web app at `frontend/` is unchanged; the only
new web-side file is `frontend/scripts/export-fixtures.ts` (the fixture export
script that writes to `ios/FinchCore/Tests/Fixtures/`).

**Estimated scope**: ~1,200-1,500 lines TS to port + ~850 lines SwiftUI to
write + ~400 lines CI/test infrastructure + ~200 lines fixture export script.
4-6 weeks of full-time work for a small team.

**Phase 1.0 reads from 7 selectors** (the same shape as the web's
`lib/select.ts`; each takes the in-memory `Tx[]` + `AccountRow[]`
+ `Budget[]` as input). The 7 are:

- `accountBalance(accounts, accountId)` — single account balance
  (Accounts tab, net worth footer)
- `selectTransactions(txns, opts)` — filtered transaction list
  (Activity tab)
- `categorySpend(txns, ledgerId, month?)` — per-category spend
  (Budgets tab, progress bars)
- `budgetProgress(budget, ...)` — one budget's spent / limit /
  period (Budgets tab, each row)
- `cycleWindow(freq, startDate, ...)` — budget cycle window math
  (Budgets tab, `budgetProgress` dependency)
- `merchantStats(txns, ledgerId)` — per-merchant aggregate stats
  (Activity tab, anomaly badge; Account Detail)
- `anomalyScore(tx, stats)` — per-transaction anomaly z-score
  (Activity tab, Account Detail)

The remaining 25 selectors from `lib/select.ts` (the
Insights-tab + supporting selectors) are ported in Phase 1.5.
See `IOS_MACOS_PHASE_1_5_DESIGN §2` for the full Phase 1.5
list.

## §2. Import UX

One import path: the system file picker launched from the **Settings** tab.
The iCloud `Documents/finch/` folder is created (so the iOS Files app shows
the user's `.finch` files under "iCloud Drive › Finch › finch/") but the app
does **not** list its contents. The web app has no Inbox page; we mirror that
on iOS.

**Settings tab — "Import .finch" button**:

- Renders a SwiftUI `.fileImporter(isPresented:, allowedContentTypes: [.zip, .finch])`
- The `.finch` UTI is registered as a child of `UTType.zip` per the plan's
  §14.1 (".finch UTI + extension registration, child of UTType.zip"). The UTI
  registration lives in `ios/FinchApp/Info.plist` (`UTExportedTypeDeclarations`).
- The picker handles Mail attachments, AirDrop, "Save to Files" from any app,
  and the Files app itself — all routes converge on a single `URL`.
- On pick, the URL is handed to `Pack.import(url:)` (see §4).
- A loading overlay shows the current pipeline step ("Validating…" →
  "Auditing…" → "Swapping…").
- On success, a toast shows the imported filename + the live DB's new
  `last_imported_at` timestamp; the Accounts tab is selected.
- On failure, an alert shows the typed `PackError` with a "View details"
  disclosure listing any audit problems. A "Try again" / "Cancel" button pair.

**Settings tab — "Export .finch" button** (see §4 Export for the pipeline):

- Renders a `ShareLink` with a temporary `.finch` file in the app's `tmp/`
  directory. The user picks "Save to Files" / "Mail" / "AirDrop" / etc.
- The exported filename is `<ledger-slug>-<yyyy-mm-dd>.finch`.

**iCloud `Documents/finch/` folder**:

- The app's iCloud container is requested at first launch with
  `FileManager.default.ubiquityIdentityToken`; if the user is signed into
  iCloud, the app calls `FileManager.url(forUbiquityContainerIdentifier:)`
  and creates `Documents/finch/` if it doesn't exist.
  - **iOS**: `forUbiquityContainerIdentifier:` returns `nil` if
    the user is signed out (i.e., the call is `nil`-returning
    when no iCloud account).
  - **macOS**: `forUbiquityContainerIdentifier:` returns the
    **local** container path even when iCloud is unavailable
    (it doesn't return `nil`); the macOS path must additionally
    check `ubiquityIdentityToken` to know whether to write to
    the iCloud-replicated path or a local-only path.
- The user can drop `.finch` files into this folder from Mail, Safari,
  AirDrop, or "Save to Files." The Files app shows the folder under
  "iCloud Drive › Finch › finch/" automatically — no custom file-provider
  extension needed (that's a Phase 5+ concern).
- The app does **not** enumerate this folder. The user imports files
  explicitly via the system file picker.
- iCloud is used purely as a "dumb file mover" per the plan's §14.1
  resolved decision #1.

**Why no Inbox tab**: the web app has no Inbox page; import is a single button
in Settings. Diverging from the web's UX needs a reason. Phase 1.0 doesn't
have that reason — the Inbox concept becomes useful in Phase 5 when the
auto-pack debounce + folder-watcher lands. Until then, the system file picker
+ iCloud `Documents/finch/` folder (visible in Files) is enough.

## §3. FinchCore layout

`FinchCore` is a SwiftPM package at `ios/FinchCore/`. Seven modules with
strict layer rules — no cycles, no upward imports. The architecture mirrors
the web's `core/` + `domain/` split (`frontend/lib/db/core/` for engine code,
`frontend/lib/db/domain/` for per-domain code) but is consolidated into one
package for Phase 1.0 simplicity.

```
                   ┌──────────┐
                   │   ICloud │  (Phase 1.0)
                   └────┬─────┘
                        │ reads .finch from Documents/finch/
                        ▼
┌──────────┐      ┌──────────┐      ┌────────────┐
│  Money   │◀─────│   Pack   │─────▶│   Schema   │
│ (Decimal)│      │(build +  │      │  (DDL +    │
│          │      │ validate │      │  triggers) │
│          │      │  + swap) │      └─────┬──────┘
└──────────┘      └────┬─────┘            │
     ▲                 │ reads/writes     │ opens
     │                 ▼                  ▼
     │            ┌──────────┐      ┌──────────┐
     │            │  Audit   │      │    DB    │
     │            │ (read-   │      │ (GRDB    │
     │            │  only)   │      │  driver  │
     │            └────┬─────┘      │  + WAL)  │
     │                 │            └────┬─────┘
     │                 │                 │
     │                 ▼                 ▼
     │            ┌─────────────────────────┐
     └────────────│       Project           │
                  │  (Tx projection         │
                  │   from entries/postings) │
                  └─────────────────────────┘
```

**Layer rules** (the *only* allowed import directions; enforced by
`FinchCoreArchitectureTests`):

1. `DB` imports nothing from FinchCore (the lowest layer — wraps GRDB
   `DatabaseQueue` + WAL setup + a typed `Row` codec)
2. `Schema` imports `DB`, `Money` (issues DDL through the DB; column types
   reference `Money`)
3. `Money` imports nothing from FinchCore (pure Foundation `Decimal` + currency
   code + locale-aware formatting)
4. `Pack` imports `DB`, `Schema`, `Money`, `Audit` (it builds, validates,
   audits, and swaps; `Audit` is the read-only audit half)
5. `Audit` imports `DB`, `Schema`, `Money`, `Project` (walks the schema, reads
   the projection, returns typed problems)
6. `Project` imports `DB`, `Schema`, `Money` (reads entries/postings and
   produces `Tx[]`)
7. `ICloud` imports `Pack` (lists files and hands URLs to `Pack`)

**`Selectors` module** (Phase 1.5, not in Phase 1.0): imports `DB`, `Money`,
`Project`. Lives at `ios/FinchCore/Sources/FinchCore/Selectors/`.

**`Store` module** (Phase 2, not in Phase 1.0): the on-device write chokepoint
port. Lives at `ios/FinchCore/Sources/FinchCore/Store/`.

**Why these rules**:

- `Money` being independent means we can lift it to a separate SwiftPM target
  (`FinchMoney`) later if any other app wants it, and unit tests run without
  spinning up a database.
- `DB` being a thin GRDB wrapper means Phase 2 can swap to a different driver
  (e.g., a `bun:sqlite` test driver) by adding one more `DB` impl, with no
  changes to `Schema` / `Project` / `Audit` / `Pack`.
- `Pack` being at the top means the iCloud folder UX (`ICloud`) and the system
  file picker UX (SwiftUI `.fileImporter`) both go through one well-tested
  chokepoint.
- `Audit` not depending on `Pack` (the arrow goes the other way) means we can
  run audit on an arbitrary DB without the pack engine — useful for the
  on-device audit gate in the import pipeline and for the parity suite.

**Enforcement**: `FinchCoreArchitectureTests` walks the symbol graph at test
time and asserts the layer rules (e.g., "Pack may not import Project
directly"; "Money may not import any FinchCore module"). The web side uses
`eslint no-restricted-imports` for the same purpose (see
`frontend/AGENTS.md`'s "Layer rules" section); we mirror that with a
Swift-native test.

## §4. The `.finch` pipeline + audit gate

`Pack.import(url: URL, into: FinchStore) -> Result<ImportedPack, PackError>` is
the single entry point for both import paths (system file picker; Phase 5
folder-watcher will also call it). It is pure (no UI, no SwiftUI), takes a
URL, returns a typed result. The view-model layer wraps it in a `Task` and
updates `@Observable` state.

`Pack.export(from: FinchStore, to: URL) -> Result<ExportedPack, PackError>` is
the reverse direction.

### Import — 6 steps

**Step 1 — Extract to staging** (`Pack.extract(url: URL) -> URL`):

```
staging = tmp/import-staging/<uuid>/
unzip url -> staging/   (system unzip; .finch is a zip)
```

The staging directory holds: `manifest.json`, `finch.sqlite3`,
`attachments/<entry_id>/<attachment_id>.<ext>`. If anything in steps 2-6 fails,
the staging directory is deleted and the live DB is untouched.

**Step 2 — Manifest validation** (`PackValidator.validate(_ manifest: Manifest) -> Result<Void, ManifestError>`):

- `schema_version == "2026-06-14T00:00:00Z"` (the shared lineage from plan
  §4.6; the constant lives at `Schema/SCHEMA_VERSION`)
- `db_sha256` matches the actual file's sha256 (computed with
  `CryptoKit.SHA256`)
- `row_counts` keys are the post-DE canonical tables: `entries`, `postings`,
  `entry_tags`, `entry_attachments`, `accounts`, `categories`, `ledgers` —
  also `accounts_archived` if present
- `attachment_count` matches the on-disk file count; per-file sha256 in
  `attachments[]` matches
- If the pack is pre-DE (`schema_version` < `2026-06-14T00:00:00Z`), the
  migration runs in step 3 before audit; this matches the web's "open the
  file, migrations run" model from §4.6
- A missing or malformed `manifest.json` returns `manifestMissing` /
  `manifestMalformed`

**Step 3 — Open with GRDB + run migrations** (`FinchStore.open(staging: URL) -> Result<FinchStore, OpenError>`):

- `GRDB.DatabaseQueue(path: staging/finch.sqlite3)` opened in WAL mode
  (`PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL`) — matches the web's
  `better-sqlite3` setup from `lib/db/core/driver.ts`
- Migrations run on open: each entry in the shared `MIGRATIONS` array from
  `lib/db/core/schema.ts` is ported to Swift; idempotent on a DB already at
  the target version
- For pre-DE packs: the DE cutover migration runs (the per-entry sealed-write
  + id-fidelity logic from `lib/db/core/entries.ts` and
  `lib/db/core/sealed-entry.ts`). This is the largest single piece of ported
  logic, but it's required for cross-app interop to work.
- The migration runner is `Schema.Migrator` (a thin wrapper around GRDB's
  `DatabaseMigrator`); each migration is a Swift `Migration` record that
  mirrors the corresponding entry in the web's `MIGRATIONS` array.

**Step 4 — Audit** (`Audit.run(on: GRDB.DatabaseQueue) -> [AuditProblem]`):

- Walks `entries` + `postings` + `accounts` + `categories` + `ledgers`
- Returns the 8 typed problem classes from
  `lib/db/core/entries.ts::auditLedger`:
  1. **Unbalanced entry** — postings don't sum to 0 in the entry's base
     currency
  2. **Unsealed entry** — no `kind='opening'` or `kind='adjustment'` in the
     chain (an opening-balance entry is required to "seal" the books)
  3. **Account-leg currency mismatch** — `account.currency ≠ leg.currency`
     unless the leg is in the ledger base
  4. **`kind` shape mismatch** — e.g., `kind='expense'` with no
     `category_id` on a leg
  5. **Cross-ledger postings** — postings from different ledgers in one
     entry (should be impossible post-migration, but checked)
  6. **Non-zero global trial balance per ledger** — sum across all postings
     per ledger; the global TB must be 0
  7. **Cached `current_balance` drift** — compare `accounts.current_balance`
     to `recomputeAccount` sum (the read-only recompute; no writes)
  8. **`amount ≠ amount_base` on a base-currency leg** — should always be
     equal for legs whose currency is the ledger base
- Returns an empty array for a clean DB
- Swift types: `enum AuditProblem: Equatable, Sendable` with associated
  values for context (`entryId`, `legId`, `expected`, `actual`, etc.)
- Parity test: a fixture DB seeded with one row per problem class (8
  fixtures) → Swift's `Audit.run` returns the same typed problem set as the
  web's `lib/db/core/entries.ts::auditLedger` for each fixture (see §8)

**Step 5 — Atomic swap** (`Pack.swap(staging: URL, into: live: URL) -> Result<Void, SwapError>`):

- Close the live DB connection (FinchStore calls `db.close()`)
- Rename `Application Support/finch.sqlite3` →
  `Application Support/finch.sqlite3.bak.<unix-timestamp>` (the on-device
  backup, kept until next successful import; per plan §2.5.1 the previous
  backup is overwritten on each successful import)
- Rename `staging/finch.sqlite3` → `Application Support/finch.sqlite3`
- If attachments are present: `staging/attachments/` →
  `Application Support/attachments/` (overwriting where ids collide — ids
  are stable across imports per the DE migration's id-reuse policy from
  `lib/db/core/sealed-entry.ts`; the path structure `attachments/<entry_id>/<attachment_id>.<ext>`
  is byte-identical)
- Open the live DB
- Re-run `auditLedger` on the swapped DB (defense in depth — catches a race
  where another process modified the staging file between validation and
  swap; per plan §8 "import MUST validate manifest + sha256, then run
  auditLedger for semantic integrity, then atomically swap")
- If any step fails: roll back to `.bak.<timestamp>`, return typed
  `SwapError`

**Step 6 — Project** (`Project.run(on: GRDB.DatabaseQueue) -> [Tx]`):

- The full `Tx` projection from `lib/db/state.ts::projectState` is ported to
  Swift
- Single-entry skin (the `Tx` type the UI consumes) is preserved — opening /
  equity legs filtered out, splits flattened, category resolved via join
- `FinchStore` keeps the projected `Tx[]` in memory after open; Phase 1.5
  selectors will read from this in-memory array, matching the web's
  `lib/select.ts` shape (the web's selectors take `Tx[]` as input, not raw
  DB rows)

### Export

`Pack.export(from: live: URL, to: URL) -> Result<ExportedPack, PackError>`:

- Open the live DB (read-only `DatabaseQueue` opened with `.read-only`)
- Run `VACUUM INTO 'tmp/export/finch.sqlite3'` (matches the web's pack build
  path in `lib/db/core/pack.ts::buildPack`)
- Write a fresh `manifest.json` with the current `schema_version` +
  `db_sha256` + per-file attachment checksums + `row_counts`
- Copy `attachments/` → `tmp/export/attachments/`
- `zip` the staging directory → `<ledger-slug>-<yyyy-mm-dd>.finch`
- Hand the URL to SwiftUI's `ShareLink` (the user picks the share
  destination)

### Error model

One `PackError` enum with typed cases:

- `manifestInvalid(reason: ManifestError)` — step 2
- `migrationFailed(step: String, underlying: Error)` — step 3
- `auditFailed([AuditProblem])` — step 4 (this is the gate; import is refused)
- `swapFailed(SwapError)` — step 5
- `exportFailed(underlying: Error)` — export

The UI shows these as alerts with a "View details" disclosure that lists the
audit problems (`entryId` + class + context). The user can choose "Cancel" or
"Force import" — which skips the audit gate but still runs the rest of the
pipeline. The "Force import" button lives in **Settings › Advanced**
(always visible; not behind a debug flag). It's a recovery hatch for users
who know their data is intentionally non-compliant with the audit gate (e.g.,
a manually-edited `.finch`).

## §5. The iOS screens (Phase 1.0)

The iOS app is a single iPhone target (no iPad layout until Phase 3, no Mac
until Phase 3). It's a SwiftUI `TabView` with 4 tabs. Chrome is SwiftUI on
iOS 26+ with `@Observable` view models. No UIKit unless we hit a gap.

### Tab 1 — Accounts

Read-only list of accounts in the active ledger, grouped by `account_group_id`
(or "Ungrouped" if no group). Each row shows account name, type icon,
current balance (in the active ledger's display currency, formatted via
`Money.formatted(in: displayCurrency)`).

```
┌─────────────────────────────────────┐
│  Accounts                            │
├─────────────────────────────────────┤
│  💳 Spending                         │
│   ├─ Chase Checking       $2,340.12  │
│   ├─ Amex                 -$145.67  │
│   └─ Cash                  $40.00   │
│                                      │
│  💰 Savings                          │
│   ├─ Ally HYSA           $15,200.00  │
│   └─ Treasury Bills      $10,000.00  │
│                                      │
│  📈 Investments                      │
│   └─ Vanguard Brokerage  $42,318.55  │
│                                      │
│  ────────────                        │
│  Net worth:           $69,752.00    │
└─────────────────────────────────────┘
```

Tapping a row pushes the Activity tab's `NavigationStack` with that account's
filter pre-applied. The bottom row shows total net worth (sum of all account
balances, in display currency).

Phase 1.0 doesn't include edit/add for accounts. Long-press shows a context
menu with "View activity" (pushes Activity) and "Copy balance" (copies the
formatted string to the clipboard).

### Tab 2 — Activity

Per-account transaction list (or all accounts, depending on navigation).
Sorted by date desc, paginated to 50 rows per page (infinite scroll). Each
row shows date, merchant/description, category badge, amount (in
transaction's native currency, or display currency if same as account).

```
┌─────────────────────────────────────┐
│  ← Chase Checking                    │
├─────────────────────────────────────┤
│  Jun 12  Coffee Bar        -$6.50   │
│           ☕ Food & Dining            │
│  Jun 12  Payroll          $2,100.00  │
│           💼 Income                  │
│  Jun 11  Whole Foods      -$87.23   │
│           🛒 Groceries               │
│  ...                                 │
│                                      │
│  [Load more]                         │
└─────────────────────────────────────┘
```

Tapping a row pushes the **Transaction Detail** screen, which shows: date,
amount, account(s), category, tags, notes, splits (if any), and audit status
(clean / problem-class). All read-only. Attachments are deferred to Phase 6
(Share Extension receipts).

Search bar at the top triggers FTS5 search across `entries.description`
and `entries.notes` (the `entries_fts` virtual table in
`lib/db/core/schema.ts` indexes only these two columns — not
`counterparties.name` or `merchants.name`). The Swift port calls
`Transactions.listTransactions(exec, opts: { query: String, ... }) -> [Tx]`
(the same `listTransactions` function the web uses, with the
`query` field triggering the FTS5 `MATCH` predicate in
`lib/db/queries/transactions.ts:240`).

### Tab 3 — Budgets

Read-only list of budgets in the active ledger, grouped by `budget_group_id`
(or "Ungrouped" if no group). Each row shows budget name, period header
(current month), progress bar, and `spent / limit` figure in display
currency.

```
┌─────────────────────────────────────┐
│  Budgets            June 2026       │
├─────────────────────────────────────┤
│  🛒 Groceries                        │
│     ████████████░░░░  $340 / $500   │
│     5 days left in period            │
│                                      │
│  ☕ Food & Dining                     │
│     ████████████████  $280 / $300   │
│     93% — over budget                │
│                                      │
│  🚗 Transport                        │
│     ████░░░░░░░░░░░░  $80 / $400   │
│     20%                              │
│                                      │
│  ────────────                        │
│  Total budget:  $1,200 / $2,000     │
│  Total spent:   $700 (35%)          │
└─────────────────────────────────────┘
```

Progress bar color follows the web's thresholds: green (under 70%), yellow
(70-90%), red (over 90% or over budget). Tap a row to filter the Activity
tab to that category.

Phase 1.0 doesn't include edit/add for budgets (those land in Phase 2 with
the write chokepoint).

### Tab 4 — Settings

Read-only in Phase 1.0 (no user preferences persisted on-device yet — those
land in Phase 1.5 or 2). Sections (top to bottom):

- **Import .finch** — button (see §2)
- **Export .finch** — button (see §2)
- **Active ledger** — currently selected ledger; tap to switch from a list
  of ledgers in the imported DB
- **Database info** — filename, size, schema version, last imported at, row
  counts (entries / postings / accounts / categories)
- **Audit status** — "Clean" or "N problems" (tap to see the typed problem
  list)
- **Advanced** — collapsed by default. Contains:
  - **Force import** — a button that bypasses the audit gate (per
    Q15; this is a recovery hatch for `.finch` files that have
    audit problems the user wants to import anyway). Always
    visible; not behind a debug flag.
- **About** — app version, FinchCore version, build hash. (A deep link to
  the project repo or the docs site is a Phase 1.5 polish; not in 1.0.)

**Active ledger switching** is the only "interactive" thing in Phase 1.0.
Switching ledger re-runs the projection filtered to the new ledger's
accounts/entries/categories. Selectors in Phase 1.5 will read from the
active-ledger-filtered `Tx[]`.

**Display currency** is the active ledger's base currency in Phase 1.0. No
per-ledger display-currency override UI; the Settings tab will show
"Display currency: USD (default = base)" with a "Change" button stubbed for
Phase 1.5.

### Loading, empty, and error states

- **Loading** (during import): `ProgressView` with a status string
  ("Validating…" → "Auditing…" → "Swapping…"). The import is cancellable
  via a "Cancel" button that abandons the staging folder (live DB is
  untouched).
- **Empty Accounts / Activity / Budgets** (DB has no data): centered icon +
  one-line message + hint "Import a .finch from the Settings tab."
- **Errors** (during import): typed `PackError` alert with a "View details"
  disclosure and a "Try again" / "Cancel" button pair.

### Theming

- Light/dark follows the system setting
- Tokens ported from `frontend/app/globals.css` (the "warm editorial" light +
  "noir" dark palettes) to SwiftUI `Color` extensions
- Phase 1.0 doesn't have an in-app theme override

### Accessibility

- Dynamic Type across all text (per the plan's §11)
- VoiceOver labels on every control (the web app's icon-only buttons all
  have labels; we carry that rigor over)
- Decorative charts are accessibility-hidden with a text summary (e.g.,
  "Spending trend: up 8% vs last month")
- Contrast ratios match WCAG AA (the web's `muted-foreground` was tuned to
  ~6:1)

## §6. Dependencies

**SwiftPM-only** (no CocoaPods, no Carthage — see the README's note that
CocoaPods is broken for GRDB 7+ anyway, and we don't need either tool).

- **GRDB.swift 7.11.0** (current stable, released 2026-06-01) — the SQLite
  library. Selected over GRDB 6.x because: (a) FTS5 + trigger fixes in
  7.7-7.9 are directly relevant to our schema; (b) 6.x is in maintenance
  mode; (c) the migration guide exists *for* 6→7, and we'd rather start on
  the current stable than plan a forced migration later. iOS 13+ deployment
  target; iOS 26+ is our actual target.
- **Foundation `Decimal`** for all amounts, end-to-end. Narrowed to `DOUBLE`
  at the DB boundary via a `StorageDecimal` codec (per the plan's §4.5:
  "compute in Decimal, narrow to REAL at the boundary; cent-level parity
  assertions"). No integer minor-units conversion in Phase 1.0.
- **Swift Charts** (system framework, iOS 16+) for the Budgets progress bars
  and any future chart — no third-party chart library.
- **SwiftUI `.fileImporter`** (system framework) for the import UX.
- **SwiftUI `ShareLink`** (system framework, iOS 16+) for the export UX.
- **`CryptoKit.SHA256`** (system framework) for the manifest checksums.
- **`FileManager.url(forUbiquityContainerIdentifier:)`** (system framework)
  for the iCloud container.
- **`UTType.zip` / `.finch`** (system framework) for the file picker UTI
  registration. `.finch` is registered as a child of `.zip` per the plan's
  §14.1.
- **No other third-party deps** for Phase 1.0. The fixture export script on
  the web side (`frontend/scripts/export-fixtures.ts`) uses only `bun:test`
  + the existing `lib/db/core/seed.ts` to produce fixtures — no new web-side
  deps.

## §7. Data model

Swift types ported from the web's `lib/store/transactions/state.ts` and
`lib/db/domain/<x>/types.ts`. All amounts are `Decimal`. All dates are
`String` (ISO 8601) to match the schema's TEXT columns; the Swift side does
not re-parse to `Date` until display time (this mirrors the web, which keeps
`date` as a string for serialization parity).

```swift
// Project/Tx.swift — the single-entry skin the UI consumes
struct Tx: Equatable, Sendable {
    let id: String
    let merchant: String
    let category: String?         // category id (join key); matches
                                  // the web's `Tx.category` field
                                  // (which is the id, not a name)
                                  // — see `frontend/lib/store/
                                  // transactions/state.ts:21`.
                                  // Display names are looked up
                                  // via a separate `Category`
                                  // table; `Tx` itself holds the
                                  // id only.
    let amount: Decimal            // signed, in ledger base
    let currency: String?          // omitted/equal to ledger base for same-currency
    let nativeAmount: Decimal?     // signed, in `currency`
    let account: String            // account name
    let date: String               // "YYYY-MM-DD"
    let time: String?
    let note: String?
    let pending: Bool?
    let kind: TxKind?              // income/expense/transfer/adjustment/refund
    let ledgerId: String?
    let transferGroupId: String?
    let sourceTemplateId: String?
    let refundedTransactionId: String?
    let counterpartyId: String?
    let tags: [String]?
    let splits: [TxSplit]?
    let clearedAt: String?
    let reviewedAt: String?
    let appliedRuleIds: [String]?
}

enum TxKind: String, Equatable, Sendable, Codable {
    case income, expense, transfer, adjustment, refund
}

struct TxSplit: Equatable, Sendable {
    let id: String
    let categoryId: String?
    let amount: Decimal            // signed, in tx's native currency
    let amountBase: Decimal        // signed, in ledger's base currency
    let description: String?
}

// Project/AccountRow.swift, Category.swift, Counterparty.swift, Ledger.swift
// — ported from lib/db/domain/<x>/types.ts. All amounts Decimal.
```

The `Tx` projection from `lib/db/state.ts::projectState` is the single largest
piece of Phase 1.0 porting work. It walks entries + postings + counterparties
+ categories + tags + accounts + currencies + rates and produces a flat
`Tx[]` with opening/equity legs filtered out, splits flattened, and category
names resolved via join.

The `AuditProblem` enum (see §4 step 4) has 8 cases, one per problem class.
Each case carries the context needed to fix the underlying issue
(`entryId`, `legId`, `expected`, `actual`, `currency`, etc.).

## §8. Parity suite

The parity gate is the headline quality bar. It enforces that the Swift port
and the TypeScript web app produce identical outputs for the same inputs, to
the cent. Three layers:

### 8.1 — `Tx` projection parity

For every golden DB fixture, Swift's `Project.run(on:)` emits the same `Tx[]`
as the web's `lib/db/state.ts::projectState`. Comparison is structural
(struct-by-struct `Equatable` comparison) and runs at the Swift test level
against JSON fixtures.

### 8.2 — `auditLedger` parity

For every fixture DB (golden + property-generated), Swift's `Audit.run(on:)`
returns the same typed problem set as the web's
`lib/db/core/entries.ts::auditLedger`:

- Empty array for clean DBs
- Matching outcomes for seeded-corruption fixtures — one per problem class
  (8 fixtures):
  1. `unbalanced.finch` — an entry with postings that don't sum to 0
  2. `unsealed.finch` — an entry with no opening or adjustment
  3. `currency-mismatch.finch` — a leg whose currency ≠ account currency
  4. `kind-shape.finch` — an `expense` entry with no `category_id`
  5. `cross-ledger.finch` — postings from two different ledgers
  6. `tb-nonzero.finch` — sum across all postings ≠ 0 for a ledger
  7. `balance-drift.finch` — `accounts.current_balance` ≠ recompute sum
  8. `base-amount-mismatch.finch` — `amount ≠ amount_base` on a base leg

### 8.3 — `.db` round-trip parity

For every golden DB fixture:

- Open with GRDB → run migrations → run `projectState` → run `auditLedger`
  → expect clean
- Web-side: open the same file with `better-sqlite3` → run migrations →
  run `projectState` → run `auditLedger` → expect clean
- Compare the resulting `Tx[]` byte-for-byte (via JSON serialization)
- Special fixture: `pre-de.finch` — a pre-DE database (pre-`2026-06-14T00:00:00Z`)
  that the migration runner upgrades on open; the post-migration `Tx[]` and
  audit outcome match the web-side post-migration `Tx[]` and audit outcome
  for the same input

### 8.4 — Fixture export script

A new web-side script at `frontend/scripts/export-fixtures.ts` that:

1. Defines a curated list of `(selector, input, expected)`
   test cases (calling each selector function directly with
   the named fixture inputs; **not** by reflecting on
   `bun:test` cases — `bun:test` doesn't expose the test
   function as a value you can call outside the test
   runner, so trying to extract from `select.test.ts` at
   runtime won't work)
2. Serializes them as JSON: `{ selector: "accountBalance", input: [...],
   expected: ... }`
3. Generates the 8 audit-corruption fixtures by running the seed with a
   mutation per problem class
4. Generates the 1 pre-DE fixture by running the seed at an older
   `SCHEMA_VERSION`
5. Writes everything to `ios/FinchCore/Tests/Fixtures/` (a `selector.json`,
   a `sample.finch`, a `pre-de.finch`, and the 8 `*-corrupt.finch` files)
6. Is invoked by the macos CI job before `FinchCore` tests run, so
   fixtures stay in sync with the web

The script is Bun-only (uses `bun:test` + the existing `lib/db/core/seed.ts`).
It's checked into the repo at `frontend/scripts/export-fixtures.ts` with its
own `bun test` smoke test.

### 8.5 — Test target structure

Three SwiftPM test targets in `ios/FinchCore/`:

- `FinchCoreTests` — unit tests for each module (`Money`, `DB`, `Schema`,
  `Project`, `Audit`, `Pack`); runs on both `macOS` and `iOS Simulator`
  destinations
- `ParityTests` — the cross-implementation parity gate (the JSON goldens
  + `.db` round-trip + audit fixtures); runs on `macOS` destination only
  (the .db files are tested via the GRDB-macOS code path, which is closer
  to iOS GRDB than the Linux Bun path is)
- `FinchAppTests` — UI snapshot tests for the 4 tabs (light/dark, a few
  Dynamic Type sizes); runs on `iOS Simulator` destination

## §9. CI

macos-latest GitHub Actions runner. The Linux-side `frontend/` job is
unchanged.

### 9.1 — macos job (new)

```yaml
macos:
  name: iOS (typecheck · test · parity · UI snapshot)
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - name: Setup Bun
      uses: oven-sh/setup-bun@v2
      with: { bun-version: "1.3.11" }
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with: { xcode-version: "16.3" }   # GRDB 7 requires 16.3+
    - name: Install web deps
      working-directory: frontend
      run: bun install --frozen-lockfile
    - name: Export fixtures
      working-directory: frontend
      run: bun run scripts/export-fixtures.ts  # writes to ios/FinchCore/Tests/Fixtures/
    - name: Build FinchCore (macOS)
      working-directory: ios
      run: xcodebuild -scheme FinchCore -destination 'platform=macOS' build
    - name: Test FinchCore (macOS)
      working-directory: ios
      run: xcodebuild -scheme FinchCore -destination 'platform=macOS' test
    - name: Test ParityTests (macOS)
      working-directory: ios
      run: xcodebuild -scheme ParityTests -destination 'platform=macOS' test
    - name: Build FinchApp (iOS Simulator)
      working-directory: ios
      run: xcodebuild -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' build
    - name: Test FinchApp (iOS Simulator)
      working-directory: ios
      run: xcodebuild -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' test
```

### 9.2 — Per-increment gate (mirror of the web's discipline)

Every PR that touches `ios/` must:

- Pass the macos job (typecheck, FinchCore unit, ParityTests, FinchApp UI
  snapshot)
- Pass the existing Linux job (frontend typecheck, lint, test, build)
- Be reviewed and merged before the next increment lands

This mirrors the plan's §12 "Per-increment gate (mirror CI discipline)" —
"build + unit/parity tests + UI snapshot smoke, green before merge. Each
milestone ships a working, verifiable build."

## §10. Open questions

The plan's §14.1 lists "smaller follow-up questions opened up by these
decisions." Most are not Phase 1.0 blockers; they're noted here so they
don't get lost.

**Not blocking Phase 1.0 (decide later)**:

- **Pack cadence + sweep policy** — what's the right idle-debounce (~30 s?)
  before auto-packing, and how often do we sweep orphaned attachment files
  off disk (every pack? a periodic vacuum?). Phase 5 concern.
- **Conflict-copy UX** — when iCloud surfaces a conflict copy, what does
  the user see and what's the merge-or-discard affordance? Phase 5
  concern.
- **`.finch` UTI + extension registration** — the UTI registration itself
  is Phase 1.0 (`UTExportedTypeDeclarations` in `Info.plist`); the
  per-platform polish (Quick Look generator, document picker icon) can
  land later.
- **iCloud folder naming + visibility** — the iCloud `Documents/finch/`
  folder naming is Phase 1.0 (auto-created); the user-visible "finch/"
  subfolder name vs. the app's default `Documents/` is a polish concern
  for Phase 1.5.
- **Day-1 locales** — the web ships `en + zh-CN` (per plan §11). Native
  uses `Localizable.strings`; the day-1 list is a product call (default
  `en`; add `zh-CN` if the user base warrants it).

**Not blocking Phase 1.0 because they're Phase 2+ by design**:

- Widgets / Live Activities / Watch — Phase 7
- App Intents / Siri / Spotlight / notifications / biometric lock — Phase 6
- iPad/macOS adaptive layout — Phase 3
- Auto-pack debounce + folder-watcher — Phase 5
- Row-level sync — Phase 8 (future roadmap item; committed to building per Q22)

## §11. Out of scope (firm)

These are explicitly NOT in Phase 1.0 and will be re-spec'd in their own
specs (Phase 1.5, Phase 2, etc.):

- **Write paths** — the 74-action chokepoint (`postEntry` / `rebuildEntry` /
  `deleteEntry` and all 13 per-domain `mutations.ts` files) is Phase 2.
  Phase 1.0 has no `Store` module.
- **iPad/macOS adaptive layout** — Phase 3. Phase 1.0 is iPhone-only.
- **Power features** — reconcile, rules engine + builder, transfers CRUD,
  merchants / categories / tags admin, saved searches, bulk recategorize,
  FX/base tools. Phase 4.
- **Auto-pack debounce + iCloud folder-watcher + auto-import** — Phase 5.
  Phase 1.0's iCloud `Documents/finch/` folder is a static location; the
  app doesn't watch it.
- **Receipt attachments** — Phase 6 (Share Extension + `PhotosPicker`).
  Phase 1.0's Transaction Detail has no attachment UI.
- **Per-ledger display-currency override UI** — Phase 1.5. Phase 1.0 uses
  the active ledger's base currency as the display currency.
- **In-app theme override** — Phase 1.5. Phase 1.0 follows the system
  light/dark setting.
- **Inbox tab / folder-listing UI** — explicitly rejected for Phase 1.0
  (the web has no Inbox page; the system file picker is the only import
  UX).
- **Force-import UI** — the typed `PackError` model supports it; the
  "Force import" button is in **Settings › Advanced** (always visible
  in Phase 1.0). It's a user-facing recovery hatch for users who know
  their data is intentionally non-compliant with the audit gate
  (e.g., a manually-edited `.finch`).
- **Android** — the plan doesn't include Android. GRDB 7 added Linux/Windows
  support but the plan's §4.1 commits to "SwiftUI multiplatform" (Apple
  only).

## §12. Spec self-review

(Inline review at write time; not part of the published spec.)

- **Placeholders**: none. Every section has concrete content.
- **Internal consistency**: §4's `Pack.import` signature matches §3's
  layer rules (Pack is at the top, imports DB/Schema/Money/Audit).
  §5's UI references §4's `PackError` cases (manifestInvalid,
  auditFailed, etc.) consistently. §8's 8 audit fixtures match §4's
  8 problem classes 1:1. §6's GRDB version matches §3's `DB` module
  description (GRDB `DatabaseQueue`).
- **Scope**: focused on Phase 1.0. Phase 1.5 and Phase 2 are referenced
  as future specs but not designed here. §11 enumerates the firm
  out-of-scope items so the implementation doesn't accidentally pull
  Phase 2 work forward.
- **Ambiguity**: §4 step 4 enumerates the 8 problem classes by name with
  the same wording as the web's `lib/db/core/entries.ts::auditLedger`.
  §5's per-tab UI is described with concrete field lists (account name,
  type icon, current balance, etc.). §6's `Decimal` boundary is explicit
  ("narrowed to `DOUBLE` at the DB boundary via a `StorageDecimal`
  codec"). The 4-tab decision (§5) and the Inbox-rejection rationale
  (§2) are explicit.
