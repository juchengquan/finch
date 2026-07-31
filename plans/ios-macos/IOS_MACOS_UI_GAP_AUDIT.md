# iOS / macOS — UI capability gap audit (2026-06-14)

> ## ⚠️ HISTORICAL — a 2026-06-14 snapshot, not current state
>
> **The gap this audit found is closed.** The ~135 features listed in
> `IOS_MACOS_INDEX.md` §0 are what closed it, and web→iOS parity is complete; the
> app described below — "a read-mostly shell over a complete engine" — no longer
> exists. Do not read the findings as a to-do list.
>
> Kept for the reasoning, not the verdict: the *method* (five parallel surveys, each
> finding spot-checked against the code, the headline confirmed by three agents and
> re-verified by hand) is why it caught something ordinary review had missed for
> weeks, and the "why prior testing missed it" section below is the durable part.

> **Status: authoritative.** This supersedes any earlier "full functional
> parity" claim for the iOS/macOS port. Produced by a 5-agent feature audit
> (screen parity · macOS/iPad fitness · OS integrations · non-functional ·
> capability reachability), each finding spot-checked against the code. The
> headline finding was independently confirmed by three agents and re-verified
> by hand (grep: 0 UI callers for the core write actions below).

## The meta-finding

**The engine is complete and parity-tested; the UI exposes only a fraction of
it.** The double-entry chokepoint (75 actions), selectors, projections, pack
format, and the write-parity oracle are real and well-tested (129 green). But
many of those actions and selectors have **no screen that lets a user invoke or
see them**. The app is, today, a **read-mostly shell over a complete engine**.

**Why prior testing/review missed it:** parity tests and the #173–177 cleanup
operated at the *engine* level — they proved the actions/selectors compute
correctly byte-for-byte vs the web. None checked *UI reachability* — whether a
control actually dispatches the action. "Tests green / full parity" was true of
the brains and false of the hands.

## A note on the docs' new role (2026-06-14)

These docs are **no longer parity-only.** iOS/macOS may now add features ahead of
the web, which can later feed *back* into the web version. So this audit is not
just a "catch up to web" list — it is the native app's own roadmap. Gaps vs web
are tracked here; net-new native ideas are welcome and, when built, should be
noted for back-porting to `frontend/`.

## Capability matrix (per domain)

Legend: ✅ usable · ⚠️ partial · ⛔ engine-only (no UI) · — n/a

| Domain | Create | Edit | Delete | Detail view | Notes |
|---|---|---|---|---|---|
| **Accounts** | ⛔ | ⛔ | ⛔ | ⛔ | only the 1 seeded "Cash" account exists; `createAccount` is seed-only |
| Account groups | ⛔ | ⛔ | ⛔ | — | display-only grouping |
| **Transactions** | ✅ | ⚠️ | ✅ | ⛔ | edit lacks splits + tags; no detail screen |
| Transfers | ✅ | ⛔ | ⛔ | ⛔ | create only; no list/edit/delete UI |
| **Budgets** | ✅ | ⛔ | ✅ | ⛔ | no edit, no contribute (goals), no cycle, no groups |
| Counterparties | ⛔ | ⛔ | ⛔ | ⛔ | entire merchant/verify domain has no UI |
| Categories | ✅ | ✅ | ✅ | — | CategoryAdminView — OK |
| Tags | ✅ | ✅ | ✅ | — | TagAdminView OK; but can't tag a *transaction* |
| Rules | ✅ | ✅ | ✅ | — | RulesManagerView — OK |
| Scheduled | ✅ | ⛔ | ✅ | ⛔ | create/post/delete; no edit, no splits, no manual generate |
| Holdings | ✅ | ✅ | ✅ | — | HoldingsView — OK |
| Exchange rates | ✅ | — | ✅ | — | ExchangeRatesView — OK |
| Ledgers | ✅ | ⚠️ | ✅ | — | edit = name only (no color/tagline) |
| Display currency | ⛔ | ⛔ | — | — | `displayCurrency` returns base; `setDisplayCurrency` never called |
| Reconcile | ✅ | — | — | — | global sheet (not per-account) |

## Findings by tier

