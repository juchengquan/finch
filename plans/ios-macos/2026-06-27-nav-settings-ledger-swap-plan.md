# Swap Settings ↔ Ledger (compact nav) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On iPhone, make Settings a bottom-bar tab and reach the two-layer Ledger from the top-left corner control, launching the app on Accounts.

**Architecture:** A symmetric inversion of the app's existing "bar-tab vs corner-pushed screen" split. The pure routing (`CompactTabRouting`) flips first (Task 1, fully unit-tested), then the SwiftUI shell + router + call sites flip together (Task 2, one atomic compiling change verified by build + simulator).

**Tech Stack:** Swift / SwiftUI, XcodeGen project in `ios/`, XCTest (`FinchAppTests`). Spec: `plans/ios-macos/2026-06-27-nav-settings-ledger-swap-spec.md`.

## Global Constraints

- Scope is **compact (iPhone)** only. `SplitViewShell` / `MasterDetailShell` / `SectionSidebar` (iPad/Mac) are **unchanged**.
- Build **both** schemes before finishing: `FinchApp` (iOS) and `FinchMac` (macOS). The corner toolbar item stays iOS-only-guarded (`#if os(iOS)` + `sizeClass == .compact`).
- Corner control icon = `books.vertical`, accessibility label = `"Ledger"`. Settings tab uses `AppTab.settings` title/icon (`gear`).
- Launch/default tab = `.accounts`.
- Run all build/test/sim commands with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and from `ios/`. The `ios-build-launch` skill documents the exact commands; reuse it.
- No new dependencies. No change to `LedgerListView`/`LedgerDetailView` internals beyond what Task 2 §LedgerTab states.

---

### Task 1: Invert the pure `CompactTabRouting` mapping (+ tests)

`CompactTabRouting` is a pure, SwiftUI-free bridge with full unit coverage. Flip it first so the logic is proven before the shell changes. To keep the build green on its own commit, the `CompactTab` enum **gains** `.settings` and **keeps** `.ledger` for now (still referenced by `AdaptiveShell`); Task 2 removes the dead `.ledger` case after the shell stops using it.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift` (whole file)
- Test: `ios/FinchApp/Tests/FinchAppTests/CompactTabRoutingTests.swift` (whole file)

**Interfaces:**
- Produces (consumed by Task 2):
  - `enum CompactTab: Hashable { case ledger, accounts, budgets, scheduled, insights, settings, more }`
  - `CompactTabRouting.compactTab(for: AppTab) -> CompactTab` — `.settings→.settings`, `.accounts/.budgets/.scheduled/.insights→` self, `.ledger→.more`, `.activity→.accounts`
  - `CompactTabRouting.appTab(for: CompactTab) -> AppTab?` — primaries→self, `.settings→.settings`, `.ledger`/`.more→nil`
  - `CompactTabRouting.overflowTab(for: AppTab) -> AppTab?` — `.ledger→.ledger`, else `nil`
  - `sync(routerTab:currentPath:)` and `routerTab(forSelected:current:)` — unchanged shapes, new behavior via the maps above

- [ ] **Step 1: Rewrite the test file for the inverted mapping**

Replace the entire contents of `ios/FinchApp/Tests/FinchAppTests/CompactTabRoutingTests.swift` with:

```swift
import XCTest
@testable import FinchApp

