# iOS / macOS — UI build-out remediation plan (2026-06-14)

> Closes the gaps in `IOS_MACOS_UI_GAP_AUDIT.md`. Prioritized; Tier 1 first.

## Framing

- **The docs are no longer parity-only.** iOS/macOS may add features ahead of
  web; anything net-new should be flagged here for **back-port to `frontend/`**.
  Most items below, though, are wiring up engine actions the web already has.
- **Most Tier-1/2 work is pure UI over already-tested engine actions** —
  `Apply.swift` already dispatches all 75 actions byte-parity-verified. So these
  are mostly new SwiftUI screens calling `store.apply(...)`: **low engine risk,
  CI-buildable on the simulator** (no account/signing needed). Items that need a
  new engine action, a new chart primitive, a device, or a paid account are
  flagged ⚙️/📈/📱/💳.
- **Verification:** new screens should ship with the same patterns we already
  use — engine actions are covered by `FinchCore` tests; add `ActionCoverage`-style
  tests for any new action, and extend the write-parity oracle when a new action
  path is exercised. UI builds verified by `xcodebuild build/test` (sim).

---

## Tier 1 — make the app usable (blocking)

These are the "a user literally cannot do this" gaps. Do this tier before
anything else; without it the app isn't a usable finance app.

1. **Account CRUD + groups.** Add screens: Add/Edit Account sheet (name, type,
   currency, group, opening balance, color), archive/unarchive + delete with
   confirm; Account-group create/rename/reorder/delete. Wire `createAccount` /
   `updateAccount` / `archiveAccount` / `unarchiveAccount` / `deleteAccount` /
   `*AccountGroup`. Entry points: a `+` in `AccountsTab` toolbar + row
   swipe/context actions. *(All actions exist + tested.)*
2. **Account detail screen** (foundational — Tier 2 drill-in depends on it).
   Tap an account → balance + sparkline, its transactions (filtered), holdings,
   per-account reconcile, edit/archive. Make `AccountsTab` rows `NavigationLink`s.
3. **Budget edit + contribute + cycle + groups.** Edit sheet (`updateBudget`),
   a "Contribute" action for income/goal budgets (`contributeBudget`), cycle
   controls (`updateBudgetCycle` / `clearPendingAmount`), budget-group CRUD.
   Make `BudgetsTab` rows tappable → Budget detail (progress ring + matched
   transactions for the cycle).
