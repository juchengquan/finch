# The floating add-`+` on converted UIKit pushed screens — design

**Date:** 2026-07-31 (revised 2026-08-01 after #658 landed)
**Status:** implemented on `fix/ios-uikit-pushed-fab`
**Fixes:** the third bullet of §2c in `ios/docs/uikit-migration-verification.md`

## The problem

Two halves, which failed independently.

**The button was missing.** Every screen converted to UIKit and reached by a push had
lost the floating `+`. `AddTransactionFAB` is a SwiftUI overlay applied to the tab
**root**, so a pushed `UIViewController` covers it. Measured with
`idb ui describe-all`: SwiftUI has `Add Transaction` on the account detail, the
converted screen has no such element.

**The sheet was not seeded.** #658 restored the button on Budgets by wrapping that
tab in `TabChromeVC`, which hosts the real SwiftUI FAB over the native content. But
that FAB reads its page context from `AddTxContextKey`, a preference published up a
SwiftUI view tree — and `TabChromeOverlay` applies it to `Color.clear`, a tree with
nothing in it. So the FAB came back opening an **unseeded** sheet where the SwiftUI
path pre-fills the page's account and category.

Verified on the simulator before fixing: tapping the `+` on the Health budget's detail
gave an Add sheet with Account and Category both blank, while the same flow in hosted
mode gave `Account, Credit Card` and `Category, Pharmacy`.

## The approach

**Reuse `TabChromeVC`; do not build a second FAB.** An earlier draft of this branch
added `AddTxFABHost`, a UIKit-hosted button constrained to the navigation
controller's safe area. #658 then shipped `TabChromeVC`, which solves the same problem
by hosting the *real* modifier — keeping one implementation of the FAB's five rules
rather than a UIKit copy that must stay in step with the Mac's. That draft is
superseded; it survives only as the local branch `backup/fab-host-approach`.

So:

1. **Every converted tab with a FAB is wrapped in `TabChromeVC`**, exactly as #658
   wrapped Budgets. The chrome sits above the whole navigation controller, so the
   button floats over pushed screens. Settings has no FAB and needs no wrapper.
2. **`StacklessTabRoot` stops applying `.addTransactionFAB()`** (`TabChrome`'s new
   `appliesFAB: false`). Accounts' root is still a hosted SwiftUI view, so without
   this the root's own FAB and the chrome's would stack two buttons.
3. **`AddTxFABProviding` carries what a preference cannot.** A pushed view controller
   has no SwiftUI tree, so it states its subject and its multi-select state directly:

```swift
protocol AddTxFABProviding: UIViewController {
    var addTxContext: AddTxContext { get }
    var hidesAddTxFAB: Bool { get }
    var addTxFABStateDidChange: AnyPublisher<Void, Never> { get }
}
```

   Conformance is optional — `TabChromeVC` casts and falls back to empty defaults — so
   a screen converted later inherits a working FAB without implementing anything.
   `AccountDetailVC` supplies its account, `BudgetDetailVC` its account + category,
   `ActivityFeedVC` its multi-select.

4. **`TabChromeVC` follows the native stack** as `UINavigationControllerDelegate`, and
   `TabChromeOverlay` **republishes** what it learns as the very same preferences the
   FAB already reads:

```swift
Color.clear
    .preference(key: AddTxContextKey.self, value: native.context)
    .preference(key: SelectionActiveKey.self, value: native.selecting)
    .addTransactionFAB()
```

   The FAB itself is untouched. One set of rules, fed from two kinds of screen.

## Testing

`testFloatingAddButtonSurvivesAccountDrill` and `…BudgetDrill` run in both navigation
modes. Each drills in, asserts the button is still there, taps it, and asserts the
sheet came up **seeded** — existence alone would have passed on the unseeded state
that #658 left behind.

Three test traps, each of which produced a false result first:

- **Query by identifier, not label.** A screen's toolbar `+` carries the same
  `Add Transaction` label, and `label BEGINSWITH "Account"` also matches the
  **"Accounts" tab-bar button** and the budget detail's own Account row behind the
  sheet. Hence `fab.addTransaction`, `addtx.account`, `addtx.category`.
- **The seeded field differs per screen.** The demo's Health budget is
  `("Health", 100, "cat-health", nil)` — a category and NO account — so asserting a
  seeded Account row there fails correctly and proves nothing.
- **Hosted keeps two FABs in the tree.** A cover is presented `.overFullScreen`, so
  the tab root's button stays behind it, findable but not hittable.

The seeding half runs in uikit mode only. Hosted seeding was verified by hand on the
simulator (the cover's `+` opens a sheet reading `Account, Checking`), but XCUITest
cannot drive that cover's button — the tap resolves and no sheet appears, with both
`.tap()` and a coordinate tap. The uikit path is the one this change alters and it is
asserted in full; the hosted path keeps its existence assertions.

## Non-goals

- The other §2c items: the inline-vs-large title (~52pt) and the 9pt row offset.
  #657 is taking the title one.
- Flipping the `uikitActivity` default. This is a prerequisite, not the flip.
- iPad's `SplitShellVC`, which installs no `nativeRoute` seam and pushes no converted
  screens.
