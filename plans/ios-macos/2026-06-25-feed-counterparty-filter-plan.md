# Feed merchant (counterparty) filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Merchant" filter to the feed's filter sheet, matching the merchant detail's id-or-name behavior.

**Architecture:** `TxFilter` gains `counterpartyId`; the sheet adds a Merchant picker; the feed's `filteredTxns()` composes `merchantTransactions` (#306) with `selectTransactions` (#286). UI-only, no engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-feed-counterparty-filter-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Merchant filter (sheet + feed)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: Add `counterpartyId` to `TxFilter` (+ isActive)**

In `TransactionFilterSheet.swift`, in `struct TxFilter`, after `var tagId: String? = nil`, add:

```swift
    var counterpartyId: String? = nil
```

In `isActive`, add the new field. Replace:

```swift
    var isActive: Bool {
        direction != nil || accountId != nil || categoryId != nil || tagId != nil
            || status != nil || from != nil || to != nil || minAmount != nil || maxAmount != nil
    }
```
with:
```swift
    var isActive: Bool {
        direction != nil || accountId != nil || categoryId != nil || tagId != nil
            || counterpartyId != nil
            || status != nil || from != nil || to != nil || minAmount != nil || maxAmount != nil
    }
```

- [ ] **Step 2: Add the Merchant picker**

In the sheet body, immediately **after** the Tag picker block:

```swift
                    if !store.tags.isEmpty {
                        Picker("Tag", selection: $draft.tagId) {
                            Text("Any").tag(String?.none)
                            ForEach(store.tags) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
```
add:

```swift
                    if !store.merchants.isEmpty {
                        Picker("Merchant", selection: $draft.counterpartyId) {
                            Text("Any").tag(String?.none)
                            ForEach(store.merchants) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
```

- [ ] **Step 3: Compose the merchant filter in `filteredTxns()`**

In `ActivityTab.swift`, replace `filteredTxns()`:

```swift
    private func filteredTxns() -> [Tx] {
        let opts = ListOptions(
            ledgerId: store.activeLedgerId,
            direction: filter.direction,
            query: searchQuery.isEmpty ? nil : searchQuery,
            accountId: filter.accountId,
            categoryId: filter.categoryId,
            status: filter.status,
            from: filter.fromYMD,
            to: filter.toYMD,
            minAmount: filter.minAmount,
            maxAmount: filter.maxAmount,
            tagId: filter.tagId)
        return Selectors.selectTransactions(store.txns, opts)
    }
```
with:
```swift
    private func filteredTxns() -> [Tx] {
        let base = filter.counterpartyId.map {
            Selectors.merchantTransactions(store.txns, store.merchants, $0, store.activeLedgerId)
        } ?? store.txns
        let opts = ListOptions(
            ledgerId: store.activeLedgerId,
            direction: filter.direction,
            query: searchQuery.isEmpty ? nil : searchQuery,
            accountId: filter.accountId,
            categoryId: filter.categoryId,
            status: filter.status,
            from: filter.fromYMD,
            to: filter.toYMD,
            minAmount: filter.minAmount,
            maxAmount: filter.maxAmount,
            tagId: filter.tagId)
        return Selectors.selectTransactions(base, opts)
    }
```

- [ ] **Step 4: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): feed filter by merchant (counterparty)"
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
(Need at least one merchant — Power Tools › Merchants. A merchant whose name matches some transactions shows results.)

- [ ] **Step 2: Verify**
  - Feed → Filter → a **Merchant** picker appears; pick a merchant → the feed narrows to that merchant's transactions (same set as its detail screen); the Filter icon shows active; the count caption updates.
  - Combine with **Type = Out** (or another filter) → both apply.
  - **Clear filters & search** resets it.
  - Screenshot evidence to `/tmp/cpfilter.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: `counterpartyId` + isActive (T1 S1), Merchant picker (T1 S2), `filteredTxns` composition (T1 S3), cross-platform build (T1 S4), manual (T2). ✓
- Type consistency: `filter.counterpartyId`, `Selectors.merchantTransactions(_:_:_:_:)`, `store.merchants`, `selectTransactions` consistent. ✓
- No engine change. ✓
