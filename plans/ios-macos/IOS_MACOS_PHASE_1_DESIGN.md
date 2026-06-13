# finch for iOS & macOS — Phase 1.0 Implementation Design

> **Status**: design spec — not yet an implementation plan. Once approved, this
> becomes the input to `writing-plans` to produce a step-by-step implementation
> plan for Phase 1.0. Phase 1.5 and Phase 2 get their own specs.
>
> _Audience: the engineers who will build the iOS app. Assumes familiarity with
> the web app in `frontend/`, the direction brief in `plans/ios-macos/IOS_MACOS_PLAN.md`
> (last updated 2026-06-12 via PR #139), and the double-entry design in
> `plans/done/DOUBLE_ENTRY_PLAN.md`._
>
> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._
>
> _Hardened per Phase 1.0 dry-run, 2026-06-13 (see `_PHASE_1_0_GAP_REPORT.md`)._

## See also

- `plans/ios-macos/IOS_MACOS_INDEX.md` — the navigation index (glossary, location index, master tab list)
- `plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md` — the wire-format annex (74-action Args, pack format, I18nError, fixture format)
- `plans/ios-macos/IOS_MACOS_PLAN.md` §2 — the domain model
- `plans/ios-macos/IOS_MACOS_PLAN.md` §4 — the 8-step import pipeline
- `plans/ios-macos/IOS_MACOS_PLAN.md` §12 — the parity suite
- `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 (adds Insights tab + 25 selectors)
- `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (74-action chokepoint + 7 write screens)

## §0. Map — 8-section template

The 8-section template (Goal / Architecture / UI / Cross-cutting /
Wire / CI / Out-of-scope / Self-review) maps to this spec's
existing sections as follows:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §3 (FinchCore layout) + §7 (Data model) |
| §3. iOS UI surfaces | §5 (The iOS screens, Phase 1.0) |
| §4. Cross-cutting concerns | §6 (Dependencies) |
| §5. Wire contracts | §2 (Import UX) + §4 (The .finch pipeline + audit gate) |
| §6. CI / test infrastructure | §8 (Parity suite) + §9 (CI) |
| §7. Out of scope (firm) | §11 |
| §8. Spec self-review + open questions | §12 + §10 |

## §1. Goal & non-goals

**Goal** — Ship a working, verifiable iOS app (iPhone 16 simulator, iOS 26+)
that opens a `.finch` pack via the system file picker, displays read-only
**Accounts / Activity / Budgets / Settings**, and exports a fresh `.finch` via
the system share sheet. The four tabs cover the parity surface that exercises
the Swift port of the write-chokepoint-less read path: schema load, projection,
audit, pack build/validate/swap, GRDB round-trip, Money Decimal,
file picker, share sheet, SwiftUI, Swift Charts. (The iCloud container is
deferred to Phase 5 — see §2/§10.) The Swift port and
the TypeScript web app must agree to the cent on the audit and the
projection — that's the parity gate.

**Phase 1.5 (separate spec)** adds the Insights tab + the remaining 25
selectors (out of 32 in `lib/select.ts`; the 7 listed in §1 land in
Phase 1.0 — Task 6) + the JSON-golden parity test infrastructure.

**Phase 2 (separate spec)** adds the 74-action write chokepoint (`postEntry` /
`rebuildEntry` / `deleteEntry` ported from `frontend/lib/db/core/entries.ts`).

**Non-goals (firm)**:

- Write paths — no `postEntry` / `rebuildEntry` / `deleteEntry` in FinchCore
  yet. The 74-action chokepoint is Phase 2. The Settings tab's "Import .finch"
  is the only mutation in Phase 1.0, and it doesn't go through the chokepoint
  — it goes through the import pipeline (`Pack.parse` → `Pack.extract` →
  read-only validate/audit/swap).
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
script that writes to `ios/FinchCore/Tests/ParityTests/Fixtures/`).

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
The web app has no Inbox page; we mirror that on iOS. (The iCloud
`Documents/finch/` folder is **deferred to Phase 5** — see §3 and §10. In
Phase 1.0 import is exclusively via the system file picker and export
exclusively via `ShareLink`; no iCloud container is requested.)

**Settings tab — "Import .finch" button**:

- Renders a SwiftUI `.fileImporter(isPresented:, allowedContentTypes: [.zip, .finch])`
- The `.finch` UTI is registered as a child of `UTType.zip` per the plan's
  §14.1 (".finch UTI + extension registration, child of UTType.zip"). The UTI
  registration lives in `ios/FinchApp/Info.plist` (`UTExportedTypeDeclarations`).
- The picker handles Mail attachments, AirDrop, "Save to Files" from any app,
  and the Files app itself — all routes converge on a single `URL`.
