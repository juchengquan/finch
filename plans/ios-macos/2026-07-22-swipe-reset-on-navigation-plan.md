# Swipe-action reset on navigation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every `List` carrying `.swipeActions` closes any open swipe-action row when the user navigates away and returns; the five long transaction feeds also preserve scroll position across that reset.

**Architecture:** One shared file `Common/SwipeReset.swift`. **Component 1** — a `resetsSwipeOnNavigation(enabled:)` view modifier that bumps a private token on `.onDisappear`, changing the `List`'s `.id` so SwiftUI rebuilds it fresh (swipes closed) off-screen. **Component 2** — for feeds, a pure `SwipeReset.topVisibleID(order:visible:)` helper, a `tracksTopRow(...)` row hook that keeps a live top-visible anchor, and a `resetsSwipeAndRestoresScroll(...)` List modifier that (inside a `ScrollViewReader`) rebuilds on leave and async-restores the frozen anchor on return.

**Tech Stack:** SwiftUI (`List`, `.swipeActions`, `ScrollViewReader`, `ViewModifier`), XcodeGen-generated project, XCTest (`FinchAppTests`).

## Global Constraints

- **Deployment floor: iOS 17.0 / macOS 14.0** (`ios/project.yml:4-7`, `ios/Package.swift:9`). Every new modifier MUST compile on macOS — the `FinchMac` target shares these sources. No new API above iOS 17.
- **`.scrollPosition(id:)` is forbidden** for scroll restoration — it compiles at iOS 17 but does not reliably track/restore on `List` (disproven on-device). Use the manual anchor approach only.
- **Do not modify `txnSwipeActions`** (`Common/TxnSwipeActions.swift`) or any swipe visuals/actions. Only navigation-reset + scroll-restoration are added.
- **Do not touch `EditTransactionSheet.swift`** — its receipt list is a `Form` in a modal sheet (dismissed, not returned-to); out of scope.
- **The rebuild must be gated off while an in-list selection/edit mode is active** — a rebuild drops `selected`/`kbSel`/split-view selection. Use the exact `enabled:` expression given per screen.
- **Commit style:** no `Co-Authored-By` trailer.
- **Phase 1 (Tasks 1–4) is independently mergeable** before Phase 2 (Tasks 5–8) begins.

## Commands (referenced by name in steps)

All run from the worktree. Set the environment once per shell:

- **ENV:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- **XGEN** (after adding/removing files): `cd /tmp/finch-swipe-reset/ios && xcodegen generate`
- **BUILD_IOS:** `cd /tmp/finch-swipe-reset/ios && xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,id=6A01D29F-FBCB-4B97-9080-522192E4D6DD' -derivedDataPath /tmp/finch-swipe-reset/dd build 2>&1 | tail -3`
- **BUILD_MAC:** `cd /tmp/finch-swipe-reset/ios && xcodebuild -project FinchApp.xcodeproj -scheme FinchMac -derivedDataPath /tmp/finch-swipe-reset/dd build 2>&1 | tail -3`
- **TEST_SWIPE:** `cd /tmp/finch-swipe-reset/ios && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,id=6A01D29F-FBCB-4B97-9080-522192E4D6DD' -derivedDataPath /tmp/finch-swipe-reset/dd -only-testing:FinchAppTests/SwipeResetTests 2>&1 | tail -15`
- **INSTALL_LAUNCH** (for manual checks): install `/tmp/finch-swipe-reset/dd/Build/Products/Debug-iphonesimulator/FinchApp.app` to sim `6A01D29F-FBCB-4B97-9080-522192E4D6DD` and launch `com.juchengquan.finch`.

`6A01D29F-FBCB-4B97-9080-522192E4D6DD` is this session's iOS-17 simulator (`ios-finch2`); any booted iOS-17 sim works — substitute its UDID.

**Manual reset check (used verbatim in every application task):** launch the app, open the named screen, swipe a row open, navigate away (switch tabs via the tab bar, or push a detail and use Back — a control that does *not* touch the list), return, and confirm the row is closed. Tapping a *different row* is not a valid check — that already closes the swipe.

---

# PHASE 1 — short lists (Tasks 1–4). Mergeable on completion.