final class CompactTabRoutingTests: XCTestCase {
    func test_primaryTabsMapToOwnSlot() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .budgets), .budgets)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .scheduled), .scheduled)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .insights), .insights)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .settings), .settings)
    }

    func test_activityMapsToAccounts() {   // the activity feed lives in the Accounts tab now
        XCTAssertEqual(CompactTabRouting.compactTab(for: .activity), .accounts)
    }

    func test_ledgerIsCornerPushedOverflow() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .ledger), .more)
    }

    func test_appTabForSlot() {
        XCTAssertEqual(CompactTabRouting.appTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.appTab(for: .budgets), .budgets)
        XCTAssertEqual(CompactTabRouting.appTab(for: .scheduled), .scheduled)
        XCTAssertEqual(CompactTabRouting.appTab(for: .insights), .insights)
        XCTAssertEqual(CompactTabRouting.appTab(for: .settings), .settings)
        XCTAssertNil(CompactTabRouting.appTab(for: .more))
    }

    func test_overflowTab() {
        XCTAssertEqual(CompactTabRouting.overflowTab(for: .ledger), .ledger)
        XCTAssertNil(CompactTabRouting.overflowTab(for: .settings))   // now a primary tab
        XCTAssertNil(CompactTabRouting.overflowTab(for: .accounts))
    }

    func test_sync_primaryClearsPath() {
        let r = CompactTabRouting.sync(routerTab: .budgets, currentPath: [.ledger])
        XCTAssertEqual(r.selected, .budgets)
        XCTAssertEqual(r.path, [])
    }

    func test_sync_overflowPushesLedger() {
        let r = CompactTabRouting.sync(routerTab: .ledger, currentPath: [])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.ledger])
    }

    func test_sync_preservesExistingOverflowPath() {
        let r = CompactTabRouting.sync(routerTab: .ledger, currentPath: [.ledger])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.ledger])
    }

    func test_sync_primaryFromOverflowClearsPath() {
        let r = CompactTabRouting.sync(routerTab: .settings, currentPath: [.ledger])
        XCTAssertEqual(r.selected, .settings)
        XCTAssertEqual(r.path, [])
    }

    func test_routerTab_primaryWhenChanged() {
        XCTAssertEqual(CompactTabRouting.routerTab(forSelected: .budgets, current: .accounts), .budgets)
    }

    func test_routerTab_settingsWhenChanged() {
        XCTAssertEqual(CompactTabRouting.routerTab(forSelected: .settings, current: .accounts), .settings)
    }

    func test_routerTab_nilWhenUnchanged() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .accounts, current: .accounts))
    }

    func test_routerTab_nilForMore() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .more, current: .accounts))
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/CompactTabRoutingTests 2>&1 | grep -iE "error:|fail|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL (e.g. `compactTab(for: .settings)` returns `.more`, not `.settings`; `overflowTab(for: .ledger)` returns `nil`).

- [ ] **Step 3: Replace `CompactTabRouting.swift` with the inverted mapping**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift` with:

```swift
/// The slots in the iPhone bottom tab bar. The five primaries are Accounts,
/// Budgets, Scheduled, Insights, Settings; `.more` is the corner-pushed overflow
/// role, now carrying the two-layer Ledger reached from the top-left control.
/// (Activity is not a bottom-bar tab — its feed lives inside Accounts.)
/// `.ledger` is retained only until AdaptiveShell stops referencing it (removed
/// in the shell-swap task). See plans/ios-macos/2026-06-27-nav-settings-ledger-swap-spec.md.
enum CompactTab: Hashable {
    case ledger, accounts, budgets, scheduled, insights, settings, more
}

/// Pure bridge logic between `DeepLinkRouter.selectedTab` (an `AppTab`) and the
/// compact bottom bar's `CompactTab` selection + the corner push path. Kept free
/// of SwiftUI so it is unit-testable. Settings is a primary slot; the Ledger is
/// the corner-pushed overflow.
enum CompactTabRouting {
    /// The bottom-bar slot to highlight for a given app tab. Ledger is corner-
    /// pushed (`.more`); Settings is a primary slot; the Activity feed lives in
    /// Accounts.
    static func compactTab(for tab: AppTab) -> CompactTab {
        switch tab {
        case .settings:  return .settings
        case .accounts:  return .accounts
        case .budgets:   return .budgets
        case .scheduled: return .scheduled
        case .insights:  return .insights
        case .ledger:    return .more        // corner-pushed overflow
        case .activity:  return .accounts    // the activity feed lives in the Accounts tab now
        }
    }

    /// The app tab a primary slot maps to, or `nil` for `.more` (corner-pushed)
    /// and the retired `.ledger` slot.
    static func appTab(for compact: CompactTab) -> AppTab? {
        switch compact {
        case .accounts:  return .accounts
        case .budgets:   return .budgets
        case .scheduled: return .scheduled
        case .insights:  return .insights
        case .settings:  return .settings
        case .ledger, .more: return nil
        }
    }