- On pick, the URL is handed to the import pipeline (`Pack.parse` →
  `Pack.extract` → validate/audit/swap; see §4).
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

**iCloud `Documents/finch/` folder — deferred to Phase 5**:

The iCloud container, the `Documents/finch/` folder, and the per-platform
`ubiquityIdentityToken` / `forUbiquityContainerIdentifier:` handling are
**out of scope for Phase 1.0** and move to Phase 5 (sync), alongside the
auto-pack debounce + folder-watcher that make the folder useful. In Phase 1.0
there is no iCloud container request: the user imports `.finch` files via the
system file picker (which handles Mail attachments, AirDrop, "Save to Files,"
and the Files app), and exports via `ShareLink`. The file picker still reaches
files the user has saved to iCloud Drive through the standard document-picker
plumbing — we just don't own or enumerate a dedicated folder.

**Why no Inbox tab**: the web app has no Inbox page; import is a single button
in Settings. Diverging from the web's UX needs a reason. Phase 1.0 doesn't
have that reason — the Inbox concept (and the iCloud `Documents/finch/` folder
it would list) becomes useful in Phase 5 when the auto-pack debounce +
folder-watcher lands. Until then, the system file picker is enough.

## §3. FinchCore layout

`FinchCore` is a single SwiftPM module at `ios/FinchCore/`, organized into
**flat folders** rather than separate modules. The architecture mirrors the
web's `core/` + `domain/` split (`frontend/lib/db/core/` for engine code,
`frontend/lib/db/domain/` for per-domain code) but is consolidated into one
module for Phase 1.0 simplicity — there is no multi-module layered split. (An
earlier draft proposed a six-module split — DB/Schema/Money/Pack/Audit/Project
— plus an `ICloud` module; both are dropped for Phase 1.0. One module keeps the
build graph and the package manifest trivial; the layering can be re-introduced
as separate targets later if any consumer needs `Money` in isolation. The
iCloud container is **deferred to Phase 5** — see §2/§10 — so there is no
iCloud code in Phase 1.0. Both import (file picker) and export (`ShareLink`)
call `Pack` directly from the app layer.)

```
ios/FinchCore/Sources/FinchCore/
├── Storage/   — GRDB DatabaseQueue + WAL setup, the SCHEMA DDL +
│               triggers, the MIGRATIONS replay, the Money Decimal
│               codec, and the Pack build/validate/swap engine
├── Project/   — the Tx projection from entries/postings
│               (port of lib/db/state.ts::projectState) + the
│               read-only Audit pass (port of auditLedger)
└── Selectors/ — the 7 Phase-1.0 pure selectors (the remaining 25
                are added here in Phase 1.5)
```

**Folder responsibilities** (one module — these are organizational folders,
not separate compilation units, so there are no inter-module import rules to
enforce):

1. `Storage/` — the lowest layer: wraps GRDB `DatabaseQueue` + WAL setup + a
   typed `Row` codec, issues the `SCHEMA` DDL + triggers, replays `MIGRATIONS`,
   holds the `Money` Decimal value type (pure Foundation `Decimal` + currency
   code + locale-aware formatting), and houses the `Pack` engine (build,
   validate, audit-gate, swap).
2. `Project/` — reads entries/postings and produces `Tx[]` (the projection),
   and runs the read-only `Audit` pass over the schema + projection, returning
   typed problems.
3. `Selectors/` — the **7 pure Phase-1.0 selectors** (`accountBalance`,
   `selectTransactions`, `categorySpend`, `budgetProgress`, `cycleWindow`,
   `merchantStats`, `anomalyScore`); they take the in-memory `Tx[]` /
   `AccountRow[]` / `Budget[]` as input and **read no DB**. The remaining 25
   selectors land here in Phase 1.5.

(The iCloud folder-listing code — which would list files and hand URLs to
`Pack` — is deferred to Phase 5 with the rest of the iCloud container work. In
Phase 1.0 the SwiftUI app layer calls `Pack` directly.)

**`Store` folder** (Phase 2, not in Phase 1.0): the on-device write chokepoint
port. Lands at `ios/FinchCore/Sources/FinchCore/Store/`.

**Why one module**:

- A single module keeps the `Package.swift` manifest and the build graph
  trivial for Phase 1.0 — no inter-target dependency wiring, no symbol-graph
  enforcement to maintain. The conceptual layering survives as folder
  boundaries (`Storage/` → `Project/` → `Selectors/`), and the folders can be
  promoted to separate SwiftPM targets later if a consumer needs `Money` or
  `Storage` in isolation.
- The `Money` Decimal codec is self-contained inside `Storage/`, so it can be
  lifted to a separate `FinchMoney` target later if any other app wants it.