## Task 1: Shared modifier (Component 1) + first use (HoldingsView)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/SwipeReset.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/HoldingsView.swift` (List opens line 30, closes line 42; no trailing modifiers)

**Interfaces:**
- Produces: `func resetsSwipeOnNavigation(enabled: Bool = true) -> some View` (extension on `View`).

- [ ] **Step 1: Create the shared file with Component 1 only**

Create `ios/FinchApp/Sources/FinchApp/Common/SwipeReset.swift`:

```swift
import SwiftUI

extension View {
    /// Closes any open swipe-action row when this view leaves the screen and returns, by
    /// rebuilding the view's identity (`.id`) while it is off-screen (so the rebuild is invisible).
    /// Apply to a `List` that has `.swipeActions`.
    ///
    /// SwiftUI exposes no API to close an open swipe; a fresh `.id` is the only mechanism. The
    /// rebuild is memory-flat and happens off-screen, so it is effectively free (verified on-device).
    ///
    /// - Parameter enabled: pass `false` to suppress the rebuild while an in-list selection or edit
    ///   mode is active — a rebuild would drop that selection. Defaults to `true`.
    func resetsSwipeOnNavigation(enabled: Bool = true) -> some View {
        modifier(SwipeResetModifier(enabled: enabled))
    }
}

/// Bumps a private token on `.onDisappear`, changing the wrapped view's `.id` so SwiftUI rebuilds
/// it fresh (swipes closed) the next time it appears.
private struct SwipeResetModifier: ViewModifier {
    let enabled: Bool
    @State private var token = 0
    func body(content: Content) -> some View {
        content
            .id(token)
            .onDisappear { if enabled { token &+= 1 } }
    }
}
```

- [ ] **Step 2: Apply to HoldingsView**

In `WriteScreens/HoldingsView.swift`, attach the modifier to the `List` that opens at line 30 — immediately after its closing brace at line 42 (line 43 closes the enclosing `else`). Result:

```swift
                List {
                    // ... existing rows (unchanged) ...
                }
                .resetsSwipeOnNavigation()
```

No `enabled:` argument — HoldingsView has no selection mode.

- [ ] **Step 3: Regenerate the project (new file added)**

Run: **ENV** then **XGEN**. Expected: `Created project at .../FinchApp.xcodeproj`.

- [ ] **Step 4: Build iOS and macOS**

Run: **BUILD_IOS**, then **BUILD_MAC**. Expected: `** BUILD SUCCEEDED **` for both (macOS matters — this is the shared file).

- [ ] **Step 5: Manual reset check on Holdings**

