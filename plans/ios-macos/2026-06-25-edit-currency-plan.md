# Edit Transaction currency picker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Edit form change a transaction's currency (expense/income/refund single-leg), mirroring the Add form.

**Architecture:** A currency `Picker` whose selection folds into the Edit sheet's existing `updateTransaction` patch. UI-only — the engine already handles a `currency` patch.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-edit-currency-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — `EditTransactionSheet` is shared.
- Commits: **no `Co-Authored-By` trailer**.
- No engine/DB/parity changes (the `currency` patch is pre-existing). Currency picker: expense/income/refund, non-split only. PR targets `feat/frontend`.

---

### Task 1: Currency picker in the Edit sheet

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

- [ ] **Step 1: Add state**

After `@State private var showingRefundPicker = false`, add:

```swift
    @State private var currencyCode: String
```

- [ ] **Step 2: Initialize it in `init`**

In `init(txn:)`, after `_refundedTxId = State(initialValue: txn.refundedTransactionId)`, add:

```swift
        _currencyCode = State(initialValue: txn.currency ?? "")
```
(Empty means "use the account currency"; defaulted in `.onAppear` at Step 5 where `store` is available.)

- [ ] **Step 3: Add `accountCurrency` + `currencyOptions` computed vars**

Near the other computed vars (e.g. after `originalNative` / `isSplit`), add:

```swift
    private var accountCurrency: String {
        store.accounts.first { $0.id == accountId }?.currency ?? store.displayCurrency
    }
    private var currencyOptions: [String] {
        var set = Set(store.accounts.compactMap { $0.currency })
        set.formUnion(store.exchangeRates.map { $0.currency })
        set.insert(accountCurrency)
        return set.sorted()
    }
```

- [ ] **Step 4: Add the picker to the Amount & category section**

In the non-split `Section("Amount & category")`, after the Amount `HStack { … }`, add:

```swift
                        if txn.kind != "transfer", currencyOptions.count > 1 {
                            Picker("Currency", selection: $currencyCode) {
                                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                            }
                        }
```

- [ ] **Step 5: Default the currency on appear**

The view already has `.onAppear { attachments = store.attachments(for: txn.id) }`. Replace it with:

```swift
            .onAppear {
                attachments = store.attachments(for: txn.id)
                if currencyCode.isEmpty { currencyCode = accountCurrency }
            }
```

- [ ] **Step 6: Fold currency into the save patch**

In `save()`, after the `account` patch line
(`if txn.kind != "transfer", !accountId.isEmpty, accountId != txn.account { patch["account"] = .string(accountId) }`), add:

```swift
        if txn.kind != "transfer", !currencyCode.isEmpty, currencyCode != (txn.currency ?? accountCurrency) {
            patch["currency"] = .string(currencyCode)
        }
```

- [ ] **Step 7: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.
(If `AccountRow.currency` isn't optional, drop `.compactMap`→`.map`; if `ExchangeRate.currency` differs, match its use in `AddTransactionSheet.swift`'s `currencyOptions`.)

- [ ] **Step 8: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "feat(ios): Edit sheet — currency picker (expense/income/refund)"
```

---

### Task 2: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name; use AXPress where coordinate taps miss.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(For the picker to appear, the ledger needs >1 currency — e.g. an account or an exchange rate in another currency. Add one in Power Tools › Exchange rates if needed.)

- [ ] **Step 2: Verify**
  - Open an expense in **Edit** → a **Currency** picker appears (pre-set to the transaction's currency) when other currencies/rates exist.
  - Change the currency → save → reopen: the transaction is now that currency (foreign-currency entry; figures reconvert). Changing back to the account currency drops the foreign denomination.
  - A **transfer** and a **split** show **no** currency picker.
  - Screenshot evidence to `/tmp/editccy-<state>.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: currency state+init (T1 S1-S2), options mirroring Add (T1 S3), gated picker (T1 S4), onAppear default (T1 S5), save patch composing with account change (T1 S6), cross-platform build (T1 S7), manual incl. transfer/split exclusion (T2). ✓
- Type consistency: `currencyCode`, `accountCurrency`, `currencyOptions`, `txn.currency`/`accountId`, `patch["currency"]` consistent with the #283 account picker. ✓
- No engine change (currency patch pre-existing). ✓