- The GRDB wrapper inside `Storage/` is thin, so Phase 2 can swap to a
  different driver (e.g., a `bun:sqlite` test driver) with no changes to the
  `Project/` or `Selectors/` code.
- `Pack` (in `Storage/`) being the single import/export chokepoint means the
  system file picker UX (SwiftUI `.fileImporter`) and the export UX
  (`ShareLink`) both go through one well-tested path — and when the Phase 5
  iCloud folder UX lands, it plugs into the same chokepoint.
- The `Audit` pass (in `Project/`) does not depend on `Pack`, so we can run
  audit on an arbitrary DB without the pack engine — useful for the on-device
  audit gate in the import pipeline and for the parity suite.

**No architecture-enforcement test in Phase 1.0**: there is no
`FinchCoreArchitectureTests` symbol-graph test in 1.0 — with one module and
folder-only boundaries there are no import directions to police. (The web side
uses `eslint no-restricted-imports` for its `core/`/`domain/` split; a
Swift-native equivalent only becomes worthwhile if/when the folders are
promoted to separate targets in a later phase.)

## §4. The `.finch` pipeline + audit gate

The pack engine exposes three pure functions (no UI, no SwiftUI) that the
view-model layer wraps in a `Task` and feeds into `@Observable` state:

- `Pack.parse(_ bytes: Data) -> ParsedPack` — reads the `.finch` zip bytes in
  memory and returns the parsed manifest + zip handle.
- `Pack.extract(_ parsed: ParsedPack, to destDir: URL) -> ExtractedPack` —
  inflates a `ParsedPack` to a staging directory on disk.
- `Pack.build(_ input: PackInput) -> (bytes: Data, manifest: Manifest)` — the
  export direction: stamps + checksums the VACUUM'd clone and returns the
  packed bytes + the manifest.

The import pipeline (file picker; the Phase 5 folder-watcher will also drive it)
threads `parse` → `extract` → validate → migrate → audit → swap → project; the
import orchestrator returns a typed `Result<ImportedPack, PackError>`. The
export orchestrator wraps `Pack.build` and returns
`Result<ExportedPack, PackError>`.

### Import — 6 steps

**Step 1 — Parse + extract to staging** (`Pack.parse(_ bytes) -> ParsedPack`
then `Pack.extract(_ parsed, to: staging) -> ExtractedPack`):

```
staging = tmp/import-staging/<uuid>/
let parsed = Pack.parse(Data(contentsOf: url))   // .finch is a zip, read via ZIPFoundation
Pack.extract(parsed, to: staging)                // inflate to staging/
```

Extraction uses **ZIPFoundation** (the pinned dep — see §6), not a system
`unzip` shell-out. The staging directory holds: `manifest.json`,
`finch.sqlite3`, `attachments/<entry_id>/<attachment_id>.<ext>`. If anything in
steps 2-6 fails, the staging directory is deleted and the live DB is untouched.

**Step 2 — Manifest validation** (`PackValidator.validate(_ manifest: Manifest) -> Result<Void, ManifestError>`):

- `schema_version == "2026-06-14T00:00:00Z"` (the shared lineage from plan
  §4.6; the constant lives at `Schema/SCHEMA_VERSION`)
- `db.sha256` matches the actual file's sha256 (computed with
  `CryptoKit.SHA256`)
- `db.row_counts` keys are the 15-table `CANONICAL_TABLES` set
  (`lib/db/queries/metadata.ts:47`): `ledgers`, `account_groups`, `accounts`,
  `categories`, `counterparties`, `entries`, `postings`, `entry_tags`,
  `entry_attachments`, `budgets`, `tags`, `scheduled_templates`,
  `scheduled_splits`, `exchange_rates`, `app_state`
- `attachments.count` matches the on-disk file count; per-file sha256 in
  `attachments.items[]` matches
- A missing or malformed `manifest.json` returns `manifestMissing` /
  `manifestMalformed` (both surfaced as `PackError.manifestInvalid`)

There is **no pre-DE branch**: Phase 1.0 is fresh-DB-only. The web has no
pre-DE codepath — the double-entry cutover data-move is intentionally absent
from `MIGRATIONS` (it lives only in git history; the canonical `SCHEMA`
already carries the post-cutover shape). A `.finch` is only valid if its
`schema_version` is on the shared lineage and its migrations replay cleanly;
there is nothing to "upgrade from."

**Step 3 — Open with GRDB + run migrations** (`FinchStore.open(staging: URL) -> Result<FinchStore, OpenError>`):

- `GRDB.DatabaseQueue(path: staging/finch.sqlite3)` opened in WAL mode
  (`PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL`) — matches the web's
  `better-sqlite3` setup from `lib/db/core/driver.ts`