### Tier 1 — core actions a user literally cannot perform (verified 0 UI callers)
- **Account CRUD** (`createAccount`/`updateAccount`/`archiveAccount`/`unarchiveAccount`/`deleteAccount`) — stuck on the seeded Cash account. Single worst gap.
- **Account-group CRUD.**
- **Budget edit + contribute + cycle + groups** (`updateBudget`/`contributeBudget`/`updateBudgetCycle`/`clearPendingAmount` + budget-group actions).
- **Counterparty/merchant management** (`create/update/delete/verify/unverifyCounterparty`, `confirmPendingWithMerchant`).
- **Display-currency picker** (`setDisplayCurrency`) — a core money concept (CLAUDE.md) currently inert.
- **Transaction splits + tags** (`setTransactionSplits`/`setTransactionTags`).
- **Scheduled edit + splits** (`updateScheduled`/`addScheduledSplit`/…).

### Tier 2 — drill-in + "smart" features that exist but are invisible
- **No detail screens** (account, budget) — rows go nowhere. `DeepLinkRouter.focusedId` is set by the router and **read by zero views**, so every Spotlight/notification/deep-link tap just switches tab and drops the entity.
- **Intelligence computed but not surfaced:** `suggestCategory` + `findDuplicate` not wired into add/edit forms; `anomalyScore` only in notifications, never an in-app badge; forecast passes `[]` for scheduled (run-rate only).
- **Insights tab is a reduced subset** — Sankey (`incomeCategoryFlow`), calendar heatmap (`dailySpending`), weekly-digest card (`weeklyDigest`), category deltas (`topCategoryDeltas`), net-worth-by-type all have selectors but no UI consumer; the cashflow metric + 3M/6M/1Y range switcher are dropped. (Needs two new chart primitives: Sankey + CalendarHeatmap.)

### Tier 3 — OS integrations wired but with a broken last mile
- **Widget shows stale data** — `WidgetCenter.reloadAllTimelines()` is called nowhere; the snapshot is written only on backup, not on mutation.
- **Spotlight index goes stale on import/delete** — `deindex`/`clearAll` are dead code; importing a different pack leaves the index pointing at gone entities.
- **Deep links never reach detail** (the `focusedId` dead end, above).
- **Biometric leaks:** Siri/App Intents don't consult `BiometricGate`; an open sheet / the lock-screen widget can show figures past the lock.
- **Notification-permission denial** is unhandled (silently no-ops).

### Tier 4 — non-functional regressions vs web
- **No localization** — English-only; the web ships full `en` + `zh-CN`. 77 error codes + all UI strings untranslated; `i18nMessage` returns the English fallback only.
- **Locale decimal bug** — `.decimalPad` + `Double(string)` → comma-decimal-locale users cannot enter amounts/rates/shares in any of the 11 numeric fields.
- **Charts invisible to VoiceOver** + red/green-only meaning (Sparkline trend, Donut slices).
- **Full store re-projection on every mutation/keystroke** (O(all transactions)) — stalls at scale.
- **No loading/sync state** — empty data looks identical to "still loading / data lost"; iCloud import swallows failures.

### macOS / iPad — "the iPhone app stretched"
- **No real detail pane** — the `NavigationSplitView` sidebar hosts whole iPhone screens; no master/detail.
- **Menu bar nearly empty** — ⌘N/⌘K/⌘1-6 only; no View/sidebar-toggle, no Settings (⌘,) scene, no per-screen actions, no window sizing/multi-window.
- **Touch-only interaction** — swipe actions with almost no right-click context menus (only Scheduled), no keyboard list navigation; a `.bottomBar` action lands mislaid on Mac.

## What is genuinely solid (not gaps)
The engine + data layer: double-entry posting, FX, money editing, rollover, attachments, the 75-action chokepoint, selectors/projections, the pack format, and the byte-parity oracle. Categories/Tags/Rules/Holdings/ExchangeRates admin screens. The biometric idle timer + leg-metadata bugs were fixed in #173–177. The Watch glance is a real (read-only) glance.

## Remediation
Prioritized build-out plan: see `IOS_MACOS_UI_REMEDIATION_PLAN.md`.
