# Settings as a native push (iOS Accounts/shell)

**Date:** 2026-06-22
**Status:** Design approved, pending implementation
**Scope:** iOS compact (iPhone) shell + the 5 primary tab toolbars. iPad/Mac unchanged.

## Problem

Settings is currently reached (prototype, #244) from a **top-left gear** on every
compact tab that presents `SettingsTab` as a **bottom sheet** (with an ✕). The
preference is a **native push from a top-right gear**: tap → Settings slides in
from the right with a standard ‹ Back (and left-edge swipe-back), like navigating
into any iOS detail screen.

Settings content is **unchanged** (no profile/identity header — the new Ledger
home tab already shows ledger name, switcher, net worth, "this month", and Manage
ledgers, so a profile header would duplicate it).

## Goal

- A **top-right gear** on each compact primary tab (Ledger, Accounts, Budgets,
  Scheduled, Insights).
- Tapping it **pushes** `SettingsTab` onto the current tab's `NavigationStack`
  (native slide + ‹ Back). No sheet, no ✕.
- The programmatic `.settings` target (deep link / ⌘K / App Intent / Mac menu)
  pushes the same screen on the active tab.
- iPad/Mac keep Settings as a sidebar destination (no change).

## Design

### Single trigger, native push

Keep the existing `router.showSettings: Bool` as the **one trigger** for both the
gear tap and the programmatic `.settings` route. Replace the shell sheet with a
per-tab navigation push driven by that bool.

- **`SettingsBarButton`** (compact-only) — unchanged action (`router.showSettings = true`),
  icon stays `gearshape`. Its placement at the 5 call sites changes from
  `.topBarLeading` to **`.topBarTrailing`**.
- **Each compact primary tab's root `NavigationStack`** gains a shared modifier
  (`.settingsPush()`) that adds:
  ```swift
  .navigationDestination(isPresented: <settings binding>) { SettingsTab().navigationTitle("Settings") }
  ```
  Applied inside the tab's own `NavigationStack` (LedgerTab, AccountsTab,
  BudgetsTab, ScheduledTab, InsightsTab). `.navigationTitle("Settings")` is set
  here because `SettingsTab`'s own title (inside `MoreTabNavigationStack`'s
  conditional) doesn't reliably surface through `navigationDestination` (same
  reason `MoreTabRoot` set it explicitly).
- **The settings binding** maps `router.showSettings` (and the `.settings` router
  target) to a Bool: `get { router.showSettings || router.selectedTab == .settings }`,
  `set` clears `router.showSettings` and, if the target was `.settings`, resets
  `router.selectedTab` back to the active primary tab — mirroring the current
  `settingsSheet` binding logic, just driving a push instead of a sheet.

### Remove the sheet

Delete the shell's `.sheet(isPresented: settingsSheet) { NavigationStack { SettingsTab() … ✕ } }`
and its ✕ toolbar item — the push supplies Back.

### Don't let it linger across tabs

Because the trigger is one shared bool and each tab's stack can honor it, reset
`router.showSettings = false` on bottom-bar tab change (in the existing
`.onChange(of: selected)`), so Settings can't stay pushed on a tab you switched
away from. Practically: open via gear → use → Back (or switch tabs, which closes
it).

### iPad / Mac

`SplitViewShell` / `MasterDetailShell` keep Settings as a sidebar destination
(`SettingsBarButton` is already compact-only, so it never appears there).

## Out of scope

- Settings content (no profile header; unchanged sections).
- The Ledger home tab and its header (#246/#247).
- Web; watchOS.

## Testing

- **Build:** `xcodebuild -scheme FinchApp` (+ `xcodegen generate`).
- **Existing unit suite** stays green (no logic removed; `CompactTabRouting`
  helpers reused).
- **Manual sim** (push UX can't be scripted): on each tab, tap the top-right gear
  → Settings slides in with ‹ Back; Back returns; switching tabs closes it;
  trigger `.settings` via an App Intent / deep link → Settings pushes on the
  active tab. iPad: Settings still reached via the sidebar.

## Notes
- Net change: flip `SettingsBarButton` placement to trailing, add a shared
  `.settingsPush()` modifier to the 5 tab stacks, swap the shell sheet for the
  bool-driven push, reset on tab change. Settings screen itself untouched.