- Migrations run on open: each dated entry in the shared `MIGRATIONS` record
  from `lib/db/core/schema.ts` is ported to Swift and replayed if its key
  sorts after the DB's recorded version; idempotent on a DB already at the
  target version. The recorded version lives in the `db_metadata.schema_version`
  **table column** (`ensureMetadataRow`), not `PRAGMA user_version`.
- There is **no pre-DE / DE-cutover migration to port**. The double-entry
  cutover data-move is intentionally absent from the web's `MIGRATIONS` (dead
  code in git history; no pre-DE databases exist pre-release). Phase 1.0 opens
  fresh, post-cutover DBs only — migration is a schema-version replay, not a
  data reshaping.
- The migration runner is `Schema.Migrator` (a thin wrapper around GRDB's
  `DatabaseMigrator`); each migration is a Swift `Migration` record that
  mirrors the corresponding entry in the web's `MIGRATIONS` record.

**Step 4 — Audit GATE** (`Audit.run(on: GRDB.DatabaseQueue) -> [AuditProblem]`):

This is the gate. If `Audit.run` returns **any** problem, the import is
**refused** — the import orchestrator returns
`.failure(.auditFailed([AuditProblem]))`,
the staging directory is deleted, and the live DB is untouched. This mirrors
the web's `assertImportAuditClean`, which **throws** on any problem before the
swap. (Only the explicit user-driven **Force import** hatch — an iOS-only
divergence, D7 — bypasses this gate; the web has no skip path.)

- Walks `entries` + `postings` + `accounts` + `categories` + `ledgers`
- Returns the 10 typed problem classes from
  `lib/db/core/entries.ts::auditLedger` (the `AuditProblem.code` union):
  1. **`unsealed`** — entry never sealed (torn write)
  2. **`unbalanced`** — an entry's postings don't sum to 0
  3. **`too-few-legs`** — fewer than 2 legs
  4. **`no-account-leg`** — no account leg
  5. **`currency-mismatch`** — posting not in its account's currency
  6. **`cross-ledger`** — posting references another ledger
  7. **`base-identity`** — `amount != amount_base` in the base currency (I9)
  8. **`kind-shape`** — an entry's legs don't match its kind's expected shape
  9. **`trial-balance`** — a ledger's postings don't sum to 0
  10. **`balance-drift`** — account cached balance ≠ balance derived from
     postings
- Returns an empty array for a clean DB
- Swift type: `struct AuditProblem: Equatable, Sendable` with three fields —
  `code: String` (one of the 10 problem-class codes above), `entryId: String?`
  (nil for the ledger-wide `trial-balance` / `balance-drift` classes), and
  `detail: String` (a human-readable description of the specific violation)
- Parity test: a fixture DB seeded with one row per problem class (10
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
  `Application Support/attachments/` (overwriting where ids collide; the path
  structure `attachments/<entry_id>/<attachment_id>.<ext>` is identical on
  both sides — `entry_attachments.entry_id` is the FK)
- Open the live DB
- **iOS hardening (not web parity)**: re-run `auditLedger` on the swapped DB
  as defense in depth — catches a race where another process modified the
  staging file between the step-4 gate and the swap. The web performs no
  post-swap re-audit (its gate is `assertImportAuditClean` pre-swap, full
  stop); this extra pass is a native belt-and-suspenders check, not part of
  the parity contract.
- If any step fails: roll back to `.bak.<timestamp>`, return typed
  `PackError.swapFailed(SwapError)`

**Step 6 — Project** (`Projection.run(dbQueue: GRDB.DatabaseQueue) -> [Tx]`, all ledgers — no ledger filter, matching `projectState`):

- The full `Tx` projection from `lib/db/state.ts::projectState` is ported to
  Swift
- Single-entry skin (the `Tx` type the UI consumes) is preserved — opening /
  equity legs filtered out, splits flattened, category resolved via join
- `FinchStore` keeps the projected `Tx[]` in memory after open; Phase 1.5
  selectors will read from this in-memory array, matching the web's
  `lib/select.ts` shape (the web's selectors take `Tx[]` as input, not raw
  DB rows)

### Export

`Pack.build(_ input: PackInput) -> (bytes: Data, manifest: Manifest)` (the
export orchestrator wraps it in `Result<ExportedPack, PackError>`):

- Open the live DB (read-only `DatabaseQueue` opened with `.read-only`)
- Run `VACUUM INTO 'tmp/export/finch.sqlite3'` (matches the web's pack build
  path in `lib/db/core/pack.ts::buildPack`)
- Stamp + checksum the VACUUM'd clone before reading bytes
- Build a fresh `manifest.json` with the current `schema_version` +
  `db.sha256` + per-file attachment checksums + `db.row_counts` (the 15-table
  `CANONICAL_TABLES` set)
- Copy `attachments/` → `tmp/export/attachments/`
- Zip the staging directory via **ZIPFoundation** → `bytes` for
  `<ledger-slug>-<yyyy-mm-dd>.finch`
- Hand the URL to SwiftUI's `ShareLink` (the user picks the share
  destination)

