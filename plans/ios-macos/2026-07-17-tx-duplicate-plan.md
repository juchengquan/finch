# Transaction Duplicate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** Leading-swipe **Duplicate** on expense/income transaction rows in the Activity feed, Account Detail, and Counterparty Detail (+ context-menu twins).

**Architecture:** One shared `FinchStore.duplicateTransaction(_:)` via the `addTransaction` chokepoint; per-file row wiring matching each file's error pattern. No engine change.

Spec: `plans/ios-macos/2026-07-17-tx-duplicate-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- All row edits are additive; don't touch trailing swipes or existing Confirm buttons.

---

### Task 1: Shared helper

**Files:** Modify `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift`

- [ ] **Step 1:** Add near the other transaction helpers (e.g. after `transactions(for:)`):

```swift
    /// Re-posts a copy of a transaction dated today (same account / merchant /
    /// category / signed amount / currency / tags) via the addTransaction
    /// chokepoint — the "same coffee again" quick verb. Expense/income only;
    /// note, receipts, refund links, and pending status are deliberately not
    /// copied (a duplicate is a new event).
    public func duplicateTransaction(_ txn: Tx) throws {
        var args: [String: JSONValue] = [
            "ledgerId": .string(activeLedgerId), "accountId": .string(txn.account),
            "amount": .double(txn.amount), "merchant": .string(txn.merchant),
            "date": .string(today)]
        if let c = txn.category { args["categoryId"] = .string(c) }
        if let cur = txn.currency { args["currency"] = .string(cur) }
        if let tags = txn.tags, !tags.isEmpty { args["tagIds"] = .array(tags.map { .string($0) }) }
        try apply(.addTransaction, Args(args))
    }
```
(If `apply` isn't directly callable here, match how sibling helpers in this file invoke actions — e.g. `setDisplayCurrency` — and mirror that exactly.)

---

### Task 2: Row wiring — three lists

**Files:** Modify `Tabs/ActivityTab.swift`, `WriteScreens/AccountDetailView.swift`, `PowerTools/CounterpartyDetailView.swift`

- [ ] **Step 1 — ActivityTab** (`row(_ txn:)`, leading swipe ~line 307). Change:

```swift
        .swipeActions(edge: .leading) {
            if txn.pending == true {
                Button { confirm(txn) } label: { Label("Confirm", systemImage: "checkmark.circle") }.tint(.green)
            }
        }
```
to:

```swift
        .swipeActions(edge: .leading) {
            if txn.pending == true {
                Button { confirm(txn) } label: { Label("Confirm", systemImage: "checkmark.circle") }.tint(.green)
            }
            if ["expense", "income"].contains(txn.kind ?? "") {
                Button { duplicate(txn) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.indigo)
            }
        }
```
In the row's `.contextMenu`, after the Edit button, add:

```swift
            if ["expense", "income"].contains(txn.kind ?? "") {
                Button { duplicate(txn) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            }
```
Next to `delete(_:)`/`confirm(_:)`, add:

```swift
    private func duplicate(_ txn: Tx) {
        run { try store.duplicateTransaction(txn) }
    }
```

- [ ] **Step 2 — AccountDetailView** (`txRow(_ t:)`, ~line 155): same three additions — leading-swipe button after the pending-Confirm `if`, context-menu entry after Edit, and:

```swift
    private func duplicateTxn(_ t: Tx) {
        do { try store.duplicateTransaction(t) } catch { errorMessage = i18nMessage(error) }
    }
```
(Match this file's existing error state — it uses the same `errorMessage`/`i18nMessage` pattern as its `confirmTxn`. If the local names differ, mirror `confirmTxn` exactly.)

- [ ] **Step 3 — CounterpartyDetailView** (the `ForEach(txns)` row, ~line 36). The row has no swipes/menu today. Change:

```swift
                        Button { editing = tx } label: { TxRow(txn: tx).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
```
to:

```swift
                        Button { editing = tx } label: { TxRow(txn: tx).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                if ["expense", "income"].contains(tx.kind ?? "") {
                                    Button { duplicate(tx) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.indigo)
                                }
                            }
                            .contextMenu {
                                Button { editing = tx } label: { Label("Edit", systemImage: "pencil") }
                                if ["expense", "income"].contains(tx.kind ?? "") {
                                    Button { duplicate(tx) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                }
                            }
```
Add a `duplicate(_:)` func matching this file's error handling; if it has no error state, add `@State private var errorMessage: String?` + `.errorAlert($errorMessage)` following the pattern used across tabs.

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

- [ ] **Step 5: Commit** (all four files, one commit)

```bash
git add ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift
git commit -m "feat(ios): leading-swipe Duplicate on transaction rows (feed, account & counterparty detail)"
```

---

### Task 3: Verification (controller)

- [ ] Build to a known path, install, launch. **DB proof of the helper's write path:** note a merchant's row count, then (swipes unscriptable) verify via code review that all three sites call `store.duplicateTransaction`; launch sanity; human gesture pass post-merge — right-swipe a confirmed expense → indigo Duplicate → a new today-dated copy appears at the feed top.

---

## Self-review notes
- Spec coverage: helper (T1); three lists + menu twins + per-file error handling (T2); builds (T2 S4); verification (T3). ✓
- Consistency: `duplicateTransaction(_ txn: Tx) throws` called from all sites; eligibility guard `["expense","income"]` identical everywhere; Confirm ordering preserved (pending full-swipe still confirms). ✓
- No engine change; trailing edges untouched; "Duplicate" = new string (English fallback until next zh batch). ✓
