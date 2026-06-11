# finch for iOS & macOS — Phased Roadmap (2026-06)

> **Status**: roadmap sketch — 1-2 pages per phase. Not an implementation plan
> for any phase. The companion documents are:
>
> - `plans/IOS_MACOS_PLAN.md` — the direction brief (what native must do, the
>   architecture choices, the trade-offs)
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` — the **full design** for Phase 1.0
>   (the only phase with detailed design work, because it's the one being
>   built first)
> - `plans/IOS_MACOS_ROADMAP.md` (this file) — the **8-phase arc**: each
>   phase's goal, scope, non-goals, dependencies, acceptance criteria, and
>   open questions, kept short so a reviewer can read the whole arc in one
>   sitting
>
> Phase numbering follows the plan's §13, with the single exception that
> Phase 1 is split into **1.0** (Accounts / Activity / Budgets / Settings;
> ~1,500 lines TS to port) and **1.5** (Insights + the remaining 10-11
> selectors + JSON-golden parity). The split is described in detail in
> `IOS_MACOS_PHASE_1_DESIGN.md`. All later phases are sketched here as
> 1-phase units.
>
> Each phase is independently shippable. The per-increment CI gate from
> `IOS_MACOS_PHASE_1_DESIGN.md §9` ("build + unit/parity tests + UI snapshot
> smoke, green before merge") applies to every phase.

---

## Phase 1.0 — FinchCore + read-only iPhone app (Accounts / Activity / Budgets / Settings)

**Goal**: Ship a working, verifiable iPhone app that opens a `.finch` pack
via the system file picker, displays 4 read-only tabs, and exports a fresh
`.finch` via the system share sheet. Parity suite green: `Tx` projection +
`auditLedger` + `.db` round-trip all match the web to the cent.

**Scope (in)**:

- `ios/` repo layout: `ios/FinchCore/` (SwiftPM) + `ios/FinchApp/` (Xcode app
  target)
- FinchCore modules: `DB`, `Schema`, `Money`, `Audit`, `Project`, `Pack`,
  `ICloud` (7 modules, strict layer rules per `IOS_MACOS_PHASE_1_DESIGN §3`)
- Swift ports of: `lib/db/core/schema.ts` (DDL + triggers + FTS5),
  `lib/db/core/repo.ts` (Exec/Row types), `lib/db/core/seed.ts` (system
  equity categories), `lib/db/core/pack.ts` (build + validate +
  atomic-swap), `lib/db/core/checksum.ts`, `lib/db/core/paths.ts`,
  `lib/db/core/driver.ts` (GRDB), `lib/db/state.ts::projectState` (the
  `Tx` projection), `lib/db/core/entries.ts::auditLedger` (read-only half)
- 4 iOS screens: Accounts (list + net worth footer), Activity (list +
  FTS5 search + Transaction Detail), Budgets (progress bars + period
  header), Settings (Import / Export / DB info / audit status / active
  ledger switch / about)
- 3 selectors ported: `accountBalance`, `selectTransactions`,
  `budgetProgress` (plus the period/rollover math from
  `lib/budgets/{period,rollover}.ts`)
- `.finch` import via system file picker (Settings tab → "Import .finch")
- `.finch` export via `ShareLink` (Settings tab → "Export .finch")
- iCloud `Documents/finch/` folder (visible in Files app; not enumerated
  by the app)
- Parity: `Tx` projection parity + `auditLedger` parity (8 corruption
  fixtures) + `.db` round-trip parity (sample + pre-DE)
- CI: macos-latest runner, 3 test targets (`FinchCoreTests`, `ParityTests`,
  `FinchAppTests`)

**Non-goals (out)**:

- Write paths — no `postEntry` / `rebuildEntry` / `deleteEntry` in
  FinchCore; no `Store` module
- iPad / macOS adaptive layout
- Auto-pack debounce + iCloud folder-watcher
- App Intents / Siri / Share Extension receipts / Spotlight / notifications
  / biometric lock
- Widgets / Watch / Live Activities
- Inbox tab / folder-listing UI
- Per-ledger display-currency override UI (display currency = active
  ledger's base in 1.0)
- In-app theme override (follows system light/dark)
- Insights tab (Phase 1.5)
- Android

**Dependencies**: none (this is phase 1; nothing to depend on)

**Acceptance criteria**:

- `bun test frontend/lib` (web) + `xcodebuild test FinchCore
  -destination 'platform=macOS'` + `xcodebuild test ParityTests
  -destination 'platform=macOS'` + `xcodebuild test FinchApp
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'` all
  green on every PR
