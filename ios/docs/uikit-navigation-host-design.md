# UIKit Navigation Host — iOS 26 Liquid Glass Resume-Shadow Fix (Design Spec)

**Status:** design · **Date:** 2026-07-25 · **Platform:** iOS (compact / iPhone) only

## Problem

On iOS 26, a scrolled list that was reached by a **push** shows a Liquid Glass
"shadow" — a dark band that lingers ~2–3s under the top bar — after the app is
backgrounded and resumed. It affects Budgets → budget detail, every Settings
page, the PowerTools pages, and the Accounts drill-ins. Root tabs (never pushed)
never show it. iPad/Mac (three-column `SplitViewShell`) never show it.

### Root cause (device-confirmed, 2026-07-25, iPhone 16 Pro Max / iOS 26)

The shadow is produced by **SwiftUI `NavigationStack`**, not by the glass itself.
A SwiftUI `NavigationStack` re-samples / re-converges the `.soft` scroll-edge
glass of a *pushed* view when the app returns to the foreground. A real UIKit
`UINavigationController` push of the **same** view does not — it preserves the
pushed view and shows no shadow.

Evidence:
- Prototype on device: UIKit-pushed `ActivityFeedView` and `AccountDetailView` →
  **no shadow**; SwiftUI-pushed Budgets detail / Settings pages → **shadow**.
- Sim relative *contrast* metric (post-resume top-edge deviation-from-settled),
  stable across 3 repeats each: SwiftUI-push **~47**, UIKit-push **~6**, root **~9**.
  (The sim is not a faithful proxy for the *absolute* shadow — every absolute-shadow
  "fix" failed on device — but this *relative structural* split reproduces the
  device facts and the mechanism.)
- Not data: earlier proven via `NSLog` + `Self._printChanges` that nothing
  reprojects / recomputes / re-renders the body on resume.

Rejected alternatives: `.scrollEdgeEffectStyle(.hard)` (fixes it but is less
transparent — user rejected); `.scrollEdgeEffectHidden()` (sim-clean, device-shadowed);
introspection to freeze the effect (reduces to `.hard`; stopping SwiftUI's rebuild
needs private API). Interim fix shipped in PR #628: a `fullScreenCover` modal for
Accounts only — works but slides *up* and covers only one tab.

