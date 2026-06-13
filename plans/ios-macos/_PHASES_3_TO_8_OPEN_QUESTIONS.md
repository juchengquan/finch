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
- ✅ **Bulk recategorize + in-place category edit.** *(Correction: was NOT
  actually blocked — the engine already ships a working `bulkRecategorize` action
  that rebuilds the category leg.)* Per the user decision to un-defer category
  editing: EditTransaction's category is now an editable picker (applies via
  `bulkRecategorize` on save), and Activity has a Select mode → multi-select →
  Recategorize sheet. `updateTransaction` still defers *amount* edits only.
  Tested (single + bulk).
- 🔧 **Saved searches + per-account base override + tag admin/merge + category
  color/icon.** Deferred (saved searches → UserDefaults; per-account base + merge
  have no chokepoint action yet).

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
- ⏳ **In-app attachment UI + attachment display/projection.** The share-in path
  works; an in-app EditTransaction "add receipt" PhotosPicker + an attachments
  projection on `Tx` (to show/remove existing receipts) are a refinement. The
  placeholder tx is created at amount 0 + status pending for the user to fill in.

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
- 🚧 **Apple Watch glance** (Phase 7) — code written (`_drafts/FinchWatch/`) but
  the **watchOS platform runtime isn't installed** in this build environment, so
  it can't be compiled/verified. Wiring instructions in the draft README.
- 📐 **CloudKit row-level sync** (Phase 8) — needs a real iCloud/CloudKit account
  + container at runtime to be meaningful; unverifiable in any CI. The
  entitlement compiles; the sync engine remains the architecture note. It also
  supersedes Phase 5's pack sync by design.