    /// The corner-pushed screen for a given app tab, or `nil` if it isn't one.
    static func overflowTab(for tab: AppTab) -> AppTab? {
        switch tab {
        case .ledger: return tab
        default: return nil
        }
    }

    /// Sync the compact UI to a (possibly programmatic) router selection. Returns
    /// the bottom-bar slot and the corner push path. If the target overflow screen
    /// is already the path tail, the path is preserved (don't stomp deeper state).
    static func sync(routerTab: AppTab, currentPath: [AppTab]) -> (selected: CompactTab, path: [AppTab]) {
        if let overflow = overflowTab(for: routerTab) {
            let path = currentPath.last == overflow ? currentPath : [overflow]
            return (.more, path)
        }
        return (compactTab(for: routerTab), [])
    }

    /// The value to write to `router.selectedTab` when the user taps a slot, or
    /// `nil` to leave it unchanged (tapped `.more`, or already matching).
    static func routerTab(forSelected selected: CompactTab, current routerTab: AppTab) -> AppTab? {
        guard let mapped = appTab(for: selected), mapped != routerTab else { return nil }
        return mapped
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/CompactTabRoutingTests 2>&1 | grep -iE "error:|fail|TEST SUCCEEDED|TEST FAILED"
```
Expected: PASS (all `CompactTabRoutingTests`). The app target still compiles (AdaptiveShell still references `.ledger`, which remains in the enum).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift \
        ios/FinchApp/Tests/FinchAppTests/CompactTabRoutingTests.swift
git commit -m "refactor(ios): invert CompactTabRouting (Settings primary, Ledger overflow)"
```

---

### Task 2: Swap the compact shell — Settings tab + corner Ledger control

Flip the SwiftUI shell, router, and every call site together (one atomic compiling change), then remove the now-dead `.ledger` enum slot. Verified by build (iOS + macOS) and on the simulator.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift:38,43`
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift` (TabView, defaults, sync, focusedTx, gear→ledger rename)
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift` (drop dead `.ledger` enum case)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/LedgerTab.swift` (becomes the pushed screen)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`, `BudgetsTab.swift`, `InsightsTab.swift`, `ScheduledTab.swift` (rename call sites)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift` (add corner Ledger control)
- Test: `ios/FinchApp/Tests/FinchAppTests/DeepLinkRouterTests.swift` (create if absent; default-tab assertion)

**Interfaces:**
- Consumes (from Task 1): the inverted `CompactTabRouting` API above.
- Produces: `LedgerBarButton` (View), `ledgerPush()` (View extension), `DeepLinkRouter.showLedger: Bool`, `DeepLinkRouter.selectedTab` defaulting to `.accounts`.

- [ ] **Step 1: Write a failing test for the new launch default**

Create `ios/FinchApp/Tests/FinchAppTests/DeepLinkRouterTests.swift`:

```swift
import XCTest
@testable import FinchApp

@MainActor
final class DeepLinkRouterTests: XCTestCase {
    func test_defaultTabIsAccounts() {
        XCTAssertEqual(DeepLinkRouter().selectedTab, .accounts)
    }

    func test_ledgerRouteFlagDefaultsOff() {
        XCTAssertFalse(DeepLinkRouter().showLedger)
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/DeepLinkRouterTests 2>&1 | grep -iE "error:|fail|cannot find|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL to compile/run — `showLedger` does not exist yet and the default tab is `.ledger`.

- [ ] **Step 3: Edit `DeepLinkRouter.swift`**

Change line 38 from:
```swift
    @Published public var selectedTab: AppTab = .ledger   // Ledger is the home/first tab
```
to:
```swift
    @Published public var selectedTab: AppTab = .accounts   // Accounts is the launch tab (Ledger moved to the corner control)
```

Change line 43 from:
```swift
    @Published public var showSettings = false          // top-left gear (compact, prototype)
```
to:
```swift
    @Published public var showLedger = false            // top-left corner control → push the two-layer Ledger (compact)
```

- [ ] **Step 4: Edit `AdaptiveShell.swift` — `TabBarShell` default, TabView, onChange, sync, focusedTx**

In `TabBarShell`, change the state default (line 29) from `= .ledger` to `= .accounts`:
```swift
    @State private var selected: CompactTab = .accounts
```

Replace the `TabView(selection:)` body (the five `tabContent(...)` slots) with — Ledger dropped, Settings added (Settings has no add-transaction FAB):
```swift
        TabView(selection: $selected) {
            tabContent(.accounts).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.accounts.title, systemImage: AppTab.accounts.icon) }
                .tag(CompactTab.accounts)
            tabContent(.budgets).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.budgets.title, systemImage: AppTab.budgets.icon) }
                .tag(CompactTab.budgets)
            tabContent(.scheduled).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.scheduled.title, systemImage: AppTab.scheduled.icon) }
                .tag(CompactTab.scheduled)
            tabContent(.insights).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.icon) }
                .tag(CompactTab.insights)
            tabContent(.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(CompactTab.settings)
        }
