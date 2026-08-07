# Privacy Moves To The Ledger Button — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reclaim a toolbar slot on every iPhone screen. The privacy eye comes off, and hiding amounts moves into a hold-menu on the ledger button, with a Settings row as its visible home.

**Architecture:** `UIBarButtonItem` supports a tap action and a long-press menu on the same button; the ledger button already has the tap. Adding the menu is two lines per screen. The eye becomes regular-width-only, reusing the flag that already gates the ledger button the other way.

**Tech Stack:** Swift 5.9 / UIKit (`UIBarButtonItem`, `UIMenu`) + SwiftUI (`Menu(primaryAction:)`), XCTest. App target `ios/FinchApp` only.

## Global Constraints

- **Branch:** `feat/privacy-in-ledger-menu`, cut from `origin/feat/frontend`.
- **PRs target `feat/frontend`.** Never `main`.
- **No `Co-Authored-By` trailer in commits.**
- **iOS/macOS app only.** No `ios/FinchCore`, no `frontend/`.
- **NO NEW CATALOG STRINGS.** `"Hide Amounts"` (zh: 隐藏金额) and `"Privacy mode"` (zh: 隐私模式) both already exist and are translated. Reuse them exactly, including capitalisation. Adding a key means an export/rebuild round and a catalog commit — not needed here, so don't cause one.
- **Build:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` **and** `PATH="$DEVELOPER_DIR/usr/bin:$PATH"`.
- **The gate:** `ios/scripts/ci-local.sh` is the pre-push gate (PR checks no longer run Xcode). This change is chrome and navigation, so it needs **`--ui`** — `--full` does NOT imply the UI tests. Do not pass `SIM_NAME`; the script derives the simulator from the worktree name now.
- **`FinchApp.xcodeproj` is generated and gitignored.** Run `xcodegen generate` after branching.
- After any `xcodebuild` run, discard catalog churn:
  `git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings`

---

## Background: where the eye is, and what replaces it

The privacy toggle appears on **five** primary screens. Four are UIKit
(`AccountsListVC`, `BudgetsListVC`, `ScheduledListVC`, `SettingsListVC` — the
tabs in `UIKitScreens.navTabs`); Insights is still a hosted SwiftUI root and gets
its eye from `PrivacyToggleButton` in `AdaptiveShell.swift`.

On Accounts and Budgets the right cluster is already three items
(`[more, add, privacy]`); on Scheduled two; on Settings the eye is the *only*
button.

### Why the ledger button and not the tab bar

`UITabBarItem` has **no menu, context-menu or long-press API** — verified in the
SDK headers; `UIBarButtonItem` has had `menu` since iOS 14 and
`menuRepresentation` since 16, and the tab bar never got the equivalent. Doing it
on the tab bar means a `UILongPressGestureRecognizer` on `tabBar`, hit-testing
against geometry `UITabBar` does not publish, private view classes, a fight with
tab selection, and separate behaviour for the iPad sidebar. The ledger button
gets the same feature by filling in a property that is currently nil.

### The compact flag is already there, pointing the other way

Every screen already knows whether it is the compact tab root or an iPad column,
because the ledger button is **compact-only** (the iPad sidebar lists Ledger
itself). The eye needs exactly the opposite test:

| Screen | compact when | ledger button | eye after this change |
|---|---|---|---|
| `AccountsListVC` | `onSelect == nil` | `if onSelect == nil` | `if onSelect != nil` |
| `BudgetsListVC` | `onSelect == nil` | `if onSelect == nil` | `if onSelect != nil` |
| `ScheduledListVC` | `onSelect == nil` | `if onSelect == nil` | `if onSelect != nil` |
| `SettingsListVC` | `showsLedgerControl` | `if showsLedgerControl` | `if !showsLedgerControl` |
| Insights (SwiftUI) | `sizeClass == .compact` | `LedgerBarButton` (already gated) | gate `PrivacyToggleButton` to `!= .compact` |

**Decided during design, do not relitigate:**

1. **Tap is unchanged** — the ledger button still opens the ledger picker. The
   menu is on long-press.
2. **The eye comes off iPhone entirely**, all five screens.
3. **iPad keeps its eye.** It has no ledger button to hold, and a wide toolbar
   has room.
4. **Settings gains a row**, because the hold-menu is invisible and without a
   visible home the feature ceases to exist for anyone who was not told.
5. **The menu item carries a checkmark** when privacy is on, so a hidden control
   can be read rather than only fired.
6. **No App Intent.** Three surfaces: the hold-menu, the Settings row, the iPad eye.
7. **macOS is untouched** — `FinchCommands` already has a "Hide Amounts" menu item.

---

## File structure

| File | Change |
|---|---|
| `AdaptiveShell.swift` | `LedgerBarButton` gains the menu; `PrivacyToggleButton` becomes regular-width-only. Every SwiftUI tab inherits both — no per-tab edits. |
| `AccountsListVC.swift`, `BudgetsListVC.swift`, `ScheduledListVC.swift` | Ledger button gains the menu; eye becomes `onSelect != nil`. |
| `SettingsListVC.swift` | The same on `showsLedgerControl`, plus the visible row. |
| `PrivacyMenu.swift` (new, FinchShared) | The one place that builds the `UIAction`, so four call sites cannot drift on title, checkmark or behaviour. |
| `PrivacyMenuTests.swift` (new) | The action's title, state and toggle behaviour. |

---

## Task 1: One builder for the menu item

Four UIKit screens need an identical action. Build it once.

**Files:**
- Create: `ios/FinchApp/Sources/FinchShared/Common/PrivacyMenu.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/PrivacyMenuTests.swift`

**Interfaces:**
- Produces: `PrivacyMenu.action(store:) -> UIAction` and `PrivacyMenu.menu(store:) -> UIMenu`.
- Consumes: `FinchStore.privacyMode`.

- [ ] **Step 1: Write the failing test.**

```swift
import XCTest
@testable import FinchApp
import FinchCore