- The 8 audit corruption fixtures produce the same typed problem set in
  Swift `Audit.run(on:)` as in TS `lib/db/core/entries.ts::auditLedger`
- The pre-DE `.finch` fixture migrates successfully on open and produces
  the same `Tx[]` as the web's `projectState` for the same input
- The iPhone simulator app can: (a) import a `.finch` from the system
  file picker, (b) display the Accounts/Activity/Budgets tabs with
  correct data, (c) export a fresh `.finch` to the system share sheet
- The audit gate refuses an import when a corruption fixture is picked

**Open questions**:

- GRDB 7.11.0 ↔ `better-sqlite3` 3.46+ behavior parity for edge cases
  (the FTS5 tokenizer for `O'Reilly` / `AT&T`; `COLLATE NOCASE` on
  `counterparties.name`; the `current_timestamp` rounding mode)
- SwiftUI `.fileImporter` quirks on iOS 26 simulator (the .finch UTI
  registration via `UTExportedTypeDeclarations`; the file-picker
  animation/dismissal behavior)
- `CryptoKit.SHA256` performance on large packs (the manifest must
  hash every attachment — a 1 GB pack with thousands of attachments
  could be slow)

---

## Phase 1.5 — Insights tab + remaining selectors + JSON-golden parity

**Goal**: Add the Insights tab (5th tab) + port the remaining 10-11
selectors from `lib/select.ts` + ship the JSON-golden parity test
infrastructure. The app becomes "credible first release" coverage of
the web's read surface.

**Scope (in)**:

- `Selectors` module in FinchCore: imports `DB`, `Money`, `Project`
- Ports of: `categorySpend`, `currentMonth`, `prevMonth`,
  `monthlySpending`, `monthlyCashflow`, `topCategoryDeltas`,
  `dailySpending`, `netWorthByMonth`, `monthForecast`,
  `incomeCategoryFlow`, `weeklyDigest` (10-11 selectors, all from
  `lib/select.ts`)
- Insights tab UI: net worth chart (Swift Charts line), monthly
  cashflow chart (bar), top category deltas list, forecast figure
  card, weekly digest card
- Per-ledger display-currency override UI in Settings (the existing
  `displayCurrencyByLedger` map in the web's store; the iOS side
  reads from `FinchStore.displayCurrency` and re-formats via
  `Money.formatted(in:)`)
- Fixture export script (`frontend/scripts/export-fixtures.ts`)
  writes `selectors.json` to `ios/FinchCore/Tests/Fixtures/`;
  CI runs it before `FinchCore` tests
- `ParityTests` extended with one golden test per ported selector
  (input + expected output, Swift assertion to the cent)

**Non-goals (out)**:

