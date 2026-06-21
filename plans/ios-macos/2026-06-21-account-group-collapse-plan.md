# Collapsible Account Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users collapse/expand each account group on the iOS Accounts tab, with state persisted per group.

**Architecture:** A small `UserDefaults`-backed helper (`AccountGroupCollapse`) stores the set of *collapsed* group names (default absent = expanded). `AccountsTab.groupedSections` (shared by the iPhone and iPad layouts) gains a tappable, chevroned section header that toggles the group and conditionally renders its rows.

**Tech Stack:** Swift / SwiftUI, XcodeGen (`.xcodeproj` is generated), XCTest.

Spec: `plans/ios-macos/2026-06-21-account-group-collapse-design.md`.

## Global Constraints

- iOS deployment target **26.0**.
- Local builds require `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After creating a source file, regenerate the project: `cd ios && xcodegen generate` (the `.xcodeproj` is gitignored/generated).
- New types are `internal` (no access modifier) so `@testable import FinchApp` can see them.
- Git commits: **no `Co-Authored-By` trailer**.
- Group identity is the group **name** `String` (`store.accountGroupsOrdered: [String]`, `store.accounts(in:)`).
- Simulator destination for build/test:
  `-destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901'`
  (or any booted iPhone sim from `xcrun simctl list devices booted`).

---

### Task 1: `AccountGroupCollapse` persistence helper + tests

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/AccountGroupCollapse.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/AccountGroupCollapseTests.swift`

**Interfaces:**
- Produces:
  - `enum AccountGroupCollapse` with:
    - `static let key: String`
    - `static func collapsed(_ defaults: UserDefaults = .standard) -> Set<String>`
    - `static func isCollapsed(_ group: String, _ defaults: UserDefaults = .standard) -> Bool`
    - `static func setCollapsed(_ group: String, _ collapsed: Bool, _ defaults: UserDefaults = .standard)`

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/AccountGroupCollapseTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class AccountGroupCollapseTests: XCTestCase {
    private let suite = "test.AccountGroupCollapse"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_defaultIsExpanded() {
        XCTAssertTrue(AccountGroupCollapse.collapsed(defaults).isEmpty)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("Savings", defaults))
    }

    func test_setCollapsedTrue() {
        AccountGroupCollapse.setCollapsed("Savings", true, defaults)
        XCTAssertTrue(AccountGroupCollapse.isCollapsed("Savings", defaults))
        XCTAssertEqual(AccountGroupCollapse.collapsed(defaults), ["Savings"])
    }

    func test_setCollapsedFalseRemoves() {
        AccountGroupCollapse.setCollapsed("Savings", true, defaults)
        AccountGroupCollapse.setCollapsed("Savings", false, defaults)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("Savings", defaults))
        XCTAssertTrue(AccountGroupCollapse.collapsed(defaults).isEmpty)
    }

    func test_multipleGroupsIndependent() {
        AccountGroupCollapse.setCollapsed("A", true, defaults)
        AccountGroupCollapse.setCollapsed("B", true, defaults)
        AccountGroupCollapse.setCollapsed("A", false, defaults)
        XCTAssertFalse(AccountGroupCollapse.isCollapsed("A", defaults))
        XCTAssertTrue(AccountGroupCollapse.isCollapsed("B", defaults))
    }

    func test_setCollapsedTrueIdempotent() {
        AccountGroupCollapse.setCollapsed("A", true, defaults)
        AccountGroupCollapse.setCollapsed("A", true, defaults)
        XCTAssertEqual(AccountGroupCollapse.collapsed(defaults), ["A"])
    }
}
```

- [ ] **Step 2: Regenerate project and run the test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901' \
  -only-testing:FinchAppTests/AccountGroupCollapseTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL — `cannot find 'AccountGroupCollapse' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `ios/FinchApp/Sources/FinchApp/Common/AccountGroupCollapse.swift`:

```swift
import Foundation

/// Persists which Accounts-tab groups are *collapsed* (keyed by group name) in
/// UserDefaults. Storing the collapsed set — not the expanded set — makes the
/// default (absent) expanded, so untouched and newly-created groups show open.
/// Mirrors the `NotificationPrefs` UserDefaults pattern; `defaults` is injectable
/// for tests.
enum AccountGroupCollapse {
    static let key = "finch.accounts.collapsedGroups"

    static func collapsed(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.array(forKey: key) as? [String] ?? [])
    }

    static func isCollapsed(_ group: String, _ defaults: UserDefaults = .standard) -> Bool {
        collapsed(defaults).contains(group)
    }

    static func setCollapsed(_ group: String, _ collapsed isCollapsed: Bool, _ defaults: UserDefaults = .standard) {
        var set = self.collapsed(defaults)
        if isCollapsed { set.insert(group) } else { set.remove(group) }
        defaults.set(Array(set), forKey: key)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901' \
  -only-testing:FinchAppTests/AccountGroupCollapseTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/AccountGroupCollapse.swift \
        ios/FinchApp/Tests/FinchAppTests/AccountGroupCollapseTests.swift
git commit -m "feat(ios): AccountGroupCollapse — persist collapsed account groups"
```