See also `ios/docs/ios26-liquid-glass-artifacts.md` (post-mortem, in PR #628).

## Goals / Non-goals

**Goals**
- Eliminate the resume shadow on **all** compact pushed scrolled lists.
- Keep the native **slide-from-right** push and full `.soft` transparency.
- **No changes** to the pushed views' own `.toolbar` / `.searchable` /
  `.navigationTitle` / back behavior.
- Supersede the PR #628 Accounts modal (restore slide-from-right there).

**Non-goals**
- iPad/Mac `SplitViewShell` (three-column) — unaffected, untouched.
- Sheet-hosted `NavigationStack`s (a sheet is a modal root — no shadow) — untouched.
- watchOS.

## Key enabling finding

`UIHostingController` **bridges** `.toolbar`, `.searchable`, `.navigationTitle`,
and `\.dismiss` to its parent `UINavigationController` on iOS 26. Screenshot-proven
for a UIKit-pushed `ActivityFeedView`: the "Activity" title, back chevron, the
Select / filter / sort toolbar items, **and** the search bar all render with zero
changes to `ActivityFeedView`. This is what makes the migration mechanical: route
the *push* through UIKit and each pushed view keeps its chrome.

## Architecture

A small, app-specific, **iOS-only** navigation component that each compact tab
body uses in place of its `NavigationStack`. The iPad/Mac (`selection != nil`)
branch of every tab keeps `NavigationStack` exactly as today.

### Components (all `#if os(iOS)`)

1. **`UIKitNavStack<Root: View>`** — `UIViewControllerRepresentable` wrapping a
   `UINavigationController` whose root is `UIHostingController(rootView: root)`.
   - Publishes an imperative push/pop facade to the SwiftUI tree via
     Environment: `\.navPush` (`(AnyView) -> Void`) and `\.navPopToRoot`.
     Pop-by-one is `\.dismiss` (bridged to `popViewController`).
   - `prefersLargeTitles` set to match the tab (large on tab root, inline on
     detail via each view's existing `navigationBarTitleDisplayMode`).
   - A `Coordinator` holds a `weak UINavigationController` and the **environment
     decorator** (below); every push wraps its destination through the decorator
     so pushed views get the app environment *and* the same `\.navPush` closure
     (enabling multi-level push).

2. **`UIKitNavLink<Label, Destination>`** — a row that renders `Label` and, on
   tap, calls `\.navPush(AnyView(Destination))`. Drop-in replacement for
   `NavigationLink { Destination } label: { Label }`, so Settings' 14 links and
   the Budgets/PowerTools destinations migrate near-find-replace.

3. **Environment decorator** — the one real complication. A UIKit push does **not**
   inherit SwiftUI environment from the presenting hosting controller, so every
   pushed `UIHostingController.rootView` must be re-decorated with the app's
   environment objects. The app injects exactly **three** app-wide
   `@EnvironmentObject`s (verified — these are the only `@EnvironmentObject` types in
   the codebase): `FinchStore`, `DeepLinkRouter`, `BiometricGate`. `@Environment`
   *trait* values (`horizontalSizeClass`, color scheme, dynamic type) come from the
   hosting controller's `UITraitCollection` automatically. `@AppStorage` is global.
   Implementation: a single `.finchNavEnvironment(store:router:gate:)` modifier applied
   by the coordinator on every push; `UIKitNavStack` reads those three objects via its
   own `@EnvironmentObject` and hands them to the coordinator.

### How a tab adopts it

Each compact tab currently is `NavigationStack { inner }` where `inner` =
list + `.searchable` + `.navigationTitle` + `.toolbar` + sheets + alerts. Split
the container at the top:

```
#if os(iOS)
if selection == nil {            // compact / iPhone push mode
    UIKitNavStack { inner }      // toolbar/search/title bridge; drills use navPush
} else {
    NavigationStack { inner }    // iPad list column — unchanged
}
#else
NavigationStack { inner }        // macOS — unchanged
#endif
```

`inner` is shared; only the few **navigation-wiring** modifiers differ and are
conditionalized: `NavigationLink`/`.navigationDestination`/`.ledgerPush()` exist
only on the `NavigationStack` path; the `UIKitNavStack` path uses `UIKitNavLink`
and `navPush`.

## Per-site migration map

| Site | Today | Compact (UIKitNavStack) |
|---|---|---|
| Settings (14 rows) | `NavigationLink { Dest } label: { Row }` | `UIKitNavLink { Dest } label: { Row }` |
| Budgets → detail | `NavigationLink(value:)` + `.navigationDestination(for: String.self)` | `UIKitNavLink { BudgetDetailView(budgetId: id) }` |
| PowerTools (Categories/Merchants/Tags) | `.navigationDestination(item: $sel)` | `.onChange(of: sel) { navPush(Detail(id:)) }` |
| Accounts drill-ins | `fullScreenCover(item: $drill)` modal (PR #628) | `navPush(ActivityFeedView / AccountDetailView)`; **remove** the modal, the `DrillTarget` enum, and the debug prototype harness |
| Ledger push | `.ledgerPush()` = `.navigationDestination(isPresented: router.showLedger)` | observe `router.showLedger` → `navPush(LedgerListView())`; reset `showLedger` on pop |
| Deep links | `DeepLinkRouter` drives `NavigationLink`/destination | route through `navPush` |
| Scheduled / Activity / Ledger tab pushes | `NavigationLink` | `UIKitNavLink` / `navPush` |

## Edge cases & risks (verify in the pilot)

- **Environment re-injection** (primary risk): a pushed view that reads an
  `@EnvironmentObject` not in the decorator will crash. Mitigation: the decorator
  injects the full known set (`FinchStore`, `DeepLinkRouter`, `BiometricGate` — the
  only three in the codebase); keep the decorator the single choke point so a future
  fourth env object is a one-line add.
- **Root-tab toolbar bridging**: the tab *root* (e.g. Accounts' `+` / ledger button /
  reorder ✕✓, `.searchable`, large title, `editMode`) must bridge from the root
  `UIHostingController` — same mechanism as the pushed view, but heavier. **Verify
  first** (Accounts root is the stress case).
- **Multi-level push** (pushed view pushes again): the decorator re-injects
  `\.navPush`, so deeper pushes work. Verify with a 2-level chain.
- **`\.dismiss` → pop**: pushed views call `dismiss` (e.g. `AccountDetailView`
  after delete). Confirm it pops the UIKit nav, incl. programmatic dismiss.
- **Interactive back-swipe**: native to `UINavigationController` — free.
- **Tab switch preserves each tab's stack**: each tab owns its `UINavigationController`,
  which persists across tab switches (matches `NavigationStack` behavior).
- **Ledger switch invalidates a pushed detail**: on `activeLedgerId` change, `navPopToRoot`.
- **Sheets/alerts from pushed views**: presented modally by the hosting controller —
  unaffected.

## Testing / verification

- **Device (authoritative gate)** per migrated tab: scroll a pushed page →
  background → resume → confirm **no shadow**. Also confirm toolbar/search/title/back
  all render and multi-level push + dismiss work.
- **Sim (cheap signal, not authoritative)**: contrast metric < ~15 on the migrated
  push (script + venv already set up under the job dir).
- **Builds**: FinchApp (iOS), **FinchMac** (macOS — component is `#if os(iOS)`;
  macOS path unchanged), FinchWatch, and `ci-local` (356 + 320 tests, i18n guard).
- **No iPad regression**: the `selection != nil` three-column path is byte-for-byte
  unchanged; spot-check Accounts/Budgets three-column on iPad sim.

## Rollout (incremental — each step independently shippable + device-verified)

0. **Pilot / infra**: build `UIKitNavStack`, `UIKitNavLink`, the environment
   decorator; migrate **Budgets** (single clean destination). Device-verify the
   shadow is gone AND that root-toolbar bridging + env injection + `\.dismiss`
   work. This step de-risks the whole design.
1. **Settings** (largest surface, 14 links).
2. **Accounts**: migrate drill-ins to `navPush`; **remove** the #628 modal, the
   `DrillTarget` enum, and the debug prototype harness.
3. **Scheduled, Ledger, Activity, PowerTools, `.ledgerPush()`, deep links**.
4. Update `ios/docs/ios26-liquid-glass-artifacts.md` with the final UIKit
   resolution.

## Relationship to PR #628

PR #628 bundles two independent fixes: (a) the **tab-switch smear** fix
(`DisableTabContentTransition`) — good, keep it; (b) the **Accounts modal** shadow
fix — superseded by this work. Recommended: amend #628 to swap the modal for the
UIKit nav host (keeping the tab-switch fix + the doc), or land this as a new PR
that reverts the modal. Decide at rollout step 2.

## Out of scope / follow-ups

- Unifying the compact-push and iPad-select interactions behind one facade (the
  iPad branch already diverges; not worth it now).
- A generic, app-agnostic version of `UIKitNavStack` (this one may reference
  `FinchStore`/`DeepLinkRouter` directly).
