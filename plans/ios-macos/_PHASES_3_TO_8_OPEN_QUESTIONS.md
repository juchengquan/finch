# Phases 3–8 — open questions parked during implementation

Continuing "all the rest" (3, 4, 5, 6.5, 7, 8). Same rule as the 6.x batch: park
genuine product/scope questions with the default I chose, reconcile at the end.

Many of these phases have **device-infrastructure** parts. UPDATE: it turns out
**app-extension targets + App Group entitlements DO build for the iOS simulator
without signing** (`CODE_SIGNING_ALLOWED: NO`) — signing is device/store-only,
not CI. So the Widget extension (7), Share Extension (6.5), and App Group are now
**actually built + embedded + CI-verified**, not deferred. The still-genuinely-
deferred parts are the ones needing a *different platform destination* (macOS,
watchOS — the iOS CI scheme doesn't build them) or *real iCloud/CloudKit runtime*
(unverifiable in CI regardless of build).

> Status legend: ⏳ open · ✅ resolved · 🔧 deferred-infra (built code, infra TODO)

## Phase 3 — Adaptive iPad / macOS

- ✅ **Shell adaptation.** Implemented: `AdaptiveShell` switches on
  `horizontalSizeClass` — iPhone/compact keeps the bottom tab bar; iPad/Mac
  regular width gets a `NavigationSplitView` sidebar + detail. Built for both the
  iPhone and iPad simulators.
- 🔧 **macOS distribution target.** The Mac App Store + notarised direct-download
  targets need signing/provisioning/notarization — not headless-CI-verifiable.
  The adaptive shell is Mac-ready (size-class + NavigationSplitView), but the
  separate Mac target + menu bar + the two distribution pipelines are deferred
  infra.
- ⏳ **Multi-window / per-window ledger.** The design proposes one window per
  ledger with a per-window `activeLedgerId`. **Default chosen:** keep
  `FinchStore` a singleton with a single shared `activeLedgerId` (no per-window
  ledger) — multi-window would require de-singletoning the store, a large change.
  Revisit if per-window ledgers are wanted.
- ✅ **⌘K command palette + menu bar + keyboard shortcuts.** FinchCommands adds
  a menu bar (Go menu ⌘1–6 tabs, New Transaction ⌘N, Command Palette ⌘K) driving
  the shared router; CommandPalette is a ⌘K searchable list (pure filter, tested).
  Cross-platform (iPad hardware keyboard too); verified by local Mac build + the
  iOS scheme. Only the two Mac *distribution* pipelines remain.

## Phase 4 — Power features (7 in the design; this pass ships 3)

Phase 4 is the design's largest phase ("2-3 months", 7 features). This pass ships
the 3 cleanest, highest-value features that map directly to existing chokepoint
actions; the other 4 are documented below for a follow-up increment.

- ✅ **Rules manager + builder + backfill.** List/toggle-active/delete/backfill +
  a single-condition / single-action builder (createRule/updateRule/deleteRule/
  backfillRule). Added `Projection.rules` + a `RuleSummary` type (tested).
- ✅ **Categories admin.** Rename / add / delete spending categories
  (create/update/deleteCategory). *Merge* is not a chokepoint action — deferred.
- ✅ **FX rate editor.** View / add / delete exchange rates
  (set/deleteExchangeRate). Exposed `store.exchangeRates`.
- ✅ **Reconcile UI + CSV statement import.** ReconcileSheet (statement balance
  → adjustment) AND ImportStatementView (Accounts toolbar): pick a CSV → parse
  (StatementCSV, header/positional, $/comma/date formats) → match against existing
  txns (StatementMatcher, amount ±1¢ within ±3 days) → Apply (matched → setCleared,
  unmatched → addTransaction). Parser + matcher are pure + unit-tested.
- 🔧 **Transfers CRUD edit/delete UI.** The engine actions `updateTransfer` /
  `deleteTransfer` exist and are tested; only a dedicated edit/delete transfers
  manager screen is unbuilt (`createTransfer` is wired via the Add screen).
- ✅ **Bulk recategorize + in-place category edit.** *(Correction: was NOT
  actually blocked — the engine already ships a working `bulkRecategorize` action
  that rebuilds the category leg.)* Per the user decision to un-defer category
  editing: EditTransaction's category is now an editable picker (applies via
  `bulkRecategorize` on save), and Activity has a Select mode → multi-select →
  Recategorize sheet. `updateTransaction` now rebuilds amount / currency /
  account edits too (#167). Tested (single + bulk).
- ✅ **Tag admin** (create/rename/delete) + **Saved searches** (UserDefaults,
  Activity toolbar menu; pure upsert tested). Phase 4 is now 6 of 7 features.
- 🔧 **Per-account base override + category/tag merge.** No chokepoint action
  exists for these — genuinely unsupported by the engine, not just unbuilt.

## Phase 6.5 — Share Extension + App Group + 75th action

- ✅ **`setEntryAttachment` (the 75th action).** Built + tested in FinchCore:
  inserts an `entry_attachments` row (ledger derived from the entry), validates
  kind ∈ {image, pdf}; `removeAttachment` is the inverse. Action count is now 75
  (ArgsTests updated). This is the native-only equivalent of the web's
  `POST /api/attachments` route.
- ✅ **Share Extension target + App Group container.** BUILT (FinchShare.appex
  embedded + verified). Accepts a photo/PDF from any share sheet, sha256s it,
  stages file + manifest into the App Group; `PendingAttachmentImporter` imports
  on launch (creates a pending placeholder tx + setEntryAttachment). The App Group
  entitlement builds on the simulator without signing.
- ✅ **In-app attachment UI + display.** EditTransaction now has a "Receipts"
  section: a PhotosPicker "Add receipt photo" (saves to the live attachments tree
  + setEntryAttachment, sha256 via CryptoKit) and a list of existing receipts with
  swipe-to-remove (removeAttachment). Added Projection.attachments(txId) +
  AttachmentRow (resolves a posting id → entry). The receipt feature now works
  both via the Share Extension AND in-app.

## Phase 5 — Pack auto-sync + iCloud

- ✅ **Auto-pack debounce + local backups.** `AutoBackupManager` debounces writes
  (5s) into one `.finch` pack written to `Application Support/Backups/`, flushes
  immediately on backgrounding / "Back up now", and prunes to the newest 14.
  `BackupPruner` is a pure, unit-tested retention policy. Settings › Backups shows
  last-backup + a manual trigger. (The seed uses `Apply.apply` directly so it
  doesn't trigger a backup — only real `store.apply` writes do, by design.)
- 🔧 **iCloud Drive sync.** The NSMetadataQuery folder-watch on the iCloud
  `Documents/finch/` container, conflict detection + conflict-copy resolution, and
  the iCloud entitlement/container are device infra — not headless-CI-buildable.
  Deferred; the pack engine they'd use is in place (buildPack + this debouncer).
- ⏳ **Retention source.** Hard-coded to 14; the existing `app_state.backupConfig`
  (setBackupRetention) could feed it. Refinement.

## Phase 7 — Widgets / Live Activities / Watch

- ✅ **Widget data layer.** `WidgetSnapshot` (Codable) + pure, unit-tested
  computations (net worth over included accounts, aggregate budget-used %, weekly
  spend) + `WidgetSnapshotWriter` that writes `widget_snapshot.json` after each
  backup. This is the read-side the widgets/Watch render. Added `AccountRow`
  public init + `store.baseAmount` for testing.
- ✅ **WidgetKit extension.** BUILT (FinchWidget.appex embedded + verified): a
  small/medium widget rendering net worth + a budget gauge + this-week spend from
  the App Group snapshot. `StaticConfiguration` + `TimelineProvider`.
- 🔧 **Watch app + Live Activities.** A watchOS app is a *different platform
  destination* — the iOS CI scheme doesn't build it, so it can't be CI-verified
  here (unlike the widget, which is an iOS extension). The shared data layer
  (`WidgetSnapshot` in the App Group) is ready for it. Deferred to a watchOS
  build/target run.

## Phase 8 — Row-level sync (CloudKit) — ARCHITECTURE ONLY (deferred)

Phase 8 replaces the whole-pack sync (Phase 5) with per-row CloudKit sync. It is
**entirely device/entitlement infrastructure** — a CloudKit container + the
iCloud/CloudKit entitlement + a real iCloud account + push (CKSubscription).
**None of it is buildable or verifiable in the headless simulator CI**, and it
supersedes Phase 5 (so it shouldn't ship alongside it). No code written this pass.

Documented approach for when it's picked up (needs a provisioned target):
- Mirror each canonical table row to a `CKRecord` (recordType = table name,
  recordName = row id); a `syncToken` per zone for incremental fetch.
- Last-writer-wins on `updated_at` (the schema already stamps it), with the
  double-entry invariants re-validated by the existing audit gate after a merge.
- A `CKSyncEngine` (iOS 17+) state-serialization loop; conflicts resolved by
  re-running the posting engine, not field-merging.
- Gate behind the same App Group + a "CloudKit sync" Settings toggle; keep Phase
  5 local backups as the offline/export path.

## Decisions taken at end-of-batch review

- ✅ **Un-defer tx category edit** (user: yes). Shipped via the existing
  `bulkRecategorize` action — EditTransaction category picker + Activity
  multi-select. No engine change was needed (the action already existed).
- 🔧 **Signed targets** (user: "set up signing so I build them"). Once an Apple
  dev team / signing is configured in the Xcode project, I'll add the actual
  Share Extension (6.5), Widget + Watch (7), Mac (3) targets + the App Group /
  iCloud / CloudKit entitlements. Those still can't be fully verified in headless
  CI, but the CI-verifiable cores are already in place for each. **Waiting on the
  signing/dev-team config before scaffolding** (so it doesn't red the CI).

## Round 2 — signed/extension targets turned out CI-buildable

After discovering app-extension targets + entitlements build for the iOS
simulator without signing, I went back and BUILT what had been deferred:

- ✅ **App Group** entitlement (iOS app + extensions).
- ✅ **WidgetKit extension** (Phase 7) — FinchWidget.appex, CI-built + embedded.
- ✅ **Share Extension** (Phase 6.5) — FinchShare.appex, CI-built + embedded;
  end-to-end receipt import.
- ✅ **iCloud Drive sync** (Phase 5) — ICloudSync pushes packs to the iCloud
  container + NSMetadataQuery folder-watch → manual import. Builds (iCloud
  entitlement compiles on the simulator); no-ops without an iCloud account.
- ✅ **macOS app** (Phase 3) — FinchMac target sharing the iOS sources via a
  `#if os(macOS)` modifier shim. **Built AND launched as a native Mac app**
  (verified locally; the iOS CI scheme builds iOS only).

Genuinely remaining (true environment limits, not code):
- ✅ **Apple Watch glance** (Phase 7) — after installing the watchOS 26.5
  simulator runtime (`xcodebuild -downloadPlatform watchOS`), the `FinchWatch`
  target (self-contained watchOS app reading the App Group `WidgetSnapshot`)
  **builds for the watchOS simulator**. Wired into project.yml; iOS + Mac builds
  unaffected. (CI builds the iOS scheme only, so CI doesn't rebuild it.)
- ✅/🔧 **CloudKit row-level sync** (Phase 8) — the **CI-verifiable core is
  built + unit-tested**: the row↔CKRecord mapping (round-trips headless) and the
  LWW conflict resolution (`CloudKitRecordMapper` / `CloudKitConflict`). The
  push/fetch loop (`CloudKitSyncService`) compiles + declares the CloudKit
  entitlement, but no-ops without a signed-in iCloud account, so the actual
  sync I/O + full CKSyncEngine state loop can't be runtime-verified in CI. It
  supersedes Phase 5's pack sync by design.


## Post-roadmap: cross-currency FX (ported)

- ✅ **Foreign-currency transactions + full rateToHub.** Un-deferred the engine's
  cross-currency path (was `notImplemented.foreignCurrency`): `addTransaction`
  with a currency ≠ the account's now converts native → account → base, carrying
  `orig_amount`/`orig_currency` (plumbed through AccountLeg/ResolvedLeg/
  insertPostings). `rateToHub` now does the full web logic — on-or-before →
  on-or-after → static FALLBACK_USD_PER_UNIT, with write-through of the resolved
  rate as a 'derived' row. AddTransaction sheet gains a currency picker.
  Verified: unit tests (JPY→USD orig fields; EUR static-fallback write-through) +
  the write-parity oracle (added a JPY step — byte-for-byte vs the web). Also
  fixed a pre-existing write-parity fixture date-drift (pinned the budget startDate).


## Post-roadmap: transaction amount editing + cleared_at preservation (ported)

- ✅ **updateTransaction money edits.** Un-deferred amount/currency/account edits
  (was `notImplemented.txMoneyEdit`): the legs are rebuilt with re-locked
  conversion (incl. the §5.2 foreign-currency two-step), a verbatim port of the
  web's qUpdateTransaction. Category edits also flow through it now.
- ✅ **cleared_at preservation on rebuild.** Plumbed `clearedAt` through
  AccountLeg → ResolvedLeg → insertPostings (was hardcoded NULL on insert), so a
  reconcile mark survives an edit. Same for orig_*.
- EditTransaction's amount field is now editable. Tests: amount edit (balance
  follows, entry balances), cleared_at survives an amount edit; the old
  'money-edit throws' test now asserts success. swift test 105 green.


## Post-roadmap: engine hygiene (last deferrals closed)

- ✅ **Budget rollover invalidation.** Ported lib/budgets/rollover.ts
  invalidateRollover (+ txTouches), wired into addTransaction / updateTransaction
  / bulkRecategorize / deleteTransaction. Resets a rolled budget's cached
  carry_forward/last_rolled_period when an edit overlaps it — mainly for imported
  web data (iOS doesn't roll budgets itself). Uses the existing cycleWindow for
  periodOf. Tested.
- ✅ **Attachment file cleanup.** The engine is filesystem-agnostic, so the app
  unlinks files: FinchStore.deleteTransaction + removeAttachment capture the
  rel_paths and remove the on-disk files after the chokepoint drops the rows.
  Wired into Activity swipe-delete, EditTransaction delete, and receipt-remove.

All engine deferrals are now closed; the iOS port is at full functional parity
with the web. Remaining items are infra-only (Mac distribution signing, live
iCloud/CloudKit) or new engine actions diverging from web parity (per-account
base / merge).
