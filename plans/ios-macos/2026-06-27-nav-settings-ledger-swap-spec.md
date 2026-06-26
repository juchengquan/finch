# Spec: swap Settings ↔ Ledger in the compact navigation

**Date:** 2026-06-27
**Status:** design approved, ready for implementation plan
**Scope:** iPhone (compact size class) navigation only. iPad/Mac (regular) sidebar is unchanged.

## Goal

On iPhone, make **Settings a primary bottom-bar tab** and reach the **two-layer Ledger from the top-left corner control** (where the Settings gear is today). The app launches on **Accounts**. This inverts the two screens' roles without adding new navigation machinery.

## Motivation

The Ledger tab is now a *manage/switch* surface (the two-layer `LedgerListView → LedgerDetailView`), an occasional action rather than a daily destination — so it no longer earns a primary bottom-bar slot. Settings, conversely, is easier to reach as a normal tab. The app already supports a "bar tab vs corner-pushed screen" split, so this is a symmetric swap of which screen plays which role.

## Current layout (baseline)

- **Compact bottom bar** (`AdaptiveShell.CompactShell`, `TabView`): `Ledger · Accounts · Budgets · Scheduled · Insights` (5 slots). Default selected = `.ledger`.
- **Settings**: reached via the **top-left gear** — `SettingsBarButton` (on every primary tab) sets `router.showSettings`, and the `settingsPush()` modifier pushes `SettingsTab` onto the current `NavigationStack`. Settings is *not* a bar tab on compact.
- **`CompactTabRouting`** (pure, unit-tested) bridges `DeepLinkRouter.selectedTab` (`AppTab`) ↔ the bar's `CompactTab`. `.settings` is the "overflow" screen (`overflowTab`); `.activity → .ledger` (the feed lives in the Ledger tab today).
- **`DeepLinkRouter`**: `@Published selectedTab` defaults to `.ledger`; `showSettings` flag drives the corner push.
- **Regular (iPad/Mac)** `SplitViewShell`: a sidebar that lists every tab including both Ledger and Settings. Unaffected by this change.

## Target layout

- **Compact bottom bar:** `Accounts · Budgets · Scheduled · Insights · Settings` (5 slots; Ledger removed, Settings added as the last slot using the gear icon). Default selected = `.accounts`.
- **Top-left corner control** (on every primary tab): a **Ledger** button (icon `books.vertical`) that pushes the two-layer Ledger (`LedgerListView → LedgerDetailView`) onto the current `NavigationStack`. Same screens as the old Ledger tab, re-homed behind the corner.
- **App launch:** lands on **Accounts**.
- **Regular (iPad/Mac):** unchanged — the sidebar keeps listing both Ledger and Settings.

## Detailed changes

### 1. `AdaptiveShell.swift`
- **Compact `TabView`:** remove the `.ledger` `tabItem`/`tag`; add a `.settings` `tabItem` rendering `SettingsTab()` with `Label(AppTab.settings.title, systemImage: AppTab.settings.icon)` and `tag(CompactTab.settings)`. Slot order: accounts, budgets, scheduled, insights, settings.
- **Default state:** `@State private var selected: CompactTab = .accounts`. The `onChange`/sync fallback already defaults to `.accounts` (`CompactTabRouting.appTab(for:) ?? .accounts`) — keep that.
- **Rename `SettingsBarButton` → `LedgerBarButton`:** compact-only (`sizeClass == .compact`), icon `books.vertical`, accessibility label `"Ledger"`, action `router.showLedger = true`.
- **Rename `SettingsPush`/`settingsPush()` → `LedgerPush`/`ledgerPush()`:** pushes the two-layer Ledger screen when `router.showLedger` is set. The pushed content is the Ledger list (the two-layer entry, `LedgerListView`) — see §5 for the LedgerTab/LedgerListView wiring so the push does not double-nest a `NavigationStack`.
- `SplitViewShell` and `MasterDetailShell`: no change.

### 2. `CompactTabRouting.swift` (pure — invert the mapping)
- `enum CompactTab`: `accounts, budgets, scheduled, insights, settings, more`. (`.settings` becomes a primary slot; `.more` remains the name for the corner-pushed overflow role, now carrying Ledger.)
- `compactTab(for:)`: `.settings → .settings`; `.accounts/.budgets/.scheduled/.insights →` themselves; `.ledger → .more` (corner-pushed); `.activity → .accounts` (feed lives in Accounts now).
- `appTab(for:)`: `.settings → .settings`; primaries → themselves; `.more → nil`.
- `overflowTab(for:)`: returns `.ledger` (instead of `.settings`).
- `sync(routerTab:currentPath:)` and `routerTab(forSelected:current:)`: unchanged in shape; they now operate over the inverted maps (Ledger is the overflow that preserves a deeper path; Settings is a normal slot).

