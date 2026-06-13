# Phases 3–8 — open questions parked during implementation

Continuing "all the rest" (3, 4, 5, 6.5, 7, 8). Same rule as the 6.x batch: park
genuine product/scope questions with the default I chose, reconcile at the end.

Many of these phases have **device-infrastructure** parts that cannot be built or
verified in the headless simulator CI (extra Xcode targets, App Group / iCloud /
CloudKit entitlements, notarization, real Watch/Widget hosts). For those I
implement the **CI-verifiable core** and document the deferred infra here rather
than risk a red build or claim false completion.

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
- ⏳ **⌘K command palette / full keyboard-shortcut set.** The full Mac ⌘K
  palette + menu commands are deferred with the Mac target.

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
- 🔧 **Reconcile UI.** `reconcileAccount` exists in the chokepoint; the
  statement-balance/CSV-import UI is not built yet. Deferred increment.
- 🔧 **Transfers CRUD edit/delete UI.** `createTransfer` is wired (Add screen);
  a dedicated edit/delete transfers manager is deferred.
- ⛔ **Bulk recategorize.** BLOCKED: the engine defers transaction *category*
  edits (`updateTransaction` throws `notImplemented.txMoneyEdit`), so bulk
  recategorize can't be built without first un-deferring that. Documented, not
  attempted.
- 🔧 **Saved searches + per-account base override + tag admin/merge + category
  color/icon.** Deferred (saved searches → UserDefaults; per-account base + merge
  have no chokepoint action yet).

## Phase 6.5 — Share Extension + App Group + 75th action

- ✅ **`setEntryAttachment` (the 75th action).** Built + tested in FinchCore:
  inserts an `entry_attachments` row (ledger derived from the entry), validates
  kind ∈ {image, pdf}; `removeAttachment` is the inverse. Action count is now 75
  (ArgsTests updated). This is the native-only equivalent of the web's
  `POST /api/attachments` route.
- 🔧 **Share Extension target + App Group container.** A separate Xcode app-
  extension target + the `group.com.juchengquan.finch` App Group entitlement +
  the cross-process pending-manifest handoff. NOT headless-CI-buildable (needs a
  new signed target + entitlement). Deferred infra — the 75th action it depends
  on is now in place.
- 🔧 **In-app attachment UI (PhotosPicker on a transaction) + attachment
  display/projection.** The action exists; the EditTransaction "add receipt"
  PhotosPicker + an attachments projection on `Tx` are deferred (also need a file
  store + sha256 helper). Buildable later without new targets.

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