---

### Task 2: Collapsible group headers in `AccountsTab`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`

**Interfaces:**
- Consumes: `AccountGroupCollapse` (Task 1); existing `store.accountGroupsOrdered`, `store.accounts(in:)`, `store.subtotalDisplay(for:)`, `moveAccounts(in:from:to:)`.

- [ ] **Step 1: Add the collapsed-state property**

In `AccountsTab` (the `@State` block, currently ending at `errorMessage`), add after the `errorMessage` line (around line 27):

```swift
    @State private var collapsedGroups: Set<String> = AccountGroupCollapse.collapsed()
```

(Place it before the `#if os(iOS) … editMode … #endif` block. It is not platform-gated.)

- [ ] **Step 2: Replace `groupedSections` group loop with collapsible sections**

Find this exact block in `groupedSections` (around lines 118-129):

```swift
        ForEach(store.accountGroupsOrdered, id: \.self) { groupName in
            Section {
                ForEach(store.accounts(in: groupName)) { account in row(account) }
                    .onMove { moveAccounts(in: groupName, from: $0, to: $1) }
            } header: {
                HStack {
                    Text(groupName)
                    Spacer()
                    Text(store.subtotalDisplay(for: groupName))
                }
            }
        }
```

Replace it with:

```swift
        ForEach(store.accountGroupsOrdered, id: \.self) { groupName in
            Section {
                if !collapsedGroups.contains(groupName) {
                    ForEach(store.accounts(in: groupName)) { account in row(account) }
                        .onMove { moveAccounts(in: groupName, from: $0, to: $1) }
                }
            } header: {
                Button {
                    toggleGroup(groupName)
                } label: {
                    HStack {
                        Image(systemName: collapsedGroups.contains(groupName) ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(groupName)
                        Spacer()
                        Text(store.subtotalDisplay(for: groupName))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
```

- [ ] **Step 3: Add the `toggleGroup` helper**

Immediately after the `groupedSections` function's closing brace (before `rowActions`, around line 137), add:

```swift
    /// Toggle a group's collapsed state and persist it.
    private func toggleGroup(_ group: String) {
        let nowCollapsed = !collapsedGroups.contains(group)
        withAnimation {
            if nowCollapsed { collapsedGroups.insert(group) } else { collapsedGroups.remove(group) }
        }
        AccountGroupCollapse.setCollapsed(group, nowCollapsed)
    }
```

- [ ] **Step 4: Build and run the full unit suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,id=9500E54A-BC34-42E1-BC02-BC5E906B6901' 2>&1 | grep -E "error:|BUILD FAILED|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (AccountGroupCollapse + all existing suites pass).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift
git commit -m "feat(ios): collapsible account groups on the Accounts tab"
```

---

### Task 3: Manual simulator verification

**Files:** none (verification only). Reference: `ios/docs/simulator-ui-driving.md`.

- [ ] **Step 1: Install + launch on a booted iPhone sim**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app 2>/dev/null | head -1)
xcrun simctl install $SIM "$APP"
xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify behavior (screenshot each)**

On the Accounts tab (raise the iPhone 17 Pro window before scripted taps; re-read its position — it drifts):
  - Tap a group header → its account rows hide, the chevron flips to `chevron.right`, and the **subtotal stays visible** on the header.
  - Tap again → rows reappear, chevron back to `chevron.down`.
  - Collapse one group, switch to another tab and back → that group stays collapsed.
  - Relaunch the app → the collapsed group is still collapsed (persistence).
  - `xcrun simctl io $SIM screenshot /tmp/collapse-<state>.png` for evidence.

- [ ] **Step 3 (no commit):** Report results with screenshots. If any check fails, return to Task 2.

---

## Notes for the implementer

- The environment may have a **second simulator booted** by another session; raise the **iPhone 17 Pro** window explicitly (`AXRaise`) before scripted taps, and re-read the window position before each tap. See `ios/docs/simulator-ui-driving.md`.
- Work in the existing worktree/branch `feat/ios-account-group-collapse` (off `origin/feat/frontend`). Open the PR against **`feat/frontend`**.