### 3. `DeepLinkRouter.swift`
- Rename `showSettings` → `showLedger` (the corner-push flag).
- Default `selectedTab = .accounts` (was `.ledger`).
- Route handling: `.settings` → `selectedTab = .settings` (a real tab now, no push); `.ledger` → `showLedger = true` (corner push). `tx/counterparty → .activity`, `account → .accounts`, `category/budget → .budgets`, etc. unchanged. `finch://add` (showAddTransaction) unchanged.

### 4. The five primary tab files
`AccountsTab`, `BudgetsTab`, `ScheduledTab`, `InsightsTab`, **and `SettingsTab`** each get, in their toolbar: `ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }` and `.ledgerPush()` on the content. (Settings is now a primary tab, so it also shows the corner Ledger control — every primary tab can reach the Ledger.)

### 5. `LedgerTab.swift` / Ledger push target
- The Ledger screen is now reached only via the corner push, not as a tab. The pushed view must be the two-layer Ledger **list** content without nesting an extra `NavigationStack` inside the pushing tab's stack. Concretely: `ledgerPush()` pushes `LedgerListView()` (which already drives `navigationDestination(for: String.self) { LedgerDetailView(ledgerId:) }`); the old `LedgerTab`'s own `NavigationStack` wrapper and its `SettingsBarButton`/`settingsPush` toolbar are removed (the Ledger screen does not show a corner Ledger button — it *is* the Ledger).
- **Decision:** `ledgerPush()` pushes `LedgerListView()` directly and the `LedgerTab` `NavigationStack` wrapper is **retired** (its lean-overview header content, if still wanted, already lives inside `LedgerListView`/`LedgerDetailView`). `viewForTab(.ledger)` (used by the regular sidebar) renders `LedgerListView()` wrapped in its own `NavigationStack` as the sidebar's detail column — the regular layout keeps a Ledger entry, so it still needs a top-level container there.

### 6. Tests
- Update `CompactTabRouting` unit tests for the inverted mapping: `.settings` is now a primary slot (`appTab(.settings) == .settings`, `compactTab(.settings) == .settings`); `.ledger` is the overflow (`overflowTab(.ledger) == .ledger`, `compactTab(.ledger) == .more`); `.activity` maps to `.accounts`; `sync` preserves a deeper Ledger path; tapping the Settings slot returns `.settings` from `routerTab(forSelected:)`.
- Update any `AdaptiveShell`/`DeepLinkRouter` tests that assert the default tab (now `.accounts`) or the `showSettings` flag name (now `showLedger`).

## Behavior & edge cases

- **Deep links / routes:** `tx:`, `account:`, `category:`, `budget:`, `insights`, `scheduled` resolve to their bar tabs as before. `.ledger` opens the corner Ledger push; `.settings` selects the Settings tab. The global Edit-transaction sheet (`focusedTx`) is unaffected.
- **`-initialTab` (DEBUG):** still accepts `ledger`/`settings`/etc.; `ledger` triggers the corner push, `settings` selects the tab. No-arg launch lands on Accounts.
- **Accessibility:** corner control labeled `"Ledger"`; Settings tab uses its standard title.
- **macOS/iPad:** no behavioral change (sidebar already lists both).

## Non-goals

- No change to the two-layer Ledger screens themselves (`LedgerListView`/`LedgerDetailView`) beyond removing the now-redundant corner button on the pushed screen.
- No change to the regular (iPad/Mac) sidebar.
- No quick-switcher menu / active-ledger-name-in-bar (considered and declined; the corner pushes the full two-layer Ledger).
- No change to Settings' internal structure or the Settings sub-pages.

## Risks

- This is an actively-developed area (the two-layer Ledger just merged). Implement on a branch off the latest `feat/frontend`; the corner now re-homes that two-layer Ledger, so the two changes are complementary.
- Build **both** FinchApp (iOS) and FinchMac (macOS) — the corner toolbar uses `.topBarLeading` (already iOS-only-guarded via `sizeClass`); keep that guard intact.