/// The hold-menu's one item, built once and shared by four screens.
///
/// It is worth testing rather than eyeballing because the item is INVISIBLE
/// until someone long-presses a button they have only ever tapped — a wrong
/// title or a missing checkmark is not something a user will report, they will
/// simply never find the feature.
final class PrivacyMenuTests: XCTestCase {

    override func tearDown() {
        FinchStore.shared.privacyMode = false
        super.tearDown()
    }

    /// Reuses the string the Mac menu already uses — already translated, so this
    /// change adds no catalog key.
    func test_theItemIsTitledHideAmounts() {
        let action = PrivacyMenu.action(store: FinchStore.shared)
        XCTAssertEqual(action.title, String(localized: "Hide Amounts"))
    }

    /// A checkmark, so a hidden control can be READ and not only fired: hold the
    /// button and the menu tells you whether amounts are currently masked.
    func test_theItemCarriesItsState() {
        FinchStore.shared.privacyMode = false
        XCTAssertEqual(PrivacyMenu.action(store: FinchStore.shared).state, .off)

        FinchStore.shared.privacyMode = true
        XCTAssertEqual(PrivacyMenu.action(store: FinchStore.shared).state, .on)
    }

    /// And it actually drives the store — a menu that renders and toggles
    /// nothing is the failure mode this whole change could ship with unnoticed.
    func test_firingTheItemTogglesTheStore() {
        FinchStore.shared.privacyMode = false
        PrivacyMenu.action(store: FinchStore.shared).performWithSender(nil, target: nil)
        XCTAssertTrue(FinchStore.shared.privacyMode)
    }
}
```

- [ ] **Step 2: Run it and record the failure.**

```bash
cd ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" && \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests/PrivacyMenuTests test 2>&1 | grep -E "error:|Executed"
```
Expected: does not compile — `PrivacyMenu` does not exist.

- [ ] **Step 3: Create the builder.**

```swift
#if canImport(UIKit)
import UIKit

/// The privacy toggle as a menu item, built in ONE place.
///
/// Four screens show this on a long-press of their ledger button. Built here so
/// they cannot drift on the title, the checkmark or the behaviour — the item is
/// invisible until someone holds a button they have only ever tapped, so a
/// discrepancy between screens is not something anyone would report.
public enum PrivacyMenu {

