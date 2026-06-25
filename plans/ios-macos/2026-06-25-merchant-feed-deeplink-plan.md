# Merchant → filtered feed deep-link — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "See in Activity feed" button on the merchant detail that switches to the Activity tab pre-filtered to that merchant.

**Architecture:** `DeepLinkRouter` gets a one-shot `pendingFilter`; the Activity-tab `ActivityFeedView` consumes it; `CounterpartyDetailView` sets it + `selectedTab = .activity`. Reuses the #308 counterparty filter. No engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-merchant-feed-deeplink-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Router slot + feed consumption + the button

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift`

- [ ] **Step 1: Add `pendingFilter` to `DeepLinkRouter`**

In `DeepLinkRouter.swift`, after `@Published public var focusedId: String? = nil`, add:

```swift
    @Published var pendingFilter: TxFilter?   // one-shot: consumed by the Activity feed
```
(Intentionally not `public` — `TxFilter` is internal to the `FinchApp` module; the class stays `public`.)

- [ ] **Step 2: Add the consume flag + helper to `ActivityFeedView`**

In `ActivityTab.swift`, in `struct ActivityFeedView`, after `var headerSection: AnyView? = nil`, add:

```swift
    var consumesPendingFilter: Bool = false
```
Add the helper method (near `consumeFocus()`):

```swift
    private func consumePendingFilter() {
        guard consumesPendingFilter, let pending = router.pendingFilter else { return }
        searchQuery = ""
        filter = pending            // existing .onChange(of: filter) → recompute()
        router.pendingFilter = nil
    }
```

- [ ] **Step 3: Wire it into the view modifiers**

In `ActivityFeedView.body`, replace:

```swift
        .onAppear { consumeFocus(); recompute() }
        .onChange(of: router.focusedId) { _, _ in consumeFocus() }
```
with:
```swift
        .onAppear { consumeFocus(); consumePendingFilter(); recompute() }
        .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        .onChange(of: router.pendingFilter) { _, _ in consumePendingFilter() }
```

- [ ] **Step 4: Opt the Activity tab in**

In `ActivityTab.swift`, in `struct ActivityTab`, replace:

```swift
        NavigationStack { ActivityFeedView() }
```
with:
```swift
        NavigationStack { ActivityFeedView(consumesPendingFilter: true) }
```
(Leave the Ledger tab and Accounts "All Transactions" instances unchanged — they keep the default `false`.)

- [ ] **Step 5: Add the button to `CounterpartyDetailView`**

In `CounterpartyDetailView.swift`, inside the `List`, after the summary `Section { … }` and before the `if !txns.isEmpty { Section("Transactions") … }`, add:

```swift
            if !txns.isEmpty {
                Section {
                    Button {
                        DeepLinkRouter.shared.pendingFilter = TxFilter(counterpartyId: counterparty.id)
                        DeepLinkRouter.shared.selectedTab = .activity
                    } label: {
                        Label("See in Activity feed", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
```

- [ ] **Step 6: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`. (If `TxFilter(counterpartyId:)` won't compile, the struct's synthesized memberwise init should accept it since all fields have defaults — read `TransactionFilterSheet.swift` and match.)

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift
git commit -m "feat(ios): merchant detail → filtered Activity feed deep-link"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(A "Coffee" merchant matching the Coffee transaction is typically already seeded; otherwise Power Tools › Merchants.)

- [ ] **Step 2: Verify**
  - Settings → Power Tools → Merchants → a merchant with transactions → **See in Activity feed**.
  - App switches to the **Activity** tab; the feed shows only that merchant's transactions (matches the detail screen's list); the Filter icon is active.
  - **Clear filters** resets the feed; a merchant with no transactions shows no button.
  - Screenshot evidence to `/tmp/merchantdeeplink.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: router `pendingFilter` (T1 S1), feed flag + helper (T1 S2), modifier wiring (T1 S3), Activity-tab opt-in (T1 S4), detail button (T1 S5), cross-platform build (T1 S6), manual (T2). ✓
- Type consistency: `pendingFilter: TxFilter?` (router), `consumesPendingFilter: Bool` (feed), `TxFilter(counterpartyId:)`, `DeepLinkRouter.shared`, `selectedTab = .activity` consistent with explored code. ✓
- No engine change; reuses #308 counterparty filter. ✓
