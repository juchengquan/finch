# Custom Compact "More" Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftUI's system "More" tab on iPhone with a custom More tab so Scheduled & Settings keep their navigation titles and a single back button.

**Architecture:** `TabBarShell` (compact width) renders 5 items — 4 primary tabs + a custom More tab that is a real `NavigationStack` listing Scheduled & Settings. A pure, unit-tested routing type (`CompactTabRouting`) bridges `DeepLinkRouter.selectedTab` ↔ the bottom-bar selection + the More tab's push path, so intents/notifications/⌘K still land on the right screen. iPad/Mac (`SplitViewShell`) is untouched.

**Tech Stack:** Swift / SwiftUI, XcodeGen (`.xcodeproj` is generated), XCTest.

Spec: `plans/ios-macos/2026-06-21-compact-more-tab-design.md`.

## Global Constraints

- iOS deployment target **26.0** (simulator destination below).
- Local builds require `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After creating/removing any source file, regenerate the project: `cd ios && xcodegen generate` (the `.xcodeproj` is gitignored/generated).
- New types are `internal` (no access modifier) so `@testable import FinchApp` can see them; `AppTab` is already `public`.
- Git commits: **no `Co-Authored-By` trailer**.
- Do not modify `AppTab`, `MoreTabNavigationStack`, or `SplitViewShell`.
- Simulator destination for all build/test commands:
  `-destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901'`
  (or any booted iPhone sim — resolve via `xcrun simctl list devices booted`).

---

### Task 1: Pure routing logic (`CompactTabRouting`) + tests

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/CompactTabRoutingTests.swift`

**Interfaces:**
- Consumes: `AppTab` (public enum: `.accounts .activity .budgets .insights .scheduled .settings`) from `DeepLink/DeepLinkRouter.swift`.
- Produces:
  - `enum CompactTab: Hashable { case accounts, activity, budgets, insights, more }`
  - `enum CompactTabRouting` with:
    - `static func compactTab(for: AppTab) -> CompactTab`
    - `static func appTab(for: CompactTab) -> AppTab?`
    - `static func overflowTab(for: AppTab) -> AppTab?`
    - `static func sync(routerTab: AppTab, currentPath: [AppTab]) -> (selected: CompactTab, path: [AppTab])`
    - `static func routerTab(forSelected: CompactTab, current: AppTab) -> AppTab?`

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/CompactTabRoutingTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class CompactTabRoutingTests: XCTestCase {
    func test_primaryTabsMapToOwnSlot() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .activity), .activity)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .budgets), .budgets)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .insights), .insights)
    }

    func test_overflowTabsMapToMore() {
        XCTAssertEqual(CompactTabRouting.compactTab(for: .scheduled), .more)
        XCTAssertEqual(CompactTabRouting.compactTab(for: .settings), .more)
    }

    func test_appTabForSlot() {
        XCTAssertEqual(CompactTabRouting.appTab(for: .accounts), .accounts)
        XCTAssertEqual(CompactTabRouting.appTab(for: .insights), .insights)
        XCTAssertNil(CompactTabRouting.appTab(for: .more))
    }

    func test_overflowTab() {
        XCTAssertEqual(CompactTabRouting.overflowTab(for: .settings), .settings)
        XCTAssertEqual(CompactTabRouting.overflowTab(for: .scheduled), .scheduled)
        XCTAssertNil(CompactTabRouting.overflowTab(for: .accounts))
    }

    func test_sync_primaryClearsPath() {
        let r = CompactTabRouting.sync(routerTab: .budgets, currentPath: [.settings])
        XCTAssertEqual(r.selected, .budgets)
        XCTAssertEqual(r.path, [])
    }

    func test_sync_overflowPushesScreen() {
        let r = CompactTabRouting.sync(routerTab: .settings, currentPath: [])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.settings])
    }

    func test_sync_preservesExistingOverflowPath() {
        let r = CompactTabRouting.sync(routerTab: .settings, currentPath: [.settings])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.settings])
    }

    func test_sync_switchesBetweenOverflowScreens() {
        let r = CompactTabRouting.sync(routerTab: .scheduled, currentPath: [.settings])
        XCTAssertEqual(r.selected, .more)
        XCTAssertEqual(r.path, [.scheduled])
    }

    func test_routerTab_primaryWhenChanged() {
        XCTAssertEqual(CompactTabRouting.routerTab(forSelected: .activity, current: .accounts), .activity)
    }

    func test_routerTab_nilWhenUnchanged() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .accounts, current: .accounts))
    }

    func test_routerTab_nilForMore() {
        XCTAssertNil(CompactTabRouting.routerTab(forSelected: .more, current: .accounts))
    }
}
```