### Error model

One `PackError` enum with the five import-pipeline cases (one per failure point
below). The PLAN's `PackError` is a superset that also carries the parse/extract
validation cases — see PLAN Task 4. The five pipeline cases:

- `manifestInvalid(reason: ManifestError)` — step 2 (covers
  `manifestMissing` / `manifestMalformed` / sha256 / row-count / attachment
  mismatches)
- `migrationFailed(step: String, underlying: Error)` — step 3
- `auditFailed([AuditProblem])` — step 4 (**the gate**; import is refused,
  carrying the typed problem list)
- `swapFailed(SwapError)` — step 5
- `exportFailed(underlying: Error)` — export

The UI shows these as alerts with a "View details" disclosure that lists the
audit problems (`entryId` + class + context). On `auditFailed` the user can
choose "Cancel" or **"Force import"**.

**Force import is a deliberate iOS-only divergence (D7).** The web has **no
skip path** — `assertImportAuditClean` throws and that is final. iOS keeps a
recovery hatch for users who know their data is intentionally non-compliant
with the audit gate (e.g., a manually-edited `.finch`): it skips the step-4
gate but still runs the rest of the pipeline (manifest validation, migration,
atomic swap, project). The "Force import" button lives in **Settings ›
Advanced** (always visible; not behind a debug flag).

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
row shows date, merchant/description, category badge, amount — rendered in
the active ledger's **display currency** via the same ledger-base→display
conversion the web's `useMoney` applies (see "Money" below), never the row's
raw native amount.

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

Tapping a row **is deferred (D4)**: **Transaction Detail is out of scope for
Phase 1.0** (it lands in a later phase). The Activity tab is a read-only list
only; rows are non-navigating in 1.0. When Transaction Detail does land it
will show date, amount, account(s), category, tags, notes, splits (if any),
and audit status — all read-only; attachments stay deferred to Phase 6
(Share Extension receipts).

Search bar at the top filters the in-memory `Tx[]` **client-side** via a
case-insensitive `tx.merchant.includes(query)` (mirroring the web's Activity
page, which filters its in-memory transaction list by `merchant.includes` —
it does **not** call a DB query). There is no FTS5 here: the `entries_fts`
virtual table indexes `description` + `notes` for a *different* search surface
that the Activity page never invokes, and Phase 1.0 reads exclusively from the
projected `Tx[]`, not from `listTransactions`/DB queries. (FTS-backed search
is a later-phase upgrade if wanted.)

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

Progress bar color uses a green/yellow/red banding — green (under 70%), yellow
(70-90%), red (over 90% or over budget) — and the "N days left in period"
countdown shown in the mockup. **Both are intentional native enhancements, not
web parity**: the web's budget bar is 2-state (`over ? destructive : primary`)
and shows the remaining-amount text with no day countdown. The native app adds
the three-band color and the day countdown deliberately; they must not be
asserted by the parity suite. Tap a row to filter the Activity tab to that
category.

Phase 1.0 doesn't include edit/add for budgets (those land in Phase 2 with
the write chokepoint).

### Money — display-currency conversion (all tabs)

Every balance, amount, total, and net-worth figure across Accounts, Activity,
and Budgets renders through a **ledger-base → display-currency conversion**,
mirroring the web's `useMoney` (`components/use-money.ts`): amounts are stored
in the active ledger's base currency, and the UI converts to the active
ledger's chosen display currency before formatting. Nothing renders a row's
raw native amount. The conversion path is a rate map + convert ported from the
web; `Money.formatted(in: displayCurrency)` is the single formatting entry
point. In Phase 1.0 the display currency is the active ledger's base currency
(no per-ledger override UI yet), so the conversion is identity for
base-currency rows — but the conversion seam is in place so totals across
mixed-currency rows stay correct and Phase 1.5's override drops in without a
UI rewrite.

### Detail views — deferred (D4)

**Transaction Detail and Account Detail are out of scope for Phase 1.0.** Both
move to a later phase. Phase 1.0 ships the three read-only list tabs only —
Accounts (grouping + net-worth footer), Activity (date-grouping + pagination +
category badge), Budgets (grouping + period header + threshold colors +
totals). Tapping an Accounts row still pushes the Activity tab with that
account's filter pre-applied (that's a list-to-list navigation, not a detail
view); Activity rows are non-navigating in 1.0.

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