    /// Reuses `"Hide Amounts"`, the string the macOS menu command already uses
    /// and the catalog already translates. A new key would cost an export round
    /// and a catalog commit for a phrase that exists.
    public static func action(store: FinchStore) -> UIAction {
        let action = UIAction(title: String(localized: "Hide Amounts"),
                              image: UIImage(systemName: "eye.slash")) { _ in
            store.privacyMode.toggle()
        }
        // The checkmark is what lets a HIDDEN control be read rather than only
        // fired: hold the button and the menu says whether amounts are masked.
        action.state = store.privacyMode ? .on : .off
        return action
    }

    public static func menu(store: FinchStore) -> UIMenu {
        UIMenu(children: [action(store: store)])
    }
}
#endif
```

- [ ] **Step 4: Run — three tests green.** Same command as Step 2.

- [ ] **Step 5: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: the privacy toggle as a menu item, built in one place

Four screens are about to show this on a long-press of their ledger button.
Built once so they cannot drift on title, checkmark or behaviour — the item is
invisible until someone holds a button they have only ever tapped, so a
discrepancy between screens is not something anyone would report.

Reuses \"Hide Amounts\", which the macOS menu command already uses and the
catalog already translates, so this adds no key.

The checkmark is what lets a hidden control be read rather than only fired."
```

---

## Task 2: The four UIKit screens

**Files:**
- Modify: `AccountsListVC.swift` (ledger `:355`, right items `:413`)
- Modify: `BudgetsListVC.swift` (ledger `:352`, right items `:390`)
- Modify: `ScheduledListVC.swift` (ledger `:174`, right items `:201`)
- Modify: `SettingsListVC.swift` (ledger `:248`, right items `:265`)

**Interfaces:**
- Consumes: `PrivacyMenu.menu(store:)` from Task 1.

**The pattern, applied identically to all four.** The ledger button gains
`menu:` alongside its existing `primaryAction:` — UIKit then taps the action and
long-presses the menu. The privacy button's construction is unchanged; only the
condition around adding it to `rightBarButtonItems` changes.

- [ ] **Step 1: Give the ledger button its menu.** In each of the four, the button becomes:

```swift
            let ledger = UIBarButtonItem(image: UIImage(systemName: "books.vertical"),
                                         primaryAction: UIAction { [weak self] _ in
                self?.router.showLedger = true
            },
                                         menu: PrivacyMenu.menu(store: store))
            ledger.accessibilityLabel = String(localized: "Ledger")
```

**`SettingsListVC` has no `router`** — check its existing action body and keep
whatever it already does for the tap; only add the `menu:` argument.

- [ ] **Step 2: Make the eye regular-width-only.** In `AccountsListVC`, `BudgetsListVC`, `ScheduledListVC`, wrap the privacy item where the toolbar is assembled:

```swift
        // The eye is iPad-only now. On iPhone the toolbar is cramped — three
        // items on Accounts and Budgets — and hiding amounts moved to a
        // long-press of the ledger button, which iPad does not have (its sidebar
        // lists Ledger itself). `onSelect != nil` IS "this list is a split-view
        // column", the same flag that gates the ledger button the other way.
        navigationItem.rightBarButtonItems = onSelect != nil ? [more, add, privacy] : [more, add]
```

Adjust the arrays per screen: Accounts and Budgets are `[more, add, …]`,
Scheduled is `[add, …]`, Settings is `[privacy]` only — so Settings becomes:

```swift
        navigationItem.rightBarButtonItems = showsLedgerControl ? [] : [privacy]
```

- [ ] **Step 3: Build.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`. An "unused variable `privacy`" warning on any screen
means its condition dropped the item on both paths — fix rather than silence.

- [ ] **Step 4: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: hold the ledger button to hide amounts; the eye leaves the iPhone

The privacy eye sat on all five primary screens, and on Accounts and Budgets the
right cluster was already three items. It comes off the iPhone entirely: hiding
amounts is now a long-press of the ledger button, which UIBarButtonItem supports
natively — tap runs the primary action, hold shows the menu.

iPad keeps the eye. It has no ledger button to hold (its sidebar lists Ledger
itself) and a wide toolbar has room. The condition is onSelect != nil, which
already means \"this list is a split-view column\" and already gates the ledger
button the other way — so the two cannot disagree about which shape they are in."
```

---

## Task 3: Insights, and the SwiftUI side

