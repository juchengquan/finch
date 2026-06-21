# Compact "More" tab — replace the system TabView overflow

**Date:** 2026-06-21
**Status:** Design approved, pending implementation
**Scope:** iOS compact width (iPhone / Slide Over). iPad & Mac (regular width) unchanged.

## Problem

On iPhone the bottom `TabView` is built from all six `AppTab` cases
(`accounts, activity, budgets, insights, scheduled, settings`). SwiftUI collapses
everything past the 4th into a **system "More" tab**, which is its own UIKit
`UINavigationController`. The two overflow screens — Scheduled and Settings —
are then hosted inside that controller, which causes one of two bad outcomes:

- If the screen wraps itself in a `NavigationStack` (original code): a **doubled
  nav bar** — a stray "‹ More" back button stacked above the screen's own bar.
  (This was the original bug, reported as a "double return button".)
- If the screen drops its `NavigationStack` (the PR #210 fix): a **single** back
  button, but the screen's large **navigation title no longer renders** at the
  top — the system More controller doesn't surface the SwiftUI title until the
  list is scrolled.

Root cause: the **system "More" tab existing at all**. Any screen hosted in it
loses control of its navigation chrome. The fix must eliminate it.

## Goal

On iPhone, Scheduled and Settings must:
- show a **single** back button, and
- show their **navigation title**, and
- remain reachable from deep links / App Intents / notifications / ⌘K palette
  (which select `AppTab.scheduled` / `.settings` programmatically).

…with no change to the iPad/Mac sidebar shell.

## Approach (chosen)

A **custom "More" tab**: render exactly **5** items in the compact `TabView` so
iOS never creates the system overflow. The 5th item is our own `NavigationStack`
that lists Scheduled & Settings and pushes them. Because it is our stack, pushed
screens keep their titles and a single back button.

Alternatives considered and rejected:
- **Fully custom bottom tab bar** (replace `TabView` entirely): maximum control
  but re-implements selection, safe-area/keyboard handling, accessibility,
  scroll-to-top, badges — high risk for no extra benefit here.
- **Reduce to ≤5 tabs** (drop/merge a destination): simplest code but changes
  the app's information architecture — a product decision, not a bug fix.

## Design

### Unchanged

- **`AppTab`** keeps all six cases. It still drives the iPad/Mac sidebar
  (`SplitViewShell` / `SectionSidebar`), the ⌘K palette, App Intents
  (`OpenScreenIntent`), and notification routing (`tab: .scheduled`).
- **`MoreTabNavigationStack`** is kept as-is: compact → no inner stack (the
  screen now hosts inside the custom More `NavigationStack`); regular width →
  its own stack (the iPad detail column still needs one).
- **`SplitViewShell`** (regular width, iPad/Mac) — no change.

### `TabBarShell` (compact) — rewrite

Render five tabs:

1. Accounts, 2. Activity, 3. Budgets, 4. Insights — primary tabs, unchanged
   content via `tabContent(_:)`.
5. **More** — a `NavigationStack(path:)` whose root is a `List` of two
   `NavigationLink`s → Scheduled, Settings. Title "More".

TabView selection uses a local enum, because the More tab has no `AppTab` tag:

```swift
private enum CompactTab: Hashable { case accounts, activity, budgets, insights, more }
```

State held by `TabBarShell`:

```swift
@State private var selected: CompactTab = .accounts
@State private var morePath: [AppTab] = []   // pushed overflow screen (.scheduled / .settings), 0 or 1 deep
```

The More root pushes via `navigationDestination(for: AppTab.self)` mapping
`.scheduled → ScheduledTab()`, `.settings → SettingsTab()` (each already wrapped
by `MoreTabNavigationStack`, which is a no-op in compact, so the title attaches
to the More stack).

### Router bridge

`DeepLinkRouter.selectedTab` stays authoritative. Two guarded observers keep it
in sync with the compact UI:

- **`onChange(of: router.selectedTab)`** (programmatic select — intent /
  notification / palette / first launch via `onAppear`):
  - `.scheduled` / `.settings` → `selected = .more`; set `morePath = [tab]`
    (only if not already its tail, to avoid stomping a deeper state).
  - any primary tab → `selected = <mapped>`; `morePath = []`.
- **`onChange(of: selected)`** (user taps the bar):
  - primary tab → `router.selectedTab = <mapped AppTab>` (only if different).
  - `.more` → leave `router.selectedTab` unchanged (user is just browsing More).

Equality guards on both sides prevent a feedback loop: selecting `.more` never
writes back to the router, and writing a primary tab to the router only fires
when the value actually changes.

### Mapping helpers

- `CompactTab → AppTab?` (`.more → nil`).
- `AppTab → CompactTab` (`.scheduled/.settings → .more`, else the matching case).

## Behavior / edge cases

- **Scheduled-reminder notification** (`router.selectedTab = .scheduled` +
  `focusId`): bridge sets `selected = .more`, `morePath = [.scheduled]` →
  lands on More → Scheduled with title + single back. ✅
- **Re-tapping the More tab** while a sub-screen is shown: native
  `NavigationStack` pops to root (the More list). ✅
- **Leaving More and returning**: `morePath` persists, so More restores the last
  sub-screen — standard iOS behavior.
- **⌘K "Go to Scheduled/Settings"** in compact: routes through the same bridge.

## Testing

- Build: `xcodebuild -scheme FinchApp -destination 'platform=iOS Simulator,…'`.
- Existing unit tests must stay green (`AppIntentsTests`, `LockDecisionTests`).
- Manual sim verification (scripted taps, see `ios/docs/simulator-ui-driving.md`):
  - Bottom bar shows 4 tabs + More (no system "More" list-of-lists chrome).
  - More → Scheduled and More → Settings: single back button **and** visible
    title.
  - Settings → Manage ledgers (and a Power Tools page, e.g. Rules): single back
    + title.
  - Trigger an `OpenScreenIntent` / notification for Scheduled → lands on More →
    Scheduled.

## Out of scope

- iPad/Mac sidebar behavior.
- Any change to the set of destinations (no tabs added/removed/merged).