- **ZIPFoundation 0.9.19** (pinned) — zip read/write for the `.finch` pack
  module. A `.finch` is a zip; the `Pack` module needs to extract incoming
  packs (import) and build outgoing ones (export), and the system `UTType.zip`
  / `Archive` APIs do not give us programmatic in-memory extract/build with
  per-entry control. Pinned to an exact version (D6) so DEFLATE output is
  reproducible across CI runs. Note: byte-identical packs vs. the web's JSZip
  are an explicit **non-goal** (different DEFLATE implementations); parity is
  asserted on round-tripped content + sha256, not on raw pack bytes — see §8.
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
- **Third-party SwiftPM deps for Phase 1.0: GRDB.swift and ZIPFoundation
  (both pinned) — and nothing else.** Everything above besides those two is a
  system framework. The fixture export script on the web side
  (`frontend/scripts/export-fixtures.ts`, a new Phase 1.0 artifact) uses only
  `bun:test` + the existing `lib/db/core/seed.ts` + the new
  `lib/select.fixtures.ts` `CASES` array to produce fixtures — no new web-side
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
    let account: String            // account id — `projectState` sets
                                  // `account: String(p.account_id)`
                                  // (`lib/db/state.ts:71`), not the name
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

// Project/AccountRow.swift, Category.swift, Counterparty.swift, Ledger.swift,
// Budget/BudgetRow.swift — ported from lib/db/domain/<x>/types.ts.
// All amounts Decimal.
```

The shapes above are pinned to `_CANONICAL_WEB_FACTS.md`: `Tx.nativeAmount`
(not `amountNative`), `Tx.account` = account **id** (`projectState` sets
`account: String(p.account_id)`, `lib/db/state.ts:71`), and `TxSplit.amountBase`
(the ledger-base sibling of `TxSplit.amount`). The **full** row/option type
set — `AccountRow`, `BudgetRow`/`Budget`, `Ledger`, `Category`, `Counterparty`,
`ListOptions`, plus the selector return structs (`CycleWindow`,
`BudgetProgress`, `MerchantStats`, `AnomalyScore`) — is defined inline in the
Phase 1.0 PLAN's port tasks (the types/projection task), so each task is
self-contained; this design fixes the canonical field names, the PLAN fixes
the exact members.

The `Tx` projection from `lib/db/state.ts::projectState` is the single largest
piece of Phase 1.0 porting work. It walks entries + postings + counterparties
+ categories + tags + accounts + currencies + rates and produces a flat
`Tx[]` with opening/equity legs filtered out, splits flattened, and category
names resolved via join.

The `AuditProblem` type (see §4 step 4) is a **struct**
`{ code: String; entryId: String?; detail: String }`, not an
enum-with-associated-values. `code` is one of the 10 problem-class codes;
`entryId` is nil for the ledger-wide `trial-balance` / `balance-drift` classes;
`detail` is a human-readable description of the specific violation.

## §8. Parity suite

The parity gate is the headline quality bar. It enforces that the Swift port
and the TypeScript web app produce identical outputs for the same inputs, to
the cent. Three layers:

### 8.1 — `Tx` projection parity

For every golden DB fixture, Swift's `Projection.run(dbQueue:)` emits the same `Tx[]`
as the web's `lib/db/state.ts::projectState`. Comparison is structural
(struct-by-struct `Equatable` comparison) and runs at the Swift test level
against JSON fixtures.

### 8.2 — `auditLedger` parity

For every fixture DB (golden + property-generated), Swift's `Audit.run(on:)`
returns the same typed problem set as the web's
`lib/db/core/entries.ts::auditLedger`:

- Empty array for clean DBs
- Matching outcomes for seeded-corruption fixtures — one per problem class
  (10 fixtures):
  1. `unsealed.finch` — an entry never sealed (torn write)
  2. `unbalanced.finch` — an entry's postings don't sum to 0
  3. `too-few-legs.finch` — an entry with fewer than 2 legs
  4. `no-account-leg.finch` — an entry with no account leg
  5. `currency-mismatch.finch` — a posting not in its account's currency
  6. `cross-ledger.finch` — a posting referencing another ledger
  7. `base-identity.finch` — `amount != amount_base` in the base currency
  8. `kind-shape.finch` — an entry's legs don't match its kind's shape
  9. `trial-balance.finch` — a ledger's postings don't sum to 0
  10. `balance-drift.finch` — account cached balance ≠ derived balance

### 8.3 — `.db` round-trip parity

For every golden DB fixture:

- Open with GRDB → run migrations → run `projectState` → run `auditLedger`
  → expect clean
- Web-side: open the same file with `better-sqlite3` → run migrations →
  run `projectState` → run `auditLedger` → expect clean
- Compare the resulting `Tx[]` structurally (via JSON serialization)

There is **no `pre-de.finch` round-trip** (D1). The web has no pre-DE codepath
to compare against (the DE cutover data-move is absent from `MIGRATIONS`), so a
"migrate a pre-DE pack" test would exercise logic that doesn't exist on either
side. Phase 1.0 round-trips fresh, post-cutover DBs only; migration is a
schema-version replay. (Raw-byte pack identity is also a non-goal — see §6 on
ZIPFoundation vs JSZip DEFLATE; round-trip parity is asserted on content +
sha256 of the round-tripped DB, not on pack bytes.)

### 8.4 — Fixture export script

The fixture source is a **new web-side module, `frontend/lib/select.fixtures.ts`**
(a Phase 1.0 prerequisite, "Task 0"), which exports
`export const CASES: SelectorFixture[]` — deterministic cases (fixed ids, no
`Math.random`), each `{ name, selector, input, expected, seed? }`. `CASES`
becomes the single source of truth, consumed by **both** the web oracle
(`lib/select.test.ts` iterates `CASES` and asserts each) and the Swift parity
target (via the export script). It is **not** scraped from `select.test.ts` —
that file is 74 flat `test(...)` calls with inline literals and `Math.random`
ids, which has no structured, callable source to extract.

`SelectorFixture.input` is pinned to the **named-object** shape (one keyed
object per selector's parameters, e.g.
`{ accounts: [...], accountId: "acc_1" }`), **not** a positional array or
`unknown` — the same shape both `lib/select.test.ts` and the Swift decoder
read. (Pinned in `IOS_MACOS_WIRE_FORMAT.md §5.1.)