Two edits in one file cover every SwiftUI tab, because both controls are shared
components rather than per-tab code.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/Shell/AdaptiveShell.swift` — `LedgerBarButton` `:289-298`, `PrivacyToggleButton` `:300-312`

- [ ] **Step 1: Give the SwiftUI ledger button the same menu.**

```swift
struct LedgerBarButton: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        if sizeClass == .compact {
            // Tap opens the ledger picker, hold shows the menu — the same
            // contract the UIKit screens get from UIBarButtonItem's
            // primaryAction + menu pair. `Menu(primaryAction:)` is SwiftUI's
            // equivalent, so Insights behaves like the converted tabs.
            Menu {
                Button {
                    store.privacyMode.toggle()
                } label: {
                    Label(String(localized: "Hide Amounts"),
                          systemImage: store.privacyMode ? "checkmark" : "eye.slash")
                }
            } label: {
                Image(systemName: "books.vertical")
            } primaryAction: {
                router.showLedger = true
            }
            .accessibilityLabel("Ledger")
        }
    }
}
```

- [ ] **Step 2: Make the SwiftUI eye regular-width-only.**

```swift
/// The privacy-mode eye — iPad and Mac only now.
///
/// On iPhone the toolbar is cramped and hiding amounts moved to a long-press of
/// the ledger button (`LedgerBarButton`). iPad has no ledger button — its
/// sidebar lists Ledger itself — so the eye stays there, which is also where
/// there is room for it.
struct PrivacyToggleButton: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        if sizeClass != .compact {
            Button { store.privacyMode.toggle() } label: {
                Image(systemName: store.privacyMode ? "eye.slash" : "eye")
            }
            .accessibilityLabel("Privacy mode")
            .accessibilityValue(store.privacyMode ? "on" : "off")
        }
    }
}
```

- [ ] **Step 3: Build both targets.** Same command as Task 2 Step 3, plus confirm the macOS project still builds:

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchMac.xcodeproj -scheme FinchMac -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: both `BUILD SUCCEEDED`. On macOS `sizeClass` is `.regular`, so the eye
stays in the Mac toolbar — which is correct, and the reason this gate matters.

- [ ] **Step 4: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: Insights gets the same hold-menu, and the SwiftUI eye goes iPad-only

Two edits in one file rather than five, because both controls are shared
components: every SwiftUI tab picks them up without touching a tab file.

Menu(primaryAction:) is SwiftUI's equivalent of UIBarButtonItem's
primaryAction + menu pair, so Insights behaves exactly like the converted tabs.

On macOS sizeClass is .regular, so the Mac toolbar keeps its eye — which is why
the Mac build is part of this step and not an afterthought."
```

---

## Task 4: The visible home in Settings

The hold-menu is invisible. Without this row the feature does not exist for
anyone who was not told about it.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppUIKit/SettingsListVC.swift` — `SectionID` `:63`, the row enum `:100`, `applySnapshot` `:235`, and the delegate's selection handler

- [ ] **Step 1: Add the row.** It belongs in `.general`, beside "Appearance & Language" and "Security" — it is a display preference, not a data one. Reuse `"Privacy mode"` for the title (already translated: 隐私模式).

Add the case to the row enum with its title and an `eye.slash` symbol, and
include it in `.general`'s items in `applySnapshot`.

**Every row in this file is a `UIHostingConfiguration { Label(...) }` that pushes
a subpage** — there is no existing switch row, so the registration has to branch.
Keep the SwiftUI hosting approach the file already uses rather than introducing a
`UICellAccessory`:

```swift
            // Every other row is a Label that pushes a subpage; this one is a
            // TOGGLE and stays put. Branching here rather than adding a
            // UISwitch accessory keeps one rendering path for the list.
            if row == .privacy {
                cell.contentConfiguration = UIHostingConfiguration { [store] in
                    Toggle(isOn: Binding(get: { store.privacyMode },
                                         set: { store.privacyMode = $0 })) {
                        Label(row.title, systemImage: row.symbol)
                    }
                }
                cell.accessories = []
            } else {
                // …the existing Label configuration, unchanged…
            }
```

and exclude it from the push in `didSelectItemAt`, since it has nowhere to go:

```swift
        // The privacy row is a toggle, not a destination — the switch handles
        // the tap and there is no subpage behind it.
        guard row != .privacy else {
            collectionView.deselectItem(at: indexPath, animated: true)
            return
        }