Run **INSTALL_LAUNCH**. Perform the **Manual reset check** on the Holdings screen (an account's holdings). Confirm a swiped-open holding row closes after navigating away and back.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/Common/SwipeReset.swift ios/FinchApp/Sources/FinchApp/WriteScreens/HoldingsView.swift && git commit -m "feat(ios): swipe rows reset on navigation — shared modifier + Holdings"
```

## Task 2: Apply Component 1 to the remaining no-gate short lists

**Files (all Modify):**
- `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift` (List opens 52, closes 87; trailing `#if os(iOS) .listStyle(.insetGrouped) #endif` at 88-90)
- `ios/FinchApp/Sources/FinchApp/Tabs/SettingsBackupsView.swift` (List opens 31, closes 119; trailing `.onAppear`/`.onChange`/`.navigationTitle` at 121-123)
- `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift` (List opens 17, closes 51; trailing `.navigationTitle("Rules")` at 52)
- `ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRateHistoryView.swift` (List opens 20, closes 48; trailing `.navigationTitle(currency)` at 49)

**Interfaces:**
- Consumes: `resetsSwipeOnNavigation(enabled:)` from Task 1.

- [ ] **Step 1: Attach `.resetsSwipeOnNavigation()` (no argument) to each List**

None of these four has a selection mode → no `enabled:` argument. Insert the modifier right after each List's closing brace, before its existing trailing modifiers:

`ScheduledCalendarView.swift` — after line 87 `}`:
```swift
        }
        .resetsSwipeOnNavigation()
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
```

`SettingsBackupsView.swift` — after line 119 `}`:
```swift
        }
        .resetsSwipeOnNavigation()
        .onAppear { retention = min(max(retention, AutoBackupManager.retentionRange.lowerBound), AutoBackupManager.retentionRange.upperBound) }
```
(then the existing `.onChange` / `.navigationTitle` follow unchanged).

`RulesManagerView.swift` — after line 51 `}`:
```swift
        }
        .resetsSwipeOnNavigation()
        .navigationTitle("Rules")
```
(Note: the `MultiSelectList` helper's own `List {` at line 135 has no swipes — leave it alone.)

`ExchangeRateHistoryView.swift` — after line 48 `}`:
```swift
        }
        .resetsSwipeOnNavigation()
        .navigationTitle(currency)
```

- [ ] **Step 2: Build iOS**

Run: **ENV** then **BUILD_IOS**. Expected: `** BUILD SUCCEEDED **`. (No new files → no XGEN needed.)

- [ ] **Step 3: Manual reset check**

Run **INSTALL_LAUNCH**. Perform the **Manual reset check** on the Scheduled calendar (a day's occurrences) and the FX rate history screen. Confirm rows close after navigate-away-and-back.

- [ ] **Step 4: Commit**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift ios/FinchApp/Sources/FinchApp/Tabs/SettingsBackupsView.swift ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRateHistoryView.swift && git commit -m "feat(ios): swipe-reset on Scheduled calendar, Backups, Rules, FX history"
```

## Task 3: Apply Component 1 to the split-selection short lists

These use `List(selection:)` for split/keyboard selection; gate the reset with `enabled: <selection is empty>` so a rebuild never drops an active selection.

**Files (all Modify):**
- `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift` — two List variants in `contentList` (184-216)
- `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift` — two List variants in `contentList` (164-196)
- `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift` — `List(selection: selection ?? $kbSel)` (68-126)
- `ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerManagementView.swift` — two single-line List variants (21, 23)

**Interfaces:**
- Consumes: `resetsSwipeOnNavigation(enabled:)` from Task 1.

- [ ] **Step 1: AccountsTab — both variants**

`List(selection: selection) {` (line 186, inside `if let selection`) closes at line 195. Gate on the unwrapped binding:
```swift
            List(selection: selection) {
                // ... unchanged ...
            }
            .resetsSwipeOnNavigation(enabled: selection.wrappedValue == nil)
            #if os(macOS)
            .onDeleteCommand { if let id = selection.wrappedValue, let a = store.accounts.first(where: { $0.id == id }) { pendingDelete = a } }
            #endif
```
Plain `List {` (line 200, the `else` branch) closes at line 214, no selection — no gate:
```swift
            List {
                // ... unchanged ...
            }
            .resetsSwipeOnNavigation()
```
Leave `reorderList` (`return List {` at 321, `.onMove`, no swipes) untouched.

- [ ] **Step 2: BudgetsTab — both variants (mirror of AccountsTab)**

`List(selection: selection) {` (line 166) closes at 175:
```swift
            List(selection: selection) {
                // ... unchanged ...
            }
            .resetsSwipeOnNavigation(enabled: selection.wrappedValue == nil)
            #if os(macOS)
            .onDeleteCommand { if let id = selection.wrappedValue, let b = store.budgets.first(where: { $0.id == id }) { delete(b) } }
            #endif
```
Plain `List {` (line 180) closes at 194:
```swift
            List {
                // ... unchanged ...
            }
            .resetsSwipeOnNavigation()
```
Leave `reorderList` (`return List {` at 293) untouched.

- [ ] **Step 3: ScheduledTab**

`List(selection: selection ?? $kbSel) {` (line 68) closes at line 126; trailing `.overlay { ... }` at 127. Gate on both selection sources:
```swift
                            List(selection: selection ?? $kbSel) {
                                // ... unchanged ...
                            }
                            .resetsSwipeOnNavigation(enabled: selection?.wrappedValue == nil && kbSel == nil)
                            .overlay {
                                if searchActive && filteredScheduled.isEmpty && filteredDetected.isEmpty {
                                    ContentUnavailableView.search(text: searchQuery)
                                }
                            }
```

- [ ] **Step 4: LedgerManagementView — both single-line variants**

Inside `if let selection` (lines 19-25):
```swift
                List(selection: selection) { rows }
                    .resetsSwipeOnNavigation(enabled: selection.wrappedValue == nil)
```
and the `else` plain variant:
```swift
                List { rows }
                    .resetsSwipeOnNavigation()
```

- [ ] **Step 5: Build iOS and macOS**

Run: **ENV**, **BUILD_IOS**, **BUILD_MAC**. Expected: `** BUILD SUCCEEDED **` for both (AccountsTab/BudgetsTab have `#if os(macOS)` branches — verify the modifier placement compiles there).

- [ ] **Step 6: Manual reset check incl. selection mode**

Run **INSTALL_LAUNCH**. Perform the **Manual reset check** on Accounts, Budgets, and the Scheduled list. On iPad/Mac split (if available), additionally: select an item (detail shows), navigate away and back, and confirm the selection is intact (the gate held — no rebuild fired while selected).

- [ ] **Step 7: Commit**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerManagementView.swift && git commit -m "feat(ios): swipe-reset on Accounts, Budgets, Scheduled, Ledgers (selection-gated)"
```

## Task 4: Apply Component 1 to the `isSelecting` short lists — completes Phase 1

These use an `isSelecting` multi-select flag. Gate with `enabled: !isSelecting`.

**Files (all Modify):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift` (List at line 44, trailing `.modifier(SearchableModifier...)` at 45)
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift` (List opens 63, closes 76; trailing `.modifier(SearchableModifier...)`/`.navigationTitle` at 77-78)
- `ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift` (List opens 41, closes 47; trailing `.modifier(SearchableModifier...)`/`.navigationTitle` at 48-49)

**Interfaces:**
- Consumes: `resetsSwipeOnNavigation(enabled:)` from Task 1.

- [ ] **Step 1: MerchantsView**

Single-line `List` at line 44:
```swift
                List { ForEach(filtered) { cp in row(cp, counts) } }
                    .resetsSwipeOnNavigation(enabled: !isSelecting)
                    .modifier(SearchableModifier(text: $search))
```

- [ ] **Step 2: CategoriesView**

`return List {` (line 63) closes at 76:
```swift
        }
        .resetsSwipeOnNavigation(enabled: !isSelecting)
        .modifier(SearchableModifier(text: $search))
        .navigationTitle("Categories")
```
(The reorder branch makes rows `.draggable` with no swipes; the merge-target sheet's `List {` at line 93 is separate — leave both alone.)

- [ ] **Step 3: TagsView**

`return List {` (line 41) closes at 47:
```swift
        }
        .resetsSwipeOnNavigation(enabled: !isSelecting)
        .modifier(SearchableModifier(text: $search))
        .navigationTitle("Tags")
```
(The gate is load-bearing here: `TagsView`'s `.swipeActions` at line 188 are attached even during select mode.)

- [ ] **Step 4: Build iOS and macOS**

Run: **ENV**, **BUILD_IOS**, **BUILD_MAC**. Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 5: Manual reset check incl. select mode**

Run **INSTALL_LAUNCH**. Perform the **Manual reset check** on Merchants, Categories, Tags. Then: enter select mode (tap Select), navigate away and back, and confirm the selection state is preserved (gate held).

- [ ] **Step 6: Commit — Phase 1 complete**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift && git commit -m "feat(ios): swipe-reset on Merchants, Categories, Tags (selection-gated)"
```

**Phase 1 is now complete and mergeable** — all 12 short lists reset swipes on navigation. Phase 2 adds scroll-preserving reset to the 5 feeds.

---

# PHASE 2 — long feeds with scroll preservation (Tasks 5–8)

## Task 5: Component 2 helpers + unit tests

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/SwipeReset.swift` (append Component 2)
- Create: `ios/FinchApp/Tests/FinchAppTests/SwipeResetTests.swift`

**Interfaces:**
- Produces:
  - `enum SwipeReset { static func topVisibleID(order: [String], visible: Set<String>) -> String? }`
  - `func tracksTopRow(id: String, order: [String], visible: Binding<Set<String>>, anchor: Binding<String?>) -> some View`
  - `func resetsSwipeAndRestoresScroll(enabled: Bool, token: Binding<Int>, anchor: Binding<String?>, savedAnchor: Binding<String?>, proxy: ScrollViewProxy) -> some View`

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/SwipeResetTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class SwipeResetTests: XCTestCase {
    func test_topVisibleID_returnsFirstOrderedIdThatIsVisible() {
        let order = ["a", "b", "c", "d", "e"]
        // c and d on screen → topmost in display order is c.
        XCTAssertEqual(SwipeReset.topVisibleID(order: order, visible: ["d", "c"]), "c")
    }

    func test_topVisibleID_respectsOrderNotSetIteration() {
        let order = ["z", "y", "x"]
        // Only y and x visible → first in order (z absent) is y.
        XCTAssertEqual(SwipeReset.topVisibleID(order: order, visible: ["x", "y"]), "y")
    }

    func test_topVisibleID_emptyVisible_isNil() {
        XCTAssertNil(SwipeReset.topVisibleID(order: ["a", "b"], visible: []))
    }

    func test_topVisibleID_ignoresStaleVisibleIdsNotInOrder() {
        // A visible id that is no longer part of the display order is ignored.
        XCTAssertEqual(SwipeReset.topVisibleID(order: ["a", "b"], visible: ["gone", "b"]), "b")
    }

    func test_topVisibleID_emptyOrder_isNil() {
        XCTAssertNil(SwipeReset.topVisibleID(order: [], visible: ["a"]))
    }
}
```

- [ ] **Step 2: Regenerate + run the test to verify it fails**

Run: **ENV**, **XGEN** (the new test file must be added to `FinchAppTests`), then **TEST_SWIPE**.
Expected: FAIL to compile / `use of unresolved identifier 'SwipeReset'` (the enum does not exist yet).

- [ ] **Step 3: Append Component 2 to `SwipeReset.swift`**

Add to the end of `ios/FinchApp/Sources/FinchApp/Common/SwipeReset.swift`:

```swift
// MARK: - Component 2 — scroll preservation for long transaction feeds

/// Pure helpers for feeds that must also keep their scroll position across the reset rebuild.
enum SwipeReset {
    /// The topmost currently-visible row: the first id in `order` (the full display order of row
    /// ids) that is present in `visible` (the set of on-screen row ids). `nil` when nothing known
    /// is visible. Ordering comes from `order`, never from `Set` iteration.
    static func topVisibleID(order: [String], visible: Set<String>) -> String? {
        order.first { visible.contains($0) }
    }
}

extension View {
    /// Feed rows: report on-screen visibility and keep `anchor` pointing at the current top-visible
    /// row. `anchor` is updated on `onAppear` ONLY — never on `onDisappear` — so it survives the
    /// navigate-away teardown (when many rows disappear at once) holding the last on-screen top
    /// instead of being cleared. `order` is the full display order of `Tx.id`s.
    func tracksTopRow(id: String, order: [String],
                      visible: Binding<Set<String>>, anchor: Binding<String?>) -> some View {
        onAppear {
            visible.wrappedValue.insert(id)
            anchor.wrappedValue = SwipeReset.topVisibleID(order: order, visible: visible.wrappedValue)
        }
        .onDisappear { visible.wrappedValue.remove(id) }
    }

    /// Feed `List` (MUST be inside a `ScrollViewReader`): rebuild on navigate-away to close swipes,
    /// then restore the frozen anchor on return. On leave, `anchor` (the live top) is frozen into
    /// `savedAnchor` — which row re-appears on return cannot overwrite — then the token bumps.
    /// On return, `scrollTo(savedAnchor)` runs `async` so the rebuilt list lays out first.
    func resetsSwipeAndRestoresScroll(enabled: Bool, token: Binding<Int>,
                                      anchor: Binding<String?>, savedAnchor: Binding<String?>,
                                      proxy: ScrollViewProxy) -> some View {
        self
            .id(token.wrappedValue)
            .onDisappear {
                if enabled {
                    savedAnchor.wrappedValue = anchor.wrappedValue
                    token.wrappedValue &+= 1
                }
            }
            .onAppear {
                if let a = savedAnchor.wrappedValue {
                    DispatchQueue.main.async { proxy.scrollTo(a, anchor: .top) }
                }
            }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: **TEST_SWIPE**. Expected: `Test Suite 'SwipeResetTests' passed` (5 tests).

- [ ] **Step 5: Build iOS and macOS**

Run: **BUILD_IOS**, **BUILD_MAC**. Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/Common/SwipeReset.swift ios/FinchApp/Tests/FinchAppTests/SwipeResetTests.swift && git commit -m "feat(ios): swipe-reset Component 2 — top-visible tracking + scroll restore (+ tests)"
```

## Task 6: Apply Component 2 to Account detail (the clean feed — no selection)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift` (List opens 35, closes 42; `txRow` at 219; `transactionsSection` 168-215)

**Interfaces:**
- Consumes: `tracksTopRow(...)`, `resetsSwipeAndRestoresScroll(...)` from Task 5.

- [ ] **Step 1: Add feed state**

Add these `@State` properties to `AccountDetailView` (near the existing `@State` declarations at the top of the struct):

```swift
    @State private var swipeToken = 0
    @State private var visibleTxns: Set<String> = []
    @State private var scrollAnchor: String?
    @State private var savedScrollAnchor: String?
```

- [ ] **Step 2: Thread display order into the row builder**

`txRow` is `@ViewBuilder private func txRow(_ t: Tx) -> some View` at line 219. Give it an `order` parameter and attach the tracking hook. Change the signature and its body's outer modifier:

```swift
    @ViewBuilder private func txRow(_ t: Tx, order: [String]) -> some View {
        // ... existing row content, unchanged, ending with .txnSwipeActions(t, …) at line 226 ...
        // append this to the returned view:
            .tracksTopRow(id: t.id, order: order, visible: $visibleTxns, anchor: $scrollAnchor)
    }
```

In `transactionsSection(_ a: Account)`, after `let confirmed = ...` (line 176) compute the display order once, and pass it to every `txRow(...)` call:

```swift
        let order: [String] = groupByMonth
            ? (pending + MonthGrouping.sections(confirmed).flatMap { $0.txns }).map(\.id)
            : (pending + confirmed).map(\.id)
```

Then update the three call sites:
- line 179 `ForEach(pending, id: \.id) { t in txRow(t) }` → `txRow(t, order: order)`
- line 190 `ForEach(section.txns, id: \.id) { t in txRow(t) }` → `txRow(t, order: order)`
- line 212 `ForEach(confirmed, id: \.id) { t in txRow(t) }` → `txRow(t, order: order)`

- [ ] **Step 3: Wrap the List in a ScrollViewReader and attach the reset+restore modifier**

The List opens at line 35 inside `if let account {`, closes at line 42, with `.errorAlert`/`.navigationTitle` trailing at 43-44. Wrap just the List:

```swift
                ScrollViewReader { proxy in
                    List {
                        // ... unchanged section content ...
                    }
                    .resetsSwipeAndRestoresScroll(enabled: true, token: $swipeToken,
                                                  anchor: $scrollAnchor, savedAnchor: $savedScrollAnchor,
                                                  proxy: proxy)
                    .errorAlert($errorMessage)
                    .navigationTitle(account.name ?? "Account")
                    // ... any remaining existing modifiers, unchanged ...
                }
```

`enabled: true` — AccountDetailView has no selection mode.

- [ ] **Step 4: Build iOS and macOS**

Run: **ENV**, **BUILD_IOS**, **BUILD_MAC**. Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 5: Manual check — reset AND scroll preservation**

Run **INSTALL_LAUNCH**. Open an account with many transactions. Scroll down into the middle, swipe a row open, push a transaction's detail (or switch tabs) and return. Confirm: (a) the row is closed, and (b) the list is at the same scroll position, not jumped to the top.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift && git commit -m "feat(ios): scroll-preserving swipe-reset on Account detail"
```

## Task 7: Apply Component 2 to Category / Tag / Merchant detail (three identical clean feeds)

All three have the same shape: computed `txns` + `pendingTxns`, a shared `row(_ tx:)` builder, no selection.

**Files (all Modify):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryDetailView.swift` (List opens 30, closes 48; `row` at 74; `txns` computed at 16, `pendingTxns` at 24)
- `ios/FinchApp/Sources/FinchApp/PowerTools/TagDetailView.swift` (List opens 29, closes 47; `row` at 73; `txns` at 15, `pendingTxns` at 23)
- `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift` (List opens 27, closes 45; `row` at 71; `txns` at 13, `pendingTxns` at 21)

**Interfaces:**
- Consumes: `tracksTopRow(...)`, `resetsSwipeAndRestoresScroll(...)` from Task 5.

- [ ] **Step 1: For EACH of the three files, add feed state + display order**

Add these `@State` properties to the struct (near existing state):

```swift
    @State private var swipeToken = 0
    @State private var visibleTxns: Set<String> = []
    @State private var scrollAnchor: String?
    @State private var savedScrollAnchor: String?
```

Add a computed display-order property (the arrays already exist as computed properties on each view):

```swift
    private var displayOrder: [String] { (pendingTxns + txns).map(\.id) }
```

- [ ] **Step 2: For EACH file, attach the tracking hook in `row(_:)`**

`row` is `@ViewBuilder private func row(_ tx: Tx) -> some View` (line 74 / 73 / 71). Append the hook to the returned view (after its existing `.txnSwipeActions(tx, …)`):

```swift
            .tracksTopRow(id: tx.id, order: displayOrder, visible: $visibleTxns, anchor: $scrollAnchor)
```

`row` is shared between the pending `ForEach` and the Transactions `ForEach`, so this covers both. No signature change is needed (`displayOrder` is in scope as a property).

- [ ] **Step 3: For EACH file, wrap the List in a ScrollViewReader + attach reset+restore**

`List {` (line 30 / 29 / 27) closes at 48 / 47 / 45, with `.navigationTitle(...)` trailing. Wrap:

```swift
        ScrollViewReader { proxy in
            List {
                // ... unchanged ...
            }
            .resetsSwipeAndRestoresScroll(enabled: true, token: $swipeToken,
                                          anchor: $scrollAnchor, savedAnchor: $savedScrollAnchor,
                                          proxy: proxy)
            .navigationTitle(category.name)   // TagDetailView: tag.name · CounterpartyDetailView: counterparty.name
            // ... any remaining existing modifiers, unchanged ...
        }
```

`enabled: true` — none has a selection mode. Use the file's own `.navigationTitle` argument (`category.name` / `tag.name` / `counterparty.name`) unchanged.

- [ ] **Step 4: Build iOS and macOS**

Run: **ENV**, **BUILD_IOS**, **BUILD_MAC**. Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 5: Manual check — reset AND scroll preservation**

Run **INSTALL_LAUNCH**. Open a category (or tag / merchant) with many transactions. Scroll down, swipe a row, push a detail / switch tabs, return. Confirm the row closed and scroll position is preserved. Spot-check at least two of the three screens.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryDetailView.swift ios/FinchApp/Sources/FinchApp/PowerTools/TagDetailView.swift ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift && git commit -m "feat(ios): scroll-preserving swipe-reset on Category, Tag, Merchant detail"
```

## Task 8: Apply Component 2 to the Activity feed (gated, complex) — completes Phase 2

The Activity feed (`ActivityFeedView`) has multi-select (`isSelecting`/`selected`), split/keyboard selection (`selection`/`kbSel`), pagination, and non-transaction rows. The reset must be gated so a rebuild never fires mid-selection.

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift` (`List(selection:)` opens 84, closes 137; `row(_:)` at 317; `@State pendingTxns` 72, `@State sections` 71)

**Interfaces:**
- Consumes: `tracksTopRow(...)`, `resetsSwipeAndRestoresScroll(...)` from Task 5.

- [ ] **Step 1: Add feed state + display order**

Add to `ActivityFeedView` (near the existing `@State` at lines 62-72):

```swift
    @State private var swipeToken = 0
    @State private var visibleTxns: Set<String> = []
    @State private var scrollAnchor: String?
    @State private var savedScrollAnchor: String?
```

Add a computed display-order property (pending is always pinned first; when `groupByMonth == false` the confirmed rows are still `sections.flatMap { $0.txns }`):

```swift
    private var displayOrder: [String] { (pendingTxns + sections.flatMap { $0.txns }).map(\.id) }
```

- [ ] **Step 2: Attach the tracking hook in `row(_:)`**

`row` is `private func row(_ txn: Tx) -> some View` at line 317, shared across the pending, month-section, and ungrouped `ForEach`es. Append the hook to the returned view (after the existing `.txnSwipeActions(...)` at 335 and `.tag(txn.id)` at 341):

```swift
            .tracksTopRow(id: txn.id, order: displayOrder, visible: $visibleTxns, anchor: $scrollAnchor)
```

The non-transaction rows (saved-search chips, count row, "Load more") are not tracked — only txn rows anchor scroll, which is correct.

- [ ] **Step 3: Wrap the List in a ScrollViewReader + attach gated reset+restore**

The `List(selection: selection ?? $kbSel) {` (line 84) is inside `else {` (line 83) inside a `Group` (line 80); it closes at line 137 with a `#if os(macOS) .onKeyPress(.return) … #endif` trailing at 138-146. Wrap just the List (the `Group`'s `.searchable`/`.toolbar`/`.onChange`s at 149+ stay on the Group, untouched):

```swift
                ScrollViewReader { proxy in
                    List(selection: selection ?? $kbSel) {
                        // ... unchanged ...
                    }
                    .resetsSwipeAndRestoresScroll(
                        enabled: !isSelecting && selection?.wrappedValue == nil && kbSel == nil,
                        token: $swipeToken, anchor: $scrollAnchor,
                        savedAnchor: $savedScrollAnchor, proxy: proxy)
                    #if os(macOS)
                    .onKeyPress(.return) {
                        // ... unchanged ...
                    }
                    #endif
                }
```

The `enabled:` expression suppresses the rebuild whenever bulk multi-select, split selection, or keyboard selection is active — protecting `selected` / `selection` / `kbSel`.

- [ ] **Step 4: Build iOS and macOS**

Run: **ENV**, **BUILD_IOS**, **BUILD_MAC**. Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 5: Manual check — reset, scroll preservation, and selection safety (device flash check)**

Run **INSTALL_LAUNCH**. On the Activity feed:
1. Scroll into the middle, swipe a transaction open, switch tabs, return → row closed, scroll position preserved. **Watch the return transition for any flash of the top of the list** — the async restore should be seamless. If a flash is visible, note it (a follow-up could freeze the list opacity for one frame); do not block the task on it unless it is clearly objectionable.
2. Enter multi-select (long-press or Select), select a few rows, switch tabs, return → selection is intact and the list did NOT jump to the top (the gate held; no rebuild fired).
3. On iPad/Mac split (if available): select a row (detail shows), navigate, return → selection preserved.

- [ ] **Step 6: Commit — Phase 2 complete**

```bash
cd /tmp/finch-swipe-reset && git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift && git commit -m "feat(ios): scroll-preserving, selection-gated swipe-reset on Activity feed"
```

---

## Self-review (completed by plan author)

**Spec coverage:** Component 1 (short lists) → Tasks 1-4 (all 12 screens). Component 2 (feeds) → Tasks 5-8 (all 5 feeds). Selection gating → Task 3/4 (short) + Task 8 (Activity). Pure-helper unit test → Task 5. `EditTransactionSheet` exclusion honored (never touched). `.scrollPosition(id:)` avoided (manual anchor used). macOS build verified in every code task. ✔

**Placeholder scan:** every code step shows the exact modifier/edit and its anchor line; commands are named and defined; no "TBD"/"handle edge cases"/"similar to". ✔

**Type consistency:** `resetsSwipeOnNavigation(enabled:)`, `topVisibleID(order:visible:)`, `tracksTopRow(id:order:visible:anchor:)`, `resetsSwipeAndRestoresScroll(enabled:token:anchor:savedAnchor:proxy:)` — signatures defined in Tasks 1/5 and used identically in Tasks 2-4/6-8. Feed state names (`swipeToken`, `visibleTxns`, `scrollAnchor`, `savedScrollAnchor`) consistent across Tasks 6-8. ✔