```

In `.onChange(of: selected)`, change `router.showSettings = false` to:
```swift
            router.showLedger = false
```

Replace `syncFromRouter(_:)` with the Ledger-push version:
```swift
    private func syncFromRouter(_ tab: AppTab) {
        // A `.ledger` route (deep link / ⌘K / intent / corner button) → push the
        // two-layer Ledger on the active tab; settle the bar on a real primary tab.
        if tab == .ledger {
            router.showLedger = true
            router.selectedTab = CompactTabRouting.appTab(for: selected) ?? .accounts
            return
        }
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: [])
        if result.selected != .more, selected != result.selected { selected = result.selected }
    }
```

In `focusedTx`, change the reset target (the line `if router.selectedTab == .activity { router.selectedTab = .ledger }`) to:
```swift
                    if router.selectedTab == .activity { router.selectedTab = .accounts }
```

- [ ] **Step 5: Edit `AdaptiveShell.swift` — rename the gear to the Ledger control**

Replace `struct SettingsBarButton` with:
```swift
/// The top-left Ledger control on every compact primary tab — pushes the
/// two-layer Ledger onto the current tab (via `.ledgerPush()`). Compact-only, so
/// the iPad/Mac sidebar (which lists Ledger itself) doesn't get a redundant
/// button. Drop one in each tab's `.toolbar`:
/// `ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }`.
struct LedgerBarButton: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        if sizeClass == .compact {
            Button { router.showLedger = true } label: { Image(systemName: "books.vertical") }
                .accessibilityLabel("Ledger")
        }
    }
}
```

Replace `private struct SettingsPush` and the `settingsPush()` extension with:
```swift
/// Pushes the two-layer Ledger onto the enclosing NavigationStack when
/// `router.showLedger` is set (by the corner button or a `.ledger` route).
/// Compact-only — iPad/Mac reach the Ledger via the sidebar.
private struct LedgerPush: ViewModifier {
    @EnvironmentObject private var router: DeepLinkRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationDestination(isPresented: Binding(
            get: { sizeClass == .compact && router.showLedger },
            set: { if !$0 { router.showLedger = false } })) {
            LedgerListView().navigationTitle("Ledger")
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Apply inside a compact tab's NavigationStack so the top-left Ledger control
    /// (and a `.ledger` route) pushes the Ledger there.
    func ledgerPush() -> some View { modifier(LedgerPush()) }
}
```

Also update the now-stale doc comment on `TabBarShell` (lines ~20-25) to describe the new bar (Accounts/Budgets/Scheduled/Insights/Settings) and the corner Ledger control — wording only, no behavior.

- [ ] **Step 6: Edit `CompactTabRouting.swift` — drop the dead `.ledger` slot**

Now that `AdaptiveShell` no longer references `CompactTab.ledger`, remove it. Change the enum to:
```swift
enum CompactTab: Hashable {
    case accounts, budgets, scheduled, insights, settings, more
}
```
and in `appTab(for:)` change `case .ledger, .more: return nil` to:
```swift
        case .more: return nil
```
(Update the enum doc comment to drop the `.ledger`-retained sentence.)

- [ ] **Step 7: Edit `LedgerTab.swift` — it is now the pushed screen**

Replace the whole file body so it no longer pushes itself (drop the `SettingsBarButton`/`settingsPush`); it stays the regular-sidebar container for the Ledger:
```swift
import SwiftUI
import FinchCore

/// The Ledger screen — a master→detail flow: a list of every ledger
/// (LedgerListView), drilling into a per-ledger detail (LedgerDetailView). On
/// iPhone it's pushed from the top-left corner control (`ledgerPush()`); on
/// iPad/Mac it's a sidebar section. The single global active ledger scopes the
/// rest of the app.
struct LedgerTab: View {
    var body: some View {
        NavigationStack {
            LedgerListView().navigationTitle("Ledger")
        }
    }
}
```

- [ ] **Step 8: Rename the call sites in the four primary tabs**

In each of `AccountsTab.swift`, `BudgetsTab.swift`, `InsightsTab.swift`, `ScheduledTab.swift`: change `.settingsPush()` → `.ledgerPush()` and `SettingsBarButton()` → `LedgerBarButton()`. (Each has exactly one of each; the `#if os(iOS)` around the `ToolbarItem(placement: .topBarLeading)` stays.)

- [ ] **Step 9: Add the corner Ledger control to `SettingsTab`**

In `SettingsTab.swift`, the `List` inside `MoreTabNavigationStack` ends with `.navigationTitle("Settings")`. Append the toolbar + push so Settings (now a primary tab) can also reach the Ledger:
```swift
            .navigationTitle("Settings")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }
                #endif
            }
            .ledgerPush()
```

- [ ] **Step 10: Build both platforms + run the full FinchAppTests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -only-testing:FinchAppTests 2>&1 | grep -iE "error:|fail|TEST SUCCEEDED|TEST FAILED"
```
Expected: both builds `BUILD SUCCEEDED`; `DeepLinkRouterTests` + `CompactTabRoutingTests` pass.

- [ ] **Step 11: Verify on the simulator**

Install + launch (see the `ios-build-launch` skill for the install/launch block), then confirm by eye:
- App launches on **Accounts** (not Ledger, not Settings).
- Bottom bar = **Accounts · Budgets · Scheduled · Insights · Settings**.
- The top-left **books.vertical** control on every tab pushes the Ledger list → tapping a ledger pushes its detail → back button returns. (No corner control content on iPad/Mac.)
- A `tx:` deep link / `-initialTab settings` still works (`xcrun simctl launch <udid> com.juchengquan.finch -initialTab settings` selects the Settings tab; `-initialTab ledger` opens the corner push).

- [ ] **Step 12: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift \
        ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift \
        ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/LedgerTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift \
        ios/FinchApp/Tests/FinchAppTests/DeepLinkRouterTests.swift
git commit -m "feat(ios): swap Settings <-> Ledger in compact nav (Settings tab + corner Ledger)"
```

---

## Self-Review

**1. Spec coverage:**
- Target bar / Settings tab / launch on Accounts → Task 2 Steps 4, 3. ✅
- Corner Ledger control (`books.vertical`, "Ledger", pushes two-layer Ledger) → Task 2 Steps 5, 9. ✅
- `CompactTabRouting` inversion + tests → Task 1. ✅
- `DeepLinkRouter` (`showSettings`→`showLedger`, default `.accounts`, routes) → Task 2 Steps 1-3. ✅ (`.settings` is now a normal slot — no special-case needed; `.ledger` handled in `syncFromRouter`.)
- 5 primary tabs' toolbars (incl. Settings) → Task 2 Steps 8, 9. ✅
- LedgerTab re-home (push `LedgerListView`, retire wrapper's gear) → Task 2 Step 7 + the `ledgerPush()` in Step 5. ✅
- Tests updated → Task 1 Step 1, Task 2 Step 1. ✅
- iPad/Mac unchanged → no task touches `SplitViewShell`/`MasterDetailShell`/`SectionSidebar`. ✅
- Build both platforms → Task 2 Step 10. ✅

**2. Placeholder scan:** none — every code step shows complete code; commands have expected output.

**3. Type consistency:** `showLedger`, `LedgerBarButton`, `ledgerPush()`, `CompactTab` cases (`accounts/budgets/scheduled/insights/settings/more` after Task 2), and `CompactTabRouting` signatures are used identically across Task 1 (produces) and Task 2 (consumes). `selectedTab` default `.accounts` asserted in the Task 2 Step 1 test and set in Step 3.
