# Settings Native Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the top-left gear *sheet* with a top-right gear that **native-pushes** Settings onto the current tab.

**Architecture:** One trigger (`router.showSettings`) drives a per-tab `navigationDestination(isPresented:)` (via a shared `.settingsPush()` modifier) so Settings pushes onto the active tab's `NavigationStack`. The gear sets the bool; the programmatic `.settings` route is converted to the bool in the shell; switching tabs clears it. The shell sheet is removed. iPad/Mac unchanged.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-22-settings-native-push-design.md`.

## Global Constraints

- iOS deployment target 17.0; local builds need `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After any source change, `cd ios && xcodegen generate` before building (generated `.xcodeproj`).
- Commits: **no `Co-Authored-By` trailer**.
- `SettingsBarButton` is **compact-only** (its `sizeClass == .compact` guard) — iPad/Mac never show it; their Settings stays a sidebar destination.
- This is view wiring (no unit tests); the gate is **build + manual sim**.
- Sim destination: `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

---

### Task 1: Native-push plumbing (modifier + shell + 5 tab toolbars)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/{LedgerTab,AccountsTab,BudgetsTab,ScheduledTab,InsightsTab}.swift`

**Interfaces — Produces:** `extension View { func settingsPush() -> some View }`.

- [ ] **Step 1: Add the `SettingsPush` modifier**

In `AdaptiveShell.swift`, add near `SettingsBarButton` (end of file):

```swift
/// Pushes Settings onto the enclosing NavigationStack when `router.showSettings`
/// is set (by the gear or a `.settings` route). Compact-only — iPad/Mac reach
/// Settings via the sidebar. `.navigationTitle` is set here because SettingsTab's
/// own title (inside MoreTabNavigationStack's conditional) doesn't surface
/// through `navigationDestination`.
private struct SettingsPush: ViewModifier {
    @EnvironmentObject private var router: DeepLinkRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationDestination(isPresented: Binding(
            get: { sizeClass == .compact && router.showSettings },
            set: { if !$0 { router.showSettings = false } })) {
            SettingsTab().navigationTitle("Settings")
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Apply inside a compact tab's NavigationStack so the top-right gear (and a
    /// `.settings` route) pushes Settings there.
    func settingsPush() -> some View { modifier(SettingsPush()) }
}
```

- [ ] **Step 2: Remove the Settings sheet**

In `AdaptiveShell.swift`, delete this block (around lines 53-66):

```swift
        // PROTOTYPE: Settings as a modal, opened by the top-left gear or a
        // `.settings` router target (deep link / ⌘K / intent).
        .sheet(isPresented: settingsSheet) {
            NavigationStack {
                SettingsTab()
                    #if os(iOS)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { settingsSheet.wrappedValue = false } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Close")
                        }
                    }
                    #endif
            }
        }
```

- [ ] **Step 3: Convert the `.settings` route to the bool + clear on tab switch**

In `AdaptiveShell.swift`, replace `syncFromRouter`:

```swift
    private func syncFromRouter(_ tab: AppTab) {
        guard tab != .settings else { return }
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: [])
        if result.selected != .more, selected != result.selected { selected = result.selected }
    }
```

with:

```swift
    private func syncFromRouter(_ tab: AppTab) {
        // A `.settings` route (deep link / ⌘K / intent) → push Settings on the
        // active tab; settle the bar back on a real primary tab.
        if tab == .settings {
            router.showSettings = true
            router.selectedTab = CompactTabRouting.appTab(for: selected) ?? .accounts
            return
        }
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: [])
        if result.selected != .more, selected != result.selected { selected = result.selected }
    }
```

Then in the same file's `.onChange(of: selected)` handler, add a reset so Settings can't linger on a tab you switched away from:

```swift
        .onChange(of: selected) { _, sel in
            router.showSettings = false
            if let tab = CompactTabRouting.routerTab(forSelected: sel, current: router.selectedTab) {
                router.selectedTab = tab
            }
        }
```

- [ ] **Step 4: Remove the now-unused `settingsSheet` binding**

In `AdaptiveShell.swift`, delete the entire `private var settingsSheet: Binding<Bool> { … }` computed property (around lines 86-100) — it's no longer referenced after Steps 2-3.

- [ ] **Step 5: Move the gear to the trailing edge (all 5 tabs)**

Run (flips placement in every tab that hosts the gear):

```bash
cd ios/FinchApp/Sources/FinchApp/Tabs
sed -i '' 's/placement: .topBarLeading) { SettingsBarButton()/placement: .topBarTrailing) { SettingsBarButton()/' \
  LedgerTab.swift AccountsTab.swift BudgetsTab.swift ScheduledTab.swift InsightsTab.swift
```

- [ ] **Step 6: Apply `.settingsPush()` inside each tab's NavigationStack**

`LedgerTab.swift` — replace:

```swift
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { SettingsBarButton() }
                }
```

with:

```swift
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { SettingsBarButton() }
                }
                .settingsPush()
```

`AccountsTab.swift` — after `.navigationTitle("Accounts")` add `.settingsPush()`:

```swift
            .navigationTitle("Accounts")
            .settingsPush()
```

`BudgetsTab.swift` — after `.navigationTitle("Budgets")`:

```swift
            .navigationTitle("Budgets")
            .settingsPush()
```

`ScheduledTab.swift` — after `.navigationTitle("Scheduled")`:

```swift
            .navigationTitle("Scheduled")
            .settingsPush()
```

`InsightsTab.swift` — after `.navigationTitle("Insights")`:

```swift
            .navigationTitle("Insights")
            .settingsPush()
```

- [ ] **Step 7: Build + run the full suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD FAILED|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (no logic removed; existing suites pass).

- [ ] **Step 8: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/LedgerTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): Settings as a top-right native push (replaces gear sheet)"
```

---

### Task 2: Manual simulator verification

**Files:** none. Reference: `ios/docs/simulator-ui-driving.md` (a 2nd sim may steal foreground — raise the iPhone 17 Pro window by name before taps).

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Gear is **top-right** on every tab (Ledger, Accounts, Budgets, Scheduled, Insights); no sheet/✕.
  - Tap gear → Settings **slides in from the right** with a **‹ Back** title bar (title reads "Settings"); Back (or left-edge swipe) returns to the same tab.
  - Open Settings, then tap another bottom-bar tab → Settings is dismissed (doesn't linger).
  - Trigger `.settings` (e.g. an `OpenScreenIntent`/deep link if available) → Settings pushes on the active tab.
  - Screenshot evidence: `xcrun simctl io $SIM screenshot /tmp/settings-push-<state>.png`.

- [ ] **Step 3 (no commit):** report results; if any check fails, return to Task 1.

---

## Notes
- One shared `router.showSettings` drives all five tabs' `navigationDestination(isPresented:)`. If the simultaneous (off-screen) pushes on inactive tabs misbehave in testing, gate each `.settingsPush()` by whether its tab is the active one (pass the active `CompactTab` in) — but the shared-bool form is expected to be fine since inactive stacks aren't visible and `selected`-change clears the bool.
- PR targets **`feat/frontend`**.