- Write paths (still Phase 2)
- Holdings, accounts with positions/price-updates UI (read-only display
  is in Phase 1.0's Accounts tab; full holdings CRUD is Phase 2)
- Saved searches (Phase 4)
- Per-account forecast tab (Phase 4)

**Dependencies**: Phase 1.0 complete (the `Tx` projection + `Project`
module + the in-memory `Tx[]` cache are the foundation for selectors)

**Acceptance criteria**:

- Every ported selector has a JSON-golden parity test
- The Insights tab renders with real data from an imported `.finch`
  (sample fixture) and from a live-imported pack
- Display-currency switching in Settings re-formats the Insights tab
  in real time
- The iPhone simulator app's 5 tabs cover: Accounts, Activity, Budgets,
  Insights, Settings

**Open questions**:

- Does `monthForecast` (linear regression over historical data) need
  to port the same training-set window as the web, or can we use a
  simpler heuristic for v1?
- How does `weeklyDigest` handle weeks that span the active-ledger
  boundary (e.g., a Sunday `anchor` that lands in the prior ledger
  for a transfer)?

---

## Phase 2 — Entry + core CRUD + write chokepoint

**Goal**: Make the app "usable for real" — add transactions, edit them,
confirm pending, manage budgets, post-now on scheduled items, full
ledger CRUD. All writes flow through the Swift port of the web's
`postEntry` / `rebuildEntry` / `deleteEntry` chokepoint.

**Scope (in)**:

- `Store` module in FinchCore: the write chokepoint, ported from
  `lib/db/core/entries.ts` (823 lines)
- The 14 per-domain `mutations.ts` files in `ios/FinchCore/Sources/FinchCore/Store/Domain/<x>/`,
  each ported from the corresponding `frontend/lib/db/domain/<x>/mutations.ts`
  file (74 actions total)
- 6 new iOS screens: Add Transaction (the long form), Edit
  Transaction, Transaction Detail edits, Pending confirm flow, Budget
  CRUD, Scheduled CRUD, Ledger CRUD (form sheets)
- The two `rebuildEntry` adapter preconditions from
  `lib/db/core/entries.ts` (forward `cleared_at`; pass explicit
  `amountBase` for pinned rates) — apply verbatim
- The `lib/db/core/sealed-entry.ts` per-entry sealed-write helper
- Write-side parity: the Swift chokepoint produces the same final
  `Tx[]` as the web chokepoint for the same Args input (parity
  fixtures = the same ones the web's `lib/db/_args.test.ts` smoke
  tests use)

**Non-goals (out)**:

- iPad / macOS adaptive layout (Phase 3)
- Reconcile, rules engine, transfers CRUD, merchants / categories /
  tags admin (Phase 4)
- Auto-pack debounce + iCloud folder-watcher (Phase 5)
- App Intents / Siri / Share Extension receipts / Spotlight /
  notifications / biometric lock (Phase 6)
- Widgets / Watch / Live Activities (Phase 7)
- Row-level sync (Phase 8, may never ship)

**Dependencies**: Phase 1.5 complete (the `Tx` projection + all
selectors are read by the iOS UI; the write chokepoint must produce
data the existing read surface can render)

**Acceptance criteria**:

- The 74 actions in the central `_args.ts` registry all resolve to a
  Swift handler in the per-domain `mutations.ts` ports (tsc-level
  smoke test, same as the web's `lib/db/domain/_args.test.ts`)
- A "Add Transaction" tap → form fill → save round-trips correctly:
  the new entry appears in the Activity tab, the account balance
  updates, the audit gate (on next import) reports clean
- The `?debug=1` "Force import" UI (from Phase 1.0) is preserved for
  parity-test fixtures that intentionally violate the audit gate
- Per-domain mutations parity: every ported mutation produces the same
  `Tx[]` delta as the web's `lib/db/domain/<x>/mutations.ts` for the
  same Args

**Open questions**:

- Should the iOS write path be optimistically local (write to the
  local DB, then export a `.finch` for the web) or always-`.finch`
  (write only via import/export)? The plan's §4.3 implies "always-
  pack," but the Phase 1.0 import UX is "open one pack, work
  locally"; the right answer depends on what feels native.
- The 14 per-domain files have 5 known cross-domain deps (per
  `frontend/AGENTS.md`: `accounts → accountGroups`, `transactions →
  attachments`, `budgets → budgetGroups`, `rules → counterparties`,
  `scheduled → counterparties`). The plan is to expose them via
  per-domain `_deps.ts` shims — but the shims aren't created yet on
  the web side. Do we create the shims first on the web, or in
  parallel on iOS?
- Write-side parity fixtures are much larger than read-side ones
  (every Args shape × every state). How do we keep the fixture
  count manageable without losing coverage?

---

## Phase 3 — Adaptive iPad / macOS

**Goal**: The same code base serves iPhone, iPad, and Mac via
SwiftUI's adaptive containers. Both distribution paths set up
(Mac App Store + notarised direct download).

**Scope (in)**:

- `NavigationSplitView` replaces `NavigationStack` on iPad / Mac
- macOS-specific chrome: menu bar, keyboard shortcuts, ⌘K command
  palette, window management
- Multi-window support on iPad (one window per ledger? per drill-down?)
- Mac App Store + notarised direct download targets (Xcode
  distribution: two targets, one codebase, per the plan's §4.8)
- Universal binary (Apple Silicon only — macOS 26 dropped Intel
  support; macOS 26+ is the only supported target per the plan's
  §4.7)
- Sandbox + entitlements review (Mac App Store requires more
  restrictive sandboxing than direct download)

**Non-goals (out)**:

- Catalyst (only as a fallback per the plan's §4.1)
- iOS → Mac sharing (the app is iPhone / iPad / Mac; iPhone-only
  is Phase 1.0; iPad + Mac is Phase 3)
- iCloud Drive sync (still Phase 5)
- Widgets (still Phase 7)

**Dependencies**: Phase 2 complete (the app has real write paths;
adaptive layout is most useful when there's stuff to write)

**Acceptance criteria**:

- The same binary runs on iPhone 15 sim, iPad 11" sim, and
  Mac (Apple Silicon) with the same feature set
- ⌘K on Mac opens the command palette and navigates to any tab /
  detail / action
- Mac App Store submission passes review (sandbox, entitlements,
  no private APIs)
- Notarised direct download runs without Gatekeeper warnings
  (notarisation ticket stapled; hardened runtime enabled)

**Open questions**:

- Does the iPhone-only iOS deployment target need to bump from
  iOS 26+ to iOS 26+ + iPadOS 26+ + macOS 26+ as separate
  targets, or does the single SwiftPM target cover all three?
- What's the right granularity for multi-window on iPad? One
  window per ledger, or one window per (ledger, drill-down)?

---

## Phase 4 — Power features

**Goal**: Add the heavy-duty write surfaces: reconcile, rules engine
+ builder + backfill, transfers CRUD, merchants / categories / tags
admin, saved searches, bulk recategorize, FX / base tools.

**Scope (in)**:

- Reconcile module: cleared-balance selector (already ported as
  part of the projection), reconcile UI, statement import (CSV)
- Rules engine port (`lib/rules/{engine,types,describe}.ts` → Swift):
  condition/action model, evaluator, rule builder UI, backfill
  (apply a rule to historical entries)
- Transfers UI: explicit transfer CRUD (currently the projection
  already pairs transfer legs as separate `Tx` rows with the same
  `transferGroupId`; this phase adds the creation/edit UI for
  transfers specifically)
- Merchants / categories / tags admin: full CRUD on the reference
  data (rename, merge, archive, color)
- Saved searches: persist a search query + filters as a named
  shortcut
- Bulk recategorize: multi-select entries + apply category
- FX / base tools: per-account base-currency override, historical
  rate editor, currency rename

**Non-goals (out)**:

- Bank/feed import (out of scope per the plan's §7 boundary)
- Auto-pack debounce + iCloud folder-watcher (Phase 5)
- App Intents / Siri / Share Extension receipts / Spotlight /
  notifications / biometric lock (Phase 6)
- Widgets / Watch / Live Activities (Phase 7)

**Dependencies**: Phase 2 complete (write chokepoint is the
foundation; the rules engine + reconcile use the chokepoint
internally)

**Acceptance criteria**:

- Reconcile a real account: cleared sum matches the bank
  statement, the un-cleared entries are listed, an adjustment
  posts if the gap exceeds the tolerance
- Create a rule: "if merchant matches 'Starbucks', set category
  to 'Coffee'" — apply backfill to the last 90 days; the affected
  entries' categories update
- Bulk recategorize 50 entries to a new category in one tap;
  audit gate stays clean
- Saved searches persist across app launches (lives in the
  `app_state` table on the local DB)

**Open questions**:

- Rules engine backfill can be slow on large datasets. Do we
  run it on a background queue with progress UI, or block the
  main thread for small datasets and require explicit "Backfill
  in background" for large ones?
- Statement import (CSV): the web has no statement import. Is
  this net-new on iOS, or do we ship a web parity feature too?

---

## Phase 5 — Pack engine + iCloud Drive sync

**Goal**: Implement the `.finch` pack format end-to-end on the
native side: build, validate, atomic swap, **debounced auto-pack**,
manual "Sync now," **conflict-copy UX**. The web-side work is
already shipped (PRs #106, #107, #109); iOS matches.

**Scope (in)**:

- Auto-pack debounce: after any write, wait ~30 s of idle, then
  pack the local DB into a `.finch` and write it to the iCloud
  `Documents/finch/` folder
- Manual "Sync now" UI: a button in Settings that forces an
  immediate pack (no debounce)
- iCloud folder-watcher: when iCloud surfaces a new `.finch` in
  the folder (from another device), auto-import it through the
  Phase 1.0 pipeline
- Conflict-copy UX: when iCloud keeps a conflict copy (both
  devices wrote offline), present an "open both, compare counts,
  pick one" sheet
- Orphan attachment sweep: when the pack is built, sweep orphaned
  attachment files off disk (the on-disk files ↔ DB rows invariant
  from `DOUBLE_ENTRY_PLAN §4.6`)

**Non-goals (out)**:

- Row-level sync (Phase 8, may never ship; the pack model is the
  answer for the foreseeable future)
- The pack **format** is already implemented (Phase 1.0 ported
  `lib/db/core/pack.ts`); this phase adds the **delivery layer**
  (auto-pack debounce + folder-watcher + conflict UX), not a
  new pack engine
- Multi-device collaborative editing (still Phase 8)

**Dependencies**: Phase 4 complete (auto-pack debounce fires on
every write; Phase 4 is the first phase that produces user-driven
writes; Phase 2's chokepoint alone isn't enough to justify the
debounce complexity)

**Acceptance criteria**:

- Edit a transaction on iPhone → wait 30 s → check Files app →
  the `Documents/finch/` folder has a fresh `.finch` with the
  edit
- Edit a transaction on iPhone → "Sync now" → the new pack
  appears in iCloud within 5 s
- iPad (Phase 3) imports the new pack via the folder-watcher
  within 10 s of iCloud replication
- Offline edit on iPhone → iPad offline edit → both come
  online → iCloud surfaces a conflict copy → user picks one
  via the "open both" sheet

**Open questions**:

- The "open both, compare counts, pick one" UX is sketched in
  the plan's §14.1 but not detailed. How do we present the
  diff (per-account balances, per-category spend, total
  transaction count)?
- What's the right retention policy for old packs in the
  iCloud folder? The web's `.finch.bak` policy is user-
  configurable (frequency + retention in `app_state`); do we
  mirror that on iOS?
- Does the auto-pack debounce need to be paused while a write
  is in progress, or can writes + debounce coexist?

---

## Phase 6 — Native upside (part 1): Spotlight / Notifications / Biometric / App Intents / Share Extension

> **Phase 6 is decomposed into 5 sub-specs** (one per Apple
> platform framework). Each sub-spec is a full design
> (~500-700 lines); the 5 are independent and ship in any
> order. The natural implementation order is
> **6.1 → 6.2 → 6.3 → 6.4 → 6.5** (simplest to hardest).

**Goal**: Land the platform-native features that make a wrapper
insufficient. The data layer is the same as Phase 5; this phase
is mostly integration work.

**The 5 sub-features** (each has its own full design spec):

| # | Sub-feature | Spec | Apple framework | Estimated scope |
|---|---|---|---|---|
| 6.1 | **Spotlight indexing** | `plans/IOS_MACOS_PHASE_6_1_DESIGN.md` | `CoreSpotlight` | ~700 lines spec; 1-2 weeks |
| 6.2 | **Notifications** | `plans/IOS_MACOS_PHASE_6_2_DESIGN.md` | `UNUserNotificationCenter` | ~800 lines spec; 2-3 weeks |
| 6.3 | **Biometric lock** | `plans/IOS_MACOS_PHASE_6_3_DESIGN.md` | `LocalAuthentication` | ~600 lines spec; 1-2 weeks |
| 6.4 | **App Intents / Siri** | `plans/IOS_MACOS_PHASE_6_4_DESIGN.md` | `AppIntents` | ~800 lines spec; 2-3 weeks |
| 6.5 | **Share Extension receipts** | `plans/IOS_MACOS_PHASE_6_5_DESIGN.md` | Share Extension target | ~900 lines spec; 3-4 weeks |

Each sub-spec is independently reviewable. The 5 share
infrastructure (the App Group container, the
`DeepLinkRouter` for Spotlight + notification deep-links,
the `BiometricGate` for sensitive actions, the Xcode
project setup) but ship independently. **Total Phase 6
scope**: ~3,800 lines spec; ~2,200 lines Swift + ~1,000
lines SwiftUI; **2-3 months of full-time work** for a
small team (less than the original 3-4 month estimate
because the per-framework decomposition makes each
sub-feature smaller than the combined "Phase 6" estimate).

**Non-goals (out)** — applied to all 5 sub-features:

- Widgets / Live Activities / Watch (Phase 7)
- Row-level sync (Phase 8, may never ship)
- Bank/feed import (out of scope per the plan's §7 boundary)
- Per-ledger display-currency override UI (Phase 1.5)
- In-app theme override (Phase 1.5)
- iCloud folder-watcher (Phase 5)

**Dependencies**: Phase 5 complete (the chokepoint + pack
engine are stable; the intents can dispatch into them; the
Share Extension can write into the same `attachments/`
layout; the widgets + Watch can read from the App Group
container). **Plus**: App Group entitlements must be
enabled at the Xcode project level (a one-time setup,
not a per-feature concern).

**Acceptance criteria** (high level — each sub-spec
details the specifics):

- "Hey Siri, add a $6 coffee to Personal in finch" → the entry
  appears in the Activity tab within 5 s (Phase 6.4)
- Share a photo from Photos → choose finch → the photo is
  attached to the most recent transaction (or the user picks
  which entry) (Phase 6.5)
- Spotlight search for "starbucks" surfaces the matching entries
  as a top hit, deep-linking into the Transaction Detail screen
  (Phase 6.1)
- Local notification fires when a scheduled item is due, when
  a budget hits its `warning_pct`, when an anomaly is flagged,
  and on Sunday morning for the weekly digest (Phase 6.2)
- App launch on a fresh device requires Face ID (per the user's
  chosen policy); export still works after Face ID auth; the
  data is `completeUnlessOpen` at rest (per the plan's §10)
  (Phase 6.3)

**Why the decomposition**:

- Each sub-feature maps to a distinct Apple platform
  framework (CoreSpotlight, UNUserNotificationCenter,
  LocalAuthentication, AppIntents, Share Extension). The
  frameworks are independent; the Xcode project setup
  is per-framework.
- Each sub-feature has its own design surface with
  Apple-platform-specific UX patterns (Spotlight's
  CSSearchableIndex, Notifications' UNUserNotificationCenter,
  biometric's LAContext, App Intents' AppEntity + IntentDialog,
  Share Extension's NSExtensionContext). Each deserves its
  own design pass.
- The 5 sub-features can ship in any order; no spec
  depends on another. The natural implementation order
  (6.1 → 6.2 → 6.3 → 6.4 → 6.5) goes from simplest to
  hardest, but any subset can ship first.

**Cross-cutting infrastructure** (shared across the 5):

- **App Group container** (added at Phase 5's Xcode
  setup): `group.com.juchengquan.finch`. Phase 6.5
  (Share Extension) and Phase 7 (widgets + Watch) all
  read/write the App Group; the iOS app is the
  coordinator.
- **`DeepLinkRouter`** (introduced in Phase 6.1): handles
  Spotlight + notification deep-links. Phases 6.2,
  6.4 reuse the router.
- **`BiometricGate`** (introduced in Phase 6.3): gates
  sensitive actions. Phases 6.4, 6.5 use the gate
  (Phase 6.5 for the Share Extension's "Save"
  action; Phase 6.4 doesn't use it since Siri is
  already biometric-authenticated by the device).

---

## Phase 7 — Native upside (part 2): Widgets / Live Activities / Watch

**Goal**: The pure-UI on top of an already-mature data layer. The
plan's §14 deferred widgets from Phase 6 for the v1 native surface
focus; this phase is when they land.

**Scope (in)**:

- **Widgets** (WidgetKit): net-worth sparkline, this-month
  budget ring, month-forecast tile, weekly digest tile — all
  read-only views on top of existing selectors (the Phase 1.5
  selectors are the data source)
- **Live Activities / Lock Screen**: the same widget data, on
  the lock screen, updated when the underlying data changes
- **Apple Watch** (MAY, later in this phase): glance net worth
  / budget rings; quick-add a recent expense
- App Group entitlements + the shared `FinchCore` package needs
  to be importable from the widget extension target

**Non-goals (out)**:

- Row-level sync (Phase 8, may never ship)
- Watch-side writes beyond "quick-add a recent expense"
- Watch-side settings (the iPhone app is the source of truth for
  preferences; Watch is read + a single write action)

**Dependencies**: Phase 6 complete (the App Group entitlements
+ container model are in place; widgets extend the same data
path)

**Acceptance criteria**:

- Adding the net-worth widget shows the current net worth on
  the home screen, refreshed on a budgeted timeline
- The budget ring widget turns red when a budget is over 90%
- The month-forecast widget updates daily
- The weekly digest widget fires on Sunday morning
- A Live Activity surfaces on the lock screen when a
  scheduled item is due
- The Watch app shows net worth + budget rings; tapping a
  recent expense opens the iPhone app at the Transaction
  Detail

**Open questions**:

- Widget refresh budgets: WidgetKit enforces a system-wide
  refresh budget. How do we balance "always fresh" vs.
  "respect the budget"? (Probably: refresh on push from the
  chokepoint, with a system-driven fallback.)
- Watch is "MAY" in the plan. If Watch turns out to be a
  significant effort, we may want to ship widgets + Live
  Activities first, defer Watch to a follow-up phase.

---

## Phase 8 — Row-level sync (the full §4.3-C, if ever pursued)

**Goal**: CloudKit or server sync atop the UUID-ready, single-
chokepoint mutation layer. **Not on the current roadmap**; the
pack model in Phase 5 is the answer for the foreseeable future.

**Scope (in)** — speculative, deferred:

- CloudKit private database, one per ledger, schema mirrors the
  shared SQLite schema
- Per-row change tracking: each posting, entry, account, etc.
  has a `revision_id` and `last_modified_at`
- The chokepoint publishes a `Mutation` event on every write;
  the sync layer subscribes, batches, and pushes to CloudKit
- Other devices subscribe to CloudKit subscriptions; the sync
  layer pulls deltas, dispatches them through the chokepoint
  (it's idempotent on `(entry_id, revision_id)`)
- Conflict resolution: last-writer-wins on `(row_id,
  revision_id)` with the chokepoint's audit gate as the safety
  net

**Non-goals (out)**:

- This phase is **explicitly deferred** per the plan's §13
  ("if ever pursued"). It conflicts with the local-first
  promise of the app; the pack model is the answer unless a
  real product need arises.

**Dependencies**: All of Phases 1-7 complete; the chokepoint +
audit gate + pack engine are the foundation

**Acceptance criteria** (if pursued):

- A change on iPhone appears on iPad within 5 s
- A change on iPad while iPhone is offline syncs within 5 s of
  iPhone coming online
- The audit gate refuses any sync-delivered mutation that
  would create a corruption; the user is shown the typed
  problem set

**Open questions**:

- CloudKit vs. a custom server: CloudKit is "free" but limits
  schema flexibility; a custom server is more work but
  matches the pack model. Probably CloudKit for v1 if ever
  pursued.
- Multi-user: does the app support per-user ledgers, or is
  one iCloud account = one finch install? The current answer
  is "one iCloud account = one install."

---

## Cross-phase dependencies (visual)

```
                ┌─────────── Phase 3 (iPad / Mac) ───────────┐
                │                                            │
Phase 1.0 ──▶ Phase 1.5 ──▶ Phase 2 ──▶  Phase 4 (power)     ──▶ Phase 5 (iCloud) ──▶ Phase 6 (intents) ──▶ Phase 7 (widgets) ──▶ Phase 8
(read-only      (Insights     (write         │                                            │
iPhone)          + selectors)   chokepoint)  └────────────────────────────────────────────┘
```

Phases 3 and 4 are **parallelizable** after Phase 2 — both depend on
the write chokepoint but neither depends on the other. Phases 6 and
7 depend on Phase 5 (the iCloud container + entitlements are in
place). Phase 8 depends on everything.

**The critical path** is 1.0 → 1.5 → 2 → 5 → 6 → 7. Phases 3 and 4
are parallelizable between Phase 2 and Phase 5; the team MAY re-order
them, but SHOULD keep the critical path intact.

---

## Out-of-band items (not in the 8 phases above)

These are tracked separately from the 8-phase roadmap because
they're either maintenance / hygiene work, or open questions that
need a separate design pass:

- **CI cadence + flake triage**: the macos job's flake rate,
  fixture export script's maintenance, the .db round-trip
  fixture staleness — all live in
  `frontend/.github/workflows/ci.yml` + a new
  `ios/.github/workflows/ios-ci.yml` (added in Phase 1.0)
- **`.finch` UTI polish**: per-platform Quick Look generator,
  document picker icon — Phase 1.5 polish, not blocking
- **iCloud folder naming**: the user-visible "finch/" subfolder
  name — Phase 1.5 polish
- **Day-1 locales**: the web ships `en + zh-CN`; the iOS side
  uses `Localizable.strings` and can ship more locales from
  day 1 (a product call, not a technical one)
- **Documentation**: the iOS app's in-app help, the developer
  onboarding for `FinchCore`, the API docs for the
  `Swift` package — separate work
- **Telemetry / analytics**: out of scope per the plan's §10
  ("no data collected" privacy label). If the product team
  ever wants opt-in local analytics, that's a separate
  design pass
