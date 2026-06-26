# Widgets CP3 (interactive quick-add) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap any finch widget → app opens the Add-Transaction sheet.

**Architecture:** Path A deep link. App: a `finch` URL scheme + `DeepLinkRouter.handle(_:)` (`finch://add` → `showAddTransaction = true`) + `.onOpenURL` on the root, reusing the existing root Add sheet. Widget: `.widgetURL("finch://add")` on the 3 widgets. No engine/snapshot change.

**Tech Stack:** SwiftUI + WidgetKit (iOS 17), XcodeGen, XCTest.

## Global Constraints

- **No engine/snapshot change.** Reuse `DeepLinkRouter.showAddTransaction` + the root `.sheet(isPresented: $router.showAddTransaction)` (already presents `AddTransactionSheet`).
- `finch://add` is the only route in CP3 (plain add; no account pre-fill).
- **Must build iOS AND macOS (FinchMac).** The FinchApp build embeds FinchWidget. `xcodegen generate` first. FinchApp tests via `xcodebuild test`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift`, `ios/FinchApp/Sources/FinchApp/FinchApp.swift`, `ios/FinchApp/Info.plist`.
**Test:** `ios/FinchApp/Tests/FinchAppTests/DeepLinkRouterTests.swift` (new).
**Modify (widget):** `ios/FinchWidget/FinchWidget.swift`.

---

### Task 1: App wiring — URL scheme + `handle` + `onOpenURL`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/FinchApp.swift`
- Modify: `ios/FinchApp/Info.plist`
- Test: `ios/FinchApp/Tests/FinchAppTests/DeepLinkRouterTests.swift`

**Interfaces:**
- Produces: `DeepLinkRouter.handle(_ url: URL)` — `finch://add` sets `showAddTransaction = true`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/DeepLinkRouterTests.swift`:
```swift
import XCTest
@testable import FinchApp

@MainActor
final class DeepLinkRouterTests: XCTestCase {
    func test_handle_add_url_sets_showAddTransaction() {
        let r = DeepLinkRouter()
        XCTAssertFalse(r.showAddTransaction)
        r.handle(URL(string: "finch://add")!)
        XCTAssertTrue(r.showAddTransaction)
    }

    func test_handle_unknown_url_is_ignored() {
        let r = DeepLinkRouter()
        r.handle(URL(string: "finch://bogus")!)
        XCTAssertFalse(r.showAddTransaction)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/DeepLinkRouterTests 2>&1 | grep -iE "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL — `handle` is undefined.

- [ ] **Step 3: Add `handle(_:)` to `DeepLinkRouter`**

In `DeepLinkRouter.swift`, after `public func open(_ tab: AppTab) { selectedTab = tab }`, add:
```swift
    /// Handle a `finch://…` deep link (e.g. a widget tap). `finch://add` opens the Add sheet.
    public func handle(_ url: URL) {
        switch url.host {
        case "add": showAddTransaction = true
        default: break
        }
    }
```

- [ ] **Step 4: Register the URL scheme in `Info.plist`**

In `ios/FinchApp/Info.plist`, add this block inside the top-level `<dict>` (e.g. immediately before `<key>LSSupportsOpeningDocumentsInPlace</key>`):
```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.juchengquan.finch</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>finch</string>
			</array>
		</dict>
	</array>
```

- [ ] **Step 5: Add `.onOpenURL` to the root**

In `FinchApp.swift`, immediately after the `.onContinueUserActivity(CSSearchableItemActionType) { … }` modifier block (the closing `}` of that modifier, ~line 78), add:
```swift
            .onOpenURL { router.handle($0) }
```
(`router` is the `@StateObject private var router = DeepLinkRouter.shared` already in scope.)

- [ ] **Step 6: Run the test**

Run (same as Step 2). Expected: `** TEST SUCCEEDED **` (2 tests).

- [ ] **Step 7: Full FinchApp + FinchCore + macOS**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** TEST SUCCEEDED **`; FinchCore all pass; `** BUILD SUCCEEDED **`. (`onOpenURL` is cross-platform.)

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift \
        ios/FinchApp/Sources/FinchApp/FinchApp.swift \
        ios/FinchApp/Info.plist \
        ios/FinchApp/Tests/FinchAppTests/DeepLinkRouterTests.swift
git commit -m "feat(ios): finch:// URL scheme + onOpenURL → open Add (deep link)"
```

---

### Task 2: Widget tap target (`.widgetURL`)

**Files:**
- Modify: `ios/FinchWidget/FinchWidget.swift`

**Interfaces:**
- Consumes: the `finch://add` handling (Task 1).

- [ ] **Step 1: Add `.widgetURL` to the three widgets**

In `FinchWidget.swift`, append `.widgetURL(URL(string: "finch://add"))` to each widget's content view:

- `FinchWidget` (line ~95): `FinchWidgetView(entry: entry)` →
  ```swift
            FinchWidgetView(entry: entry).widgetURL(URL(string: "finch://add"))
  ```
- `AccountWidget` (line ~151): `AccountWidgetView(entry: entry)` →
  ```swift
            AccountWidgetView(entry: entry).widgetURL(URL(string: "finch://add"))
  ```
- `BudgetWidget` (line ~204): `BudgetWidgetView(entry: entry)` →
  ```swift
            BudgetWidgetView(entry: entry).widgetURL(URL(string: "finch://add"))
  ```

- [ ] **Step 2: Build iOS + macOS**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification on the simulator**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch
# Verify the URL route directly (simulates a widget tap):
xcrun simctl openurl "$IPHONE" "finch://add"
```
Expected: `finch://add` (or tapping a home/lock-screen finch widget) opens the app with the **Add Transaction** sheet presented. (The `simctl openurl` is a quick way to confirm the scheme + onOpenURL without the widget gallery.)

- [ ] **Step 4: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchWidget/FinchWidget.swift
git commit -m "feat(ios): widgets open Add on tap (widgetURL finch://add)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-27-ios-widgets-cp3-design.md`):
- `finch` URL scheme (Info.plist) + `DeepLinkRouter.handle` (`finch://add` → showAddTransaction) + `.onOpenURL` → Task 1. ✓
- Test: handle add-url → true, bogus → unchanged → Task 1 step 1. ✓
- `.widgetURL("finch://add")` on all 3 widgets → Task 2. ✓
- Reuses the root Add sheet; no engine change; build iOS+macOS → both tasks. ✓

**Placeholder scan:** No TBD/TODO; full code; concrete sim step (incl. `simctl openurl`). ✓

**Type consistency:** `DeepLinkRouter.handle(_ URL)` (public, @MainActor) called from `.onOpenURL { router.handle($0) }`; `showAddTransaction` already published + bound to the root sheet; `.widgetURL(URL?)` is a WidgetKit modifier on the content view; `DeepLinkRouter()` init is public (test). ✓

---

## Out of scope (later / Watch sub-project)

Account pre-fill (`finch://add?account=<id>`); deep links to other screens; a true in-widget silent write (needs DB in the App Group); the Watch complication + quick-add. This completes the widgets sub-project (CP1 + CP2 + CP3).