A new web-side script at `frontend/scripts/export-fixtures.ts` (a Phase 1.0
artifact to be created — it does not exist yet) that:

1. Imports `CASES` from `lib/select.fixtures.ts` and serializes each case to
   JSON: `{ name, selector: "accountBalance", input: { ... }, expected: ... }`
   (named-object `input`)
2. Generates the 10 audit-corruption fixtures by running the seed with a
   mutation per problem class
3. Writes everything to `ios/FinchCore/Tests/ParityTests/Fixtures/` (a
   `selector.json`, a `sample.finch`, and the 10 `*-corrupt.finch` files —
   **no** `pre-de.finch`, per D1)
4. Is invoked by the macos CI job before the parity target runs, so fixtures
   stay in sync with the web

The script is Bun-only (uses `bun:test` + `lib/db/core/seed.ts` +
`lib/select.fixtures.ts`). It's checked into the repo at
`frontend/scripts/export-fixtures.ts` with its own `bun test` smoke test.

### 8.5 — Test target structure

Three SwiftPM test targets in `ios/FinchCore/`:

- `FinchCoreTests` — unit tests for the `FinchCore` folders (`Storage/`
  Money + DB + Schema + Pack, `Project/` projection + Audit, `Selectors/`);
  runs on both `macOS` and `iOS Simulator` destinations
- `ParityTests` — the cross-implementation parity gate (the JSON goldens
  + `.db` round-trip + audit fixtures); runs on `macOS` destination only
  (the .db files are tested via the GRDB-macOS code path, which is closer
  to iOS GRDB than the Linux Bun path is)
- `FinchAppTests` — UI snapshot tests for the 4 tabs (light/dark, a few
  Dynamic Type sizes); runs on `iOS Simulator` destination

## §9. CI

One new GitHub Actions job on a pinned `macos-15` runner with Xcode `16.3`.
The Linux-side `frontend/` job is unchanged.

### 9.1 — macos job (new)

A single job: install Bun, export the fixtures, run `swift test` (which builds
+ tests FinchCore *and* the ParityTests target against the freshly-exported
fixtures), then `xcodegen generate` the Xcode project and `xcodebuild` the
FinchApp build + test on the iPhone 16 simulator. (This matches the PLAN's
Task 12 job — `swift test` for the SwiftPM targets, `xcodegen` +
`xcodebuild` for the app.)

