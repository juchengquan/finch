# Spec: iPad/macOS sidebar-collapse persistence (#414 deferral)

**Date:** 2026-07-15
**Status:** design approved, ready for implementation plan
**Scope:** native app (`ios/`), the regular-width shell only (`Shell/AdaptiveShell.swift` `SplitViewShell` + `Shell/MasterDetailShell.swift` `ThreeColumnShell`). Closes the second #414 deferral (the first — Activity/Scheduled detail columns — remains open).

## Goal

Remember whether the user collapsed the sidebar — across app launches **and** across tab switches — **without** recording iPadOS's rotation auto-collapse as if it were the user's preference (the trap that got this deferred in #414).

## Current state (baseline)

- Neither split view binds `columnVisibility`; both run on `.automatic`:
  - `ThreeColumnShell` (MasterDetailShell.swift:56) — sidebar │ list │ detail, used by Accounts/Budgets/Ledger.
  - The 2-column `NavigationSplitView` in `SplitViewShell`'s `default:` branch (AdaptiveShell.swift:243) — sidebar │ content, used by Insights/Settings/Activity/Scheduled.
- Because `SplitViewShell` switches over `router.selectedTab`, the split views are **re-created on every tab switch**, so any sidebar collapse resets when changing tabs — an in-session annoyance this feature also fixes.
- The #414 design doc (2026-07-07-ipad-multicolumn-design.md:41) records why naïve persistence was deferred: *"iPadOS auto-collapses columns on rotation to portrait; naïvely persisting `NavigationSplitViewVisibility` would record that auto-collapse as a user preference and pin the sidebar closed after rotating back."*

## Design

### 1. State — one Bool, per device

- `@AppStorage("finch.sidebarCollapsed") var sidebarCollapsed = false` — a per-device UX preference (same pattern/precedent as `finch.privacy` and the feed toggles). Never in the DB or `.finch` packs.
- A **Bool**, not the raw `NavigationSplitViewVisibility`, because it maps cleanly onto both shells:
  - `ThreeColumnShell`: collapsed → `.doubleColumn` (list + detail), expanded → `.all`.
  - 2-column shell: collapsed → `.detailOnly`, expanded → `.doubleColumn`.

### 2. Mechanism — a shared `PersistedSplitVisibility` helper

- One small shared unit (a `ViewModifier` + a tiny pure mapping, or an equivalent wrapper — implementer's choice of exact shape) used by **both** split views, so the heuristics live in one place:
  - Local `@State var visibility: NavigationSplitViewVisibility`, seeded from the pref via the shell-appropriate mapping (`onAppear`/init), bound to `NavigationSplitView(columnVisibility: $visibility, …)`.
  - Wrapped in a `GeometryReader` (or `onGeometryChange`) to know the container's orientation: `isLandscape = width > height`.
  - `onChange(of: visibility)`: **persist `sidebarCollapsed` only when `isLandscape`** — portrait visibility changes are system auto-collapse (or overlay toggles) and are deliberately not trusted.
  - `onChange(of: isLandscape)` (portrait → landscape): **re-apply the stored pref** to `visibility`, undoing the auto-collapse rather than inheriting it.
  - macOS: windows are effectively always `width > height` in practice, and there is no auto-collapse — toggles persist naturally through the same code path; no `#if os` split needed for the logic (only for anything that genuinely doesn't compile).
- The **pure mapping** (Bool + shell kind ⇄ visibility) should be extracted as a small testable function/enum (e.g. `SplitVisibilityMapping.visibility(collapsed:columns:)` and `collapsed(from:columns:)`), unit-tested in `FinchAppTests` — the only real logic here.

### 3. Call sites

- `ThreeColumnShell` (MasterDetailShell.swift): adopt the helper with the 3-column mapping.
- `SplitViewShell`'s `default:` 2-column `NavigationSplitView` (AdaptiveShell.swift:243): adopt the helper with the 2-column mapping.
- Because both seed from `@AppStorage` on creation, tab switches (which re-create the shells) now restore the preference automatically — the in-session reset disappears as a side effect.

## Accepted limitations (documented in code)

- Explicitly opening the sidebar **while in portrait** (overlay presentation) is not recorded — portrait changes are untrusted by design. The stored preference re-asserts on the next rotation to landscape / next launch.
- `isLandscape` is derived from the container's aspect (`width > height`), not device orientation APIs — good enough for the split-view container, avoids UIKit orientation plumbing, and behaves sensibly in iPad multitasking splits (a narrow Split-View pane behaves like portrait: untrusted).

## Non-goals

- No Activity/Scheduled detail columns (the other #414 deferral — its own feature).
- No persistence of the *list column* (middle) visibility beyond what the Bool mapping implies; no per-tab preferences (one global Bool).
- No compact/iPhone changes (compact uses the tab bar, no sidebar).
- No `@SceneStorage`/multi-window-per-scene state (single global pref; multi-window scene-per-ledger is a separate roadmap item).

## Testing / verification

- **Unit tests (`FinchAppTests`):** the pure mapping both directions for both shell kinds (collapsed/expanded × 2-col/3-col), and idempotence (`collapsed(from: visibility(collapsed: x)) == x`).
- **Builds:** `FinchApp` (iOS) + `FinchMac` (macOS).
- **Simulator (scripted part):** boot an **iPad** simulator, launch, screenshot the regular-width shell; toggle persistence across relaunch can be pre-seeded via `defaults write com.juchengquan.finch finch.sidebarCollapsed -bool YES` + relaunch → sidebar starts collapsed (this verifies the seed path without rotation).
- **Manual rotation matrix (needs a human — the sandbox cannot rotate the simulator):** a 4-step checklist shipped with the PR:
  1. Landscape: collapse the sidebar (toolbar button) → relaunch → still collapsed.
  2. Landscape: expand → rotate portrait (auto-collapse happens) → rotate back → sidebar **re-opens** (auto-collapse not recorded).
  3. Portrait: toggle the overlay sidebar → rotate to landscape → stored pref (not the portrait toggle) wins.
  4. macOS: collapse via the toolbar → relaunch → still collapsed.

## Risks

- `NavigationSplitViewVisibility` behavior differs subtly across iPadOS versions/multitasking widths — the aspect-gate is a heuristic; the accepted-limitations section bounds the blast radius (worst case: a preference isn't recorded, never a wrongly-pinned sidebar, because portrait writes are ignored and landscape re-asserts the pref).
- The shell is shared with macOS — verify FinchMac renders and toggles normally (no `#if` should be needed; the same gate logic passes trivially on Mac).
- `GeometryReader` wrapping a `NavigationSplitView` must not disturb layout — prefer reading size via `.onGeometryChange`/background reader rather than wrapping the split view itself if any layout shift appears.