- [ ] **Step 2: Regenerate project and run the test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901' \
  -only-testing:FinchAppTests/CompactTabRoutingTests 2>&1 | grep -E "error:|Compiling|FAIL|PASS|** TEST"
```
Expected: FAIL — `cannot find 'CompactTabRouting' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift`:

```swift
import Foundation

/// The five slots in the iPhone bottom tab bar. The first four mirror `AppTab`;
/// `.more` is the custom overflow tab hosting Scheduled & Settings — replacing
/// SwiftUI's system "More" tab (which dropped titles / doubled the back button).
/// See plans/ios-macos/2026-06-21-compact-more-tab-design.md.
enum CompactTab: Hashable {
    case accounts, activity, budgets, insights, more
}

/// Pure bridge logic between `DeepLinkRouter.selectedTab` (an `AppTab`) and the
/// compact bottom bar's `CompactTab` selection + the More tab's push path. Kept
/// free of SwiftUI so it is unit-testable (mirrors `LockDecision`).
enum CompactTabRouting {
    /// The bottom-bar slot to highlight for a given app tab. Scheduled & Settings
    /// live under `.more`.
    static func compactTab(for tab: AppTab) -> CompactTab {
        switch tab {
        case .accounts: return .accounts
        case .activity: return .activity
        case .budgets:  return .budgets
        case .insights: return .insights
        case .scheduled, .settings: return .more
        }
    }

    /// The app tab a primary slot maps to, or `nil` for `.more` (no single tab).
    static func appTab(for compact: CompactTab) -> AppTab? {
        switch compact {
        case .accounts: return .accounts
        case .activity: return .activity
        case .budgets:  return .budgets
        case .insights: return .insights
        case .more:     return nil
        }
    }

    /// The overflow screen to push in the More tab for a given app tab, or `nil`
    /// if it isn't an overflow screen.
    static func overflowTab(for tab: AppTab) -> AppTab? {
        switch tab {
        case .scheduled, .settings: return tab
        default: return nil
        }
    }

