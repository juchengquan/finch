# Widgets CP3 — interactive quick-add (tap → Add) (iOS)

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** FinchApp (URL scheme + `onOpenURL` + a router method) + FinchWidget (`.widgetURL`). **No engine/snapshot change.** Final CP of the "deepen widgets" sub-project.

## Problem

The widgets are display-only — tapping one just opens the app to its last screen. There's no quick path from a widget to **add a transaction**. A *silent* in-widget write is impossible (the DB isn't in the App Group), so the realistic interactive quick-add is: **tap widget → app opens straight to the Add-Transaction sheet.**

## Key findings (verified)

- `DeepLinkRouter.shared.showAddTransaction: Bool` already exists, and the root `WindowGroup` already presents `AddTransactionSheet` from it (`.sheet(isPresented: $router.showAddTransaction)`). Setting it `true` opens Add from anywhere — the FAB / ⌘N / command palette all do this.
- **Missing:** no custom URL scheme (`CFBundleURLTypes` absent) and no `.onOpenURL` handler. These are the only app-side wiring CP3 adds.
- No widget currently uses `.widgetURL`/`Link`. `.widgetURL` on a widget's content opens the app with that URL — works for **all** families incl. lock-screen accessory (which can't host sub-buttons).
- The widget extension can't import the app's `AddTransactionIntent` (and that intent writes the DB anyway), so a URL deep link (Path A) is far lighter than an App-Intent button.

## CP3 decisions (locked)

1. **Path A — URL deep link.** `finch://add` → `onOpenURL` → `router.showAddTransaction = true`. Reuses the existing root sheet; no new intent.
2. **Plain add** (no account pre-fill) for all widgets in CP3. (Account pre-fill via `finch://add?account=<id>` is an easy follow-up; out of scope here.)
3. Whole-widget tap via `.widgetURL` (uniform across families), applied in the widget content closures (not the view structs).

## Detailed design

### FinchApp — URL scheme + handler

- **`ios/FinchApp/Info.plist`** — add `CFBundleURLTypes` with one entry whose `CFBundleURLSchemes` = `["finch"]` (a `CFBundleURLName` like `com.juchengquan.finch`).
- **`DeepLinkRouter`** — add:
  ```swift
  /// Handle a `finch://…` deep link (e.g. from a widget). `finch://add` opens the Add sheet.
  public func handle(_ url: URL) {
      switch url.host {
      case "add": showAddTransaction = true
      default: break
      }
  }
  ```
- **`FinchApp.swift`** root `WindowGroup` — add `.onOpenURL { router.handle($0) }` (alongside the existing `.onContinueUserActivity` / `.sheet` modifiers; uses the same `router` instance the UI observes).

### FinchWidget — tap target

Apply `.widgetURL(URL(string: "finch://add"))` to each widget's content view in the configuration closures (`FinchWidget.swift`):
```swift
StaticConfiguration(kind: "FinchOverview", provider: FinchProvider()) { entry in
    FinchWidgetView(entry: entry).widgetURL(URL(string: "finch://add"))
}
// and likewise for AccountWidget (AccountWidgetView) + BudgetWidget (BudgetWidgetView)
```
One line per widget; no change to the view structs; covers home + lock-screen families.

### Reuse

`router.showAddTransaction` + the existing root `AddTransactionSheet` presentation; the widgets' existing views.

## Facts (verified)

- `DeepLinkRouter` (FinchApp/DeepLink/DeepLinkRouter.swift): `@MainActor`, `showAddTransaction` published, `route(to:)`/`open(_:)`; observed as the root `@StateObject`/`DeepLinkRouter.shared`.
- Root `FinchApp.swift` `WindowGroup` chains `.onContinueUserActivity` + `.sheet(isPresented: $router.showAddTransaction) { AddTransactionSheet()… }` — the hook point for `.onOpenURL`.
- `FinchApp/Info.plist` has UTI/Spotlight keys but no `CFBundleURLTypes`. `project.yml` FinchApp target uses `INFOPLIST_FILE: FinchApp/Info.plist`.
- The 3 widgets (`FinchWidget`/`AccountWidget`/`BudgetWidget`) + their views exist (CP1/CP2). 0 open PRs touch widgets/deep-link.

## Testing

- **FinchApp (`DeepLinkRouter.handle`):** `handle(URL("finch://add"))` sets `showAddTransaction == true`; `handle(URL("finch://bogus"))` leaves it `false`. (`@MainActor` test.)
- **Build gate:** iOS (FinchApp embeds FinchWidget) + macOS (FinchMac — `onOpenURL` is cross-platform). Full FinchAppTests + FinchCore green.
- **Manual (sim):** add any finch widget → tap it → the app opens with the **Add Transaction** sheet presented. (Confirm on a lock-screen accessory widget too.)

## Out of scope (later / Watch sub-project)

Account pre-fill (`finch://add?account=<id>` → `AddTransactionSheet(defaultAccountId:)`); a true in-widget silent write (needs the DB in the App Group); deep links to other screens; the Watch complication + quick-add (separate sub-project). This CP completes the widgets sub-project (CP1 lock-screen, CP2 configurable, CP3 quick-add).