```

- [ ] **Step 2: Keep the row in sync — and fix the doc comment that this breaks.**

`applySnapshot` is documented *"Applied once. Nothing here depends on the store,
so there is no republish to react to and no reconfigure to get right."* This row
makes that false. Correct the comment as part of the change, rather than leaving
a comment that actively misleads the next reader:

```swift
    /// Re-applied when `privacyMode` changes: the privacy row renders that state,
    /// so it is the one row here that DOES depend on the store. It used to be
    /// true that nothing did.
```

`SettingsListVC` already re-runs `configureToolbar()` on `store.$privacyMode`
(`:159-162`). Extend that sink to also re-apply the snapshot, or the row shows a
stale value after the hold-menu is used:

```swift
        store.$privacyMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureToolbar()
                // The row shows the same state the toolbar did, so it goes stale
                // the same way — and now it is the ONLY visible indicator on
                // iPhone, so a stale one is worse than a missing one.
                self?.applySnapshot()
            }
            .store(in: &cancellables)
```

- [ ] **Step 3: Build and run the app suite.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests test 2>&1 | grep -E "error:|Executed [0-9]+ tests"
```
Expected: 0 failures.

- [ ] **Step 4: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: Settings gets a privacy row — the visible home for a hidden gesture

Hiding amounts is a long-press of a button nobody has ever held, so without a
row in the place people look for settings the feature does not exist for anyone
who was not told about it. A row costs no toolbar space, which was the point.

The row re-applies on the privacyMode publisher for the same reason the toolbar
button always did — and it matters more now, because on iPhone this row is the
only visible indicator of the mode."
```

---

## Task 5: The UI test, and the gate

The eye disappearing from four screens is exactly the kind of change a unit test
cannot see.

**Files:**
- Modify: `ios/FinchApp/Tests/FinchAppUITests/SettingsToolbarUITests.swift` — it already pins the privacy toggle

- [ ] **Step 1: Read what that test currently asserts.**

```bash
grep -n "privacy\|Privacy" ios/FinchApp/Tests/FinchAppUITests/SettingsToolbarUITests.swift
```
It pins "Settings' Ledger control and privacy toggle" (`3159e22a`). On iPhone the
privacy toggle no longer exists there, so this test MUST change — and it is the
one that proves the eye really went.

- [ ] **Step 2: Retarget it.** Assert the compact expectation: no privacy bar button on Settings, and the ledger button present. Keep its ledger assertions untouched.

- [ ] **Step 3: Run the UI suite.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppUITests test 2>&1 | grep -E "error: -\[|Executed [0-9]+ tests"
```
Expected: 0 failures. Any OTHER UI test that reaches for the eye by
`"Privacy mode"` will fail here — that is the point of running the whole suite
rather than one class.

- [ ] **Step 4: Run the full gate.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  ./scripts/ci-local.sh --ui --all
```
Expected: `gate passed`. The base was verified green immediately before this
work, so any failure here is this branch's.

- [ ] **Step 5: Discard churn and confirm scope.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git status --short
git diff --stat origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/
```
Expected: `git status` silent; the second diff EMPTY.

- [ ] **Step 6: Commit, push, open the PR** against `feat/frontend`.

---

## Out of scope

- **An App Intent** for Back Tap / the Action Button. Considered and declined.
- **A gesture** (shake, tab-bar long-press). Considered and declined.
- **macOS chrome.** `FinchCommands` already has "Hide Amounts".
- **The iPad sidebar's Ledger row** gaining the same menu.

## Verification checklist

- [ ] `ci-local.sh --ui --all` prints `gate passed`
- [ ] No privacy eye on iPhone: Accounts, Budgets, Scheduled, Insights, Settings
- [ ] Holding the ledger button on each of those four UIKit screens shows "Hide Amounts", with a checkmark when on
- [ ] Tapping the ledger button still opens the ledger picker
- [ ] iPad still shows the eye, and has no ledger button
- [ ] macOS still shows the eye
- [ ] Settings' row reflects a change made from the hold-menu without reopening the screen
- [ ] `git status` shows no `.xcstrings` change — no key was added
- [ ] `git diff origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/` is empty