    /// Sync the compact UI to a (possibly programmatic) router selection. Returns
    /// the bottom-bar slot and the More tab's push path. If the target overflow
    /// screen is already the path tail, the path is preserved (don't stomp a
    /// deeper navigation state).
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

- [ ] **Step 4: Run the test to verify it passes**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901' \
  -only-testing:FinchAppTests/CompactTabRoutingTests 2>&1 | grep -E "error:|** TEST (SUCCEEDED|FAILED)"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/CompactTabRouting.swift \
        ios/FinchApp/Tests/FinchAppTests/CompactTabRoutingTests.swift
git commit -m "feat(ios): pure CompactTabRouting bridge for the custom More tab"
```

---

### Task 2: Custom More tab root view (`MoreTabRoot`)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Shell/MoreTabRoot.swift`

**Interfaces:**
- Consumes: `AppTab` (`.title`, `.icon`, `.scheduled`, `.settings`); `ScheduledTab`, `SettingsTab` views.
- Produces: `struct MoreTabRoot: View` with `@Binding var path: [AppTab]`.

- [ ] **Step 1: Write the implementation**

Create `ios/FinchApp/Sources/FinchApp/Shell/MoreTabRoot.swift`:

```swift
import SwiftUI

/// The custom "More" tab root (compact width). A real `NavigationStack` listing
/// the overflow destinations (Scheduled, Settings) so they push with their own
/// titles and a single back button — replacing SwiftUI's system "More" tab.
/// `ScheduledTab`/`SettingsTab` use `MoreTabNavigationStack`, which is a no-op in
/// compact width, so their `.navigationTitle` attaches to this stack.
struct MoreTabRoot: View {
    @Binding var path: [AppTab]

    private static let overflow: [AppTab] = [.scheduled, .settings]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(Self.overflow, id: \.self) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: AppTab.self) { tab in
                destination(for: tab)
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .scheduled: ScheduledTab()
        case .settings:  SettingsTab()
        default:         EmptyView()
        }
    }
}
```

- [ ] **Step 2: Regenerate project and verify it builds**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/MoreTabRoot.swift
git commit -m "feat(ios): MoreTabRoot — custom More tab NavigationStack"
```

---

### Task 3: Rewrite `TabBarShell` to use the 5-slot bar + bridge

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift` (the `TabBarShell` struct only).

**Interfaces:**
- Consumes: `CompactTab`, `CompactTabRouting` (Task 1); `MoreTabRoot` (Task 2); `tabContent(_:)` (existing free func in this file); `DeepLinkRouter`.
- Produces: revised `struct TabBarShell` (same name/role).

- [ ] **Step 1: Replace the `TabBarShell` struct**

Find the existing struct in `AdaptiveShell.swift`:

```swift
/// The iPhone/compact shell — the existing bottom tab bar (Phase 1.0/1.5/2),
/// driven by the shared `DeepLinkRouter` so deep links / intents select tabs.
struct TabBarShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 })) {
            ForEach(AppTab.allCases) { tab in
                tabContent(tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
    }
}
```

Replace it entirely with:

```swift
/// The iPhone/compact shell — a five-slot bottom bar: four primary tabs plus a
/// custom More tab (`MoreTabRoot`) that hosts Scheduled & Settings. This avoids
/// SwiftUI's system "More" overflow (which dropped titles / doubled the back
/// button on those screens). `CompactTabRouting` bridges the bar selection and
/// the More tab's push path to the shared `DeepLinkRouter`, so deep links /
/// intents / notifications / ⌘K still land on the right screen.
struct TabBarShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @State private var selected: CompactTab = .accounts
    @State private var morePath: [AppTab] = []

    var body: some View {
        TabView(selection: $selected) {
            tabContent(.accounts)
                .tabItem { Label(AppTab.accounts.title, systemImage: AppTab.accounts.icon) }
                .tag(CompactTab.accounts)
            tabContent(.activity)
                .tabItem { Label(AppTab.activity.title, systemImage: AppTab.activity.icon) }
                .tag(CompactTab.activity)
            tabContent(.budgets)
                .tabItem { Label(AppTab.budgets.title, systemImage: AppTab.budgets.icon) }
                .tag(CompactTab.budgets)
            tabContent(.insights)
                .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.icon) }
                .tag(CompactTab.insights)
            MoreTabRoot(path: $morePath)
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(CompactTab.more)
        }
        .onAppear { syncFromRouter(router.selectedTab) }
        .onChange(of: router.selectedTab) { _, tab in syncFromRouter(tab) }
        .onChange(of: selected) { _, sel in
            if let tab = CompactTabRouting.routerTab(forSelected: sel, current: router.selectedTab) {
                router.selectedTab = tab
            }
        }
    }

    /// Mirror a (possibly programmatic) router selection onto the bar + More path.
    private func syncFromRouter(_ tab: AppTab) {
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: morePath)
        if selected != result.selected { selected = result.selected }
        if morePath != result.path { morePath = result.path }
    }
}
```

- [ ] **Step 2: Build and run the full unit suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901' 2>&1 | grep -E "error:|BUILD FAILED|** TEST (SUCCEEDED|FAILED)"
```
Expected: `** TEST SUCCEEDED **` (CompactTabRouting + existing suites all pass).

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift
git commit -m "feat(ios): TabBarShell uses a custom More tab (no system overflow)"
```

---

### Task 4: Manual simulator verification

**Files:** none (verification only). Reference: `ios/docs/simulator-ui-driving.md`.

- [ ] **Step 1: Install the build on a booted iPhone sim**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(find ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"
xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify the bottom bar and screens (screenshot each)**

Drive via scripted taps (raise the target window first — see the note). Confirm:
  - Bottom bar shows **Accounts · Activity · Budgets · Insights · More** (no system "More" list-of-lists; our More is a normal NavigationStack with a "More" title).
  - **More → Scheduled**: single `‹ More` back button **and** a "Scheduled" title.
  - **More → Settings**: single `‹ More` back button **and** a "Settings" title.
  - **Settings → Manage ledgers** and **Settings → Rules** (Power Tools): single back + title.
  - Capture screenshots: `xcrun simctl io $SIM screenshot /tmp/verify-<screen>.png`.

- [ ] **Step 3: Verify programmatic routing still lands correctly**

```bash
# OpenScreenIntent / notification path: select Settings via the router.
# Easiest deterministic check: trigger the Settings command from ⌘K is desktop-only,
# so verify via a notification-style deep link if available, otherwise confirm
# manually that tapping a scheduled reminder (if present) opens More → Scheduled.
```
Confirm the app switches to **More** with the right screen pushed (title + single back).

- [ ] **Step 4 (no commit):** Report results with screenshots. If any check fails, return to the relevant task.

---

## Notes for the implementer

- The environment may have a **second simulator booted** by another session; raise the **iPhone 17 Pro** window explicitly before scripted taps (`AXRaise`), and re-read the window position before each tap (it drifts). See `ios/docs/simulator-ui-driving.md`.
- Do the work in the existing worktree/branch `fix/ios-custom-more-tab` (off `origin/feat/frontend`). Open the PR against **`feat/frontend`**.