4. **Display-currency picker.** Replace the read-only `LabeledContent` in
   Settings › Ledger with a picker calling `setDisplayCurrency`; make
   `FinchStore.displayCurrency` read the store value (it currently `return
   baseCurrency`) — see `displayCurrencyByLedger` (the web's per-ledger model).
   ⚙️ small store change, no new engine action.
5. **Transaction splits + tags in Edit.** Add a splits editor (`setTransactionSplits`)
   and a tag picker (`setTransactionTags`) to `EditTransactionSheet`.
6. **Counterparty / merchant admin screen.** List + search + rename + delete +
   verify/unverify (`*Counterparty`); reachable from Settings or the Ledger
   group. Wire `confirmPendingWithMerchant` into the pending flow.
7. **Scheduled edit (+ splits).** Edit sheet (`updateScheduled`) and split
   editing (`addScheduledSplit` / `removeScheduledSplit` / `updateScheduledSplit`);
   make `ScheduledTab` rows tappable.
8. **Surface quick-action failures.** The swipe/menu/toggle quick actions use
   `try?` and silently no-op on rejection (`ScheduledTab`, `BudgetsTab`,
   `ActivityTab`, `RulesManagerView`). Route them through a shared error toast
   (reuse `i18nMessage`).

---

## Tier 2 — drill-in + the "smart" features (high value, data already exists)

9. **Consume `focusedId`.** Make Spotlight/notification/deep-link taps actually
   reach the entity: each tab observes `router.focusedId` and scrolls-to /
   selects / opens the detail. (Unblocks the OS-integration last mile too.)
10. **Wire suggestCategory + findDuplicate into entry.** `AddTransactionSheet`:
    show the suggested category (`suggestCategory`) as a default/chip, and a
    soft "looks like a duplicate" nudge (`findDuplicate`) before save.
11. **Anomaly badge in Activity.** Flag rows with a high `anomalyScore` /
    `merchantStats` z-score (already computed for notifications).
12. **Forecast with scheduled.** Pass the real scheduled templates (not `[]`) to
    `monthForecast`; add the per-account `accountForecast` + low-balance trough
    to Account detail.
13. **Insights parity cards.** Add the missing cards using existing selectors:
    weekly-digest (`weeklyDigest`), category deltas (`topCategoryDeltas`),
    net-worth-by-type; the cashflow metric + 3M/6M/1Y range switcher. 📈 Two new
    chart primitives needed for the last two: **Sankey** (`incomeCategoryFlow`)
    and **CalendarHeatmap** (`dailySpending`).

---

## Tier 3 — OS-integration last mile (mostly small, high perceived quality)

14. **Widget freshness.** Call `WidgetSnapshotWriter.write` + `WidgetCenter.shared.reloadAllTimelines()` from `FinchStore.apply` (after each mutation), not only on backup.
15. **Spotlight on import/delete.** Call `SpotlightIndexer.clearAll()` + reindex in the pack-import path (`swapInAndProject`); `deindex` on row delete.
16. ✅/⏳ **Biometric coverage.** Done: the 5 data Siri/App Intents refuse when
    locked (`FinchIntentLock.unlocked`); the entity queries
    (`Account`/`Category`/`Ledger`) now also return `[]` while locked, so the
    Shortcuts/Siri parameter pickers can't enumerate names past the lock; the
    lock cover dismisses the global sheets so it always sits on top
    (`onChange(of: gate.isLocked)`). *(Deferred: lock-screen **widget**
    redaction — 📱 needs a device to verify.)*
17. **Notification-permission denial.** Detect `.denied` and surface a "notifications are off → Settings" hint instead of silently dropping every alert.

---

## Tier 4 — non-functional (cross-cutting; do alongside)

18. ✅ **Localization layer (done).** Added `Resources/Localizable.xcstrings`
    (en source + zh-Hans) driven by the Swift compiler's string extraction
    (`SWIFT_EMIT_LOC_STRINGS`), so all 325 `LocalizedStringKey` literals localize
    with **zero view-file edits**. Translations: 104 zipped from the web
    `messages/*.json`, 207 hand-authored (terminology kept consistent with web),
    14 intentional English fallbacks (numbers/separators/format-only/brand). All
    79 `I18nError` codes now mapped in `ErrorL10n` (the runtime-data path).
    Reproducible via `ios/scripts/{xliff-keys,build-xcstrings}.ts` +
    `zh-manual.json`. `CFBundleLocalizations`/`knownRegions` declare `zh-Hans`;
    both `FinchApp` and `FinchMac` build & emit `zh-Hans.lproj`. **Back-port
    note:** the hand-authored zh copy is net-new and could feed the web later.
    App Intents / Siri phrases are localized too (`AppShortcuts.xcstrings`).
    *(Deferred: only the marginal `InfoPlist` display strings — document-type
    name "finch data pack", extension bundle names — remain en-only.)*
19. **Locale decimal parsing.** Replace `Double(string)` with a `NumberFormatter`(locale-aware) for all 11 numeric fields; round-trip the prefill formatting to match.
20. **Chart accessibility.** Add `.accessibilityLabel/Value` (or `AXChartDescriptor`) to the five chart views; add a non-color cue to Sparkline trend + Donut slices (render the `label`).
21. ✅ **Projection cost (done).** `Projection.run` gained an optional `ledgerId`
    scope; `reprojectActiveLedger` now re-projects only the **active** ledger's
    transactions (every mutation targets the active ledger), not all ledgers'.
    `ledgerId == nil` still projects everything, so the parity oracle + FinchCore
    tests are unchanged (148 green). As a free bonus this fixed a parity bug:
    `ActivityTab` read `store.txns` unfiltered and so showed *all* ledgers'
    transactions; it now shows only the active ledger, matching the web
    (`activity/page.tsx` filters by ledger). `ActivityTab`'s `filtered`/
    `daySections` were computed every render (twice, per keystroke) — now memoized
    into `@State` recomputed only on `txns`/query/page-size changes via
    `onReceive`/`onChange`.
22. **Loading/sync state.** Add an `isHydrating`/`isSyncing` flag + spinners; stop swallowing iCloud import failures.

---

## macOS / iPad — make it more than "iPhone stretched" (after Tier 1–2 detail screens exist)

23. ✅ **Real detail pane (done)** — true three-column `NavigationSplitView`
    (sidebar │ list │ detail) on regular width for the two tabs that actually
    have a list→detail relationship: **Accounts** and **Budgets**. Selecting a
    row now shows its detail beside the list instead of replacing it. The
    dashboard / sheet-based tabs (**Insights, Settings, Activity, Scheduled**)
    deliberately keep two columns (sidebar │ full-width content) — Activity and
    Scheduled edit via sheets (no detail screen), and a dashboard squeezed into a
    narrow middle column would be worse. The **compact (iPhone) shell is
    untouched** — it still uses `AccountsTab`/`BudgetsTab` (NavigationStack +
    push), so there's no iPhone risk. New code: `Shell/MasterDetailShell.swift`
    (`SectionSidebar`, `ThreeColumnShell`, `AccountsListColumn`,
    `BudgetsListColumn`); `SplitViewShell` branches by tab. Per-tab selection
    persists across section switches and resets on a ledger switch.
24. ✅ **Menu bar + windowing (done)** — `SidebarCommands()` (sidebar toggle +
    View menu), ⌘, → Settings (focuses the Settings tab; finch keeps Settings
    in-app, not a separate Preferences window), `.defaultSize` / min content size
    / `.windowResizability`. (Per-screen action shortcuts beyond ⌘N/⌘K/⌘1-6/⌘,
    can be added incrementally.)
25. ✅/⏳ **Context menus + keyboard** — `.contextMenu` row actions now on every
    list (Activity added; Accounts/Budgets/Scheduled/groups already had them).
    Arrow-key list navigation + per-row shortcuts remain a follow-up (SwiftUI
    `List` focus management is non-trivial). The `.bottomBar` mapping on Mac is
    acceptable (PlatformCompat → `.automatic`).

---

## Suggested sequencing (PR slices)

1. **Account CRUD + Account detail** (Tier 1 #1–2) — unblocks usability + Tier-2 drill-in.
2. **Budget edit/contribute + Budget detail** (#3).
3. **Display currency + splits/tags + scheduled edit + counterparty admin** (#4–7) + quick-action error toast (#8).
4. **Drill-in/focusedId + smart features** (#9–12).
5. **Insights cards + 2 chart primitives** (#13).
6. **OS last-mile** (#14–17).
7. **Localization + decimal + a11y + perf + loading** (#18–22), can interleave.
8. **macOS/iPad polish** (#23–25).

Each slice is its own green-CI PR. Tiers 1–3 + most of 4 are sim-buildable and
unit-testable with no account/signing; only the biometric/device-feel checks
(#16) and any CloudKit work need provisioning.