```yaml
macos:
  name: iOS (swift test · parity · app build/test)
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4
    - name: Select Xcode 16.3
      run: sudo xcode-select -s /Applications/Xcode_16.3.app   # GRDB 7 requires 16.3+
    - name: Setup Bun
      uses: oven-sh/setup-bun@v2
      with: { bun-version: "1.3.11" }
    - name: Install web deps
      working-directory: frontend
      run: bun install --frozen-lockfile
    - name: Export fixtures
      working-directory: frontend
      run: bun run scripts/export-fixtures.ts  # writes to ios/FinchCore/Tests/ParityTests/Fixtures/
    - name: swift test (FinchCore + ParityTests)
      working-directory: ios/FinchCore
      run: swift test
    - name: Generate Xcode project
      working-directory: ios
      run: xcodegen generate
    - name: Build + test FinchApp (iOS Simulator)
      working-directory: ios
      run: xcodebuild -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test
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
decisions." The Phase 1.0 dry-run resolved the ones that were ambiguous;
they're recorded here as resolved.

**Resolved for Phase 1.0**:

- **iCloud container / `Documents/finch/` folder — RESOLVED: deferred to
  Phase 5.** Phase 1.0 imports via the system file picker and exports via
  `ShareLink`; it requests no iCloud container and owns no folder. The
  container request, the `ubiquityIdentityToken` / `forUbiquityContainerIdentifier:`
  per-platform handling, the `ICloud` module, the conflict-copy UX, and the
  folder naming/visibility question all move to Phase 5 (sync), where the
  auto-pack debounce + folder-watcher make them useful. (See §2 and §3.)
- **Pre-DE migration — RESOLVED: dropped (D1).** The web has no pre-DE
  codepath; Phase 1.0 is fresh, post-cutover-DB-only. No `pre-de.finch`
  fixture, no DE-cutover port. (See §4 and §8.3.)
- **`.finch` UTI + extension registration — RESOLVED: Phase 1.0**, via
  `UTExportedTypeDeclarations` in `ios/FinchApp/Info.plist` (`.finch` as a
  child of `UTType.zip`). The per-platform polish (Quick Look generator,
  document picker icon) can land later.
- **Day-1 locales — RESOLVED: `en` only for Phase 1.0.** The web ships
  `en + zh-CN`; native uses `Localizable.strings` and ships `en` at day 1.
  `zh-CN` is added in a later phase if the user base warrants it.

**Still open, but Phase 5 by design (not Phase 1.0 blockers)**:

- **Pack cadence + sweep policy** — the right idle-debounce before
  auto-packing, and how often to sweep orphaned attachment files. Phase 5.

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
- **Transaction Detail + Account Detail views** — deferred (D4) to a later
  phase. Phase 1.0 ships the three read-only list tabs only (Accounts,
  Activity, Budgets); rows are non-navigating except the Accounts→Activity
  list-to-list push.
- **iCloud container + `Documents/finch/` folder + `ICloud` module** —
  Phase 5. Phase 1.0 imports via the system file picker and exports via
  `ShareLink`; no iCloud container is requested.
- **Receipt attachments** — Phase 6 (Share Extension + `PhotosPicker`).
  Phase 1.0 (once Transaction Detail lands in a later phase) has no
  attachment UI either way.
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

(Inline review at write time; not part of the published spec. Updated after
the 2026-06-13 Phase 1.0 dry-run — see `_PHASE_1_0_GAP_REPORT.md`.)

- **Hardening applied (this pass)**: dropped the pre-DE / DE-cutover migration
  claim (§4 step 3) and the `pre-de.finch` round-trip (§8.3) — D1; corrected
  Activity search from FTS5/`listTransactions` to client-side
  `merchant.includes` (§5) — D3; made the audit gate explicit and the
  `PackError` model five-cased (§4); deferred Transaction + Account Detail
  (§5/§11) — D4; added ZIPFoundation as a pinned dep and corrected the
  "no other third-party deps" claim (§6) — D6; labeled Force import a
  deliberate iOS-only divergence (§4/§11) — D7; deferred the iCloud container
  + `ICloud` module to Phase 5 (§2/§3/§10); pointed §8.4 at the new
  `lib/select.fixtures.ts` `CASES` array (Task 0) with a named-object `input`.
- **Known limits / things this design does NOT settle** (the PLAN owns these):
  the exact members of `AccountRow` / `BudgetRow` / `Ledger` / `Category` /
  `Counterparty` / `ListOptions` and the selector return structs are defined
  inline in the PLAN's port tasks, not here (§7). The Xcode project-generation
  tooling, the `Package.swift` target declarations, and the CI root-path are
  PLAN concerns. The money-conversion rate-map source and exact `Money` API
  are sketched (§5 "Money") but the PLAN pins the signature.
- **Internal consistency**: §4's `Pack.parse`/`Pack.extract`/`Pack.build` API
  matches §3's single-module folder layout (`Pack` in `Storage/`; no iCloud
  code in 1.0). §5's UI references §4's five `PackError` cases consistently. §8's 10
  audit fixtures match §4's 10 problem classes 1:1. §6's GRDB version matches
  §3's `DB` module description. The iCloud deferral is consistent across
  §2/§3/§6/§10/§11.
- **Scope**: focused on Phase 1.0. Phase 1.5 and Phase 2 are referenced as
  future specs but not designed here. §11 enumerates the firm out-of-scope
  items (now including the deferred detail views and iCloud container) so the
  implementation doesn't pull later-phase work forward.
- **Residual ambiguity**: the post-swap re-audit (§4 step 5) is labeled iOS
  hardening, not web parity, so it must not be asserted by the parity suite.
  Raw pack-byte identity is a stated non-goal (§6/§8); parity rests on
  round-tripped content + sha256.
