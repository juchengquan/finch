# Guided reconcile session CP2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add quick-add-missing (add → auto-clear) and confirm-and-clear (pending) to the guided `ReconcileSheet`.

**Architecture:** FinchApp UI only — two additions to the existing CP1 `ReconcileSheet`. No engine/selector change; uses `applyReturningId(.addTransaction)`, `.setCleared`, `.confirmTransaction`.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), XcodeGen, XCTest.

## Global Constraints

- **No engine/selector change.** Quick-add: `store.applyReturningId(.addTransaction, …)` → `store.apply(.setCleared, ["id", "cleared": true])`. Confirm-and-clear: `.confirmTransaction(["id"])` → `.setCleared(true)`.
- Quick-add posts **uncategorized** (omit `categoryId`), **statement date** (`AppDate.isoDay.string(from: date)`), reconcile account, **status confirmed**, signed amount (`addIsExpense ? −abs : +abs`).
- "To confirm" section above the confirmed Transactions list, only when pending exist (`filter { $0.pending == true }`).
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. `xcodegen generate` if needed. FinchApp tests via `xcodebuild test`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. No new unit tests (UI wiring of already-tested actions).
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift` (both tasks).

---

### Task 1: Quick-add a missing transaction

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift`

**Interfaces:**
- Consumes: `store.applyReturningId(_:_:) -> String?`, `.addTransaction`, `.setCleared`, `DecimalInput.parse`, `AppDate.isoDay`.

- [ ] **Step 1: Add state**

In `ReconcileSheet`, after `@State private var errorMessage: String?` (line 13), add:
```swift
    @State private var addMerchant = ""
    @State private var addAmount = ""
    @State private var addIsExpense = true
```

- [ ] **Step 2: Insert the quick-add section in `body`**

Between `trackerSection(a)` and `transactionsSection(a)` (currently lines 36–37), insert `quickAddSection(a)`:
```swift
                    trackerSection(a)
                    quickAddSection(a)
                    transactionsSection(a)
```

- [ ] **Step 3: Add the `quickAddSection` view + `quickAdd`**

Add to `ReconcileSheet` (e.g. after `transactionsSection`):
```swift
    @ViewBuilder private func quickAddSection(_ a: AccountRow) -> some View {
        Section("Add missing transaction") {
            Picker("Type", selection: $addIsExpense) {
                Text("Expense").tag(true)
                Text("Income").tag(false)
            }.pickerStyle(.segmented)
            TextField("Merchant", text: $addMerchant)
            HStack {
                Text("Amount"); Spacer()
                TextField("0.00", text: $addAmount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Button("Add") { quickAdd(a) }
                .disabled(DecimalInput.parse(addAmount) == nil)
        }
    }

    private func quickAdd(_ a: AccountRow) {
        errorMessage = nil
        guard let v = DecimalInput.parse(addAmount), v != 0 else { return }
        let signed = addIsExpense ? -abs(v) : abs(v)
        let args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(a.id),
            "amount": .double(signed),
            "merchant": .string(addMerchant.isEmpty ? "Reconcile" : addMerchant),
            "date": .string(AppDate.isoDay.string(from: date)), "status": .string("confirmed")]
        do {
            if let id = try store.applyReturningId(.addTransaction, Args(args)) {
                try store.apply(.setCleared, Args(["id": .string(id), "cleared": .bool(true)]))
            }
            addMerchant = ""; addAmount = ""
        } catch { errorMessage = i18nMessage(error) }
    }
```

- [ ] **Step 4: Build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift
git commit -m "feat(ios): reconcile quick-add missing transaction (add + auto-clear)"
```

---

### Task 2: Confirm-and-clear pending section

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift`

**Interfaces:**
- Consumes: `store.transactions(for:)`, `Tx.pending`, `.confirmTransaction`, `.setCleared`, `store.displayMoney(_:from:)`.

- [ ] **Step 1: Insert the pending section in `body`**

Between `quickAddSection(a)` and `transactionsSection(a)`, insert `pendingSection(a)`:
```swift
                    quickAddSection(a)
                    pendingSection(a)
                    transactionsSection(a)
```

- [ ] **Step 2: Add the `pendingSection` view + `confirmAndClear`**

Add to `ReconcileSheet`:
```swift
    @ViewBuilder private func pendingSection(_ a: AccountRow) -> some View {
        let pending = store.transactions(for: a.id).filter { $0.pending == true }
        if !pending.isEmpty {
            Section("To confirm (\(pending.count))") {
                ForEach(pending, id: \.id) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.merchant).lineLimit(1)
                            Text(t.date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.displayMoney(t.nativeAmount ?? t.amount, from: a.currency)).fontWeight(.medium)
                        Button("Confirm & clear") { confirmAndClear(t) }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
    }

    private func confirmAndClear(_ t: Tx) {
        errorMessage = nil
        do {
            try store.apply(.confirmTransaction, Args(["id": .string(t.id)]))
            try store.apply(.setCleared, Args(["id": .string(t.id), "cleared": .bool(true)]))
        } catch { errorMessage = i18nMessage(error) }
    }
```

- [ ] **Step 3: Build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Full FinchCore suite + macOS build**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: FinchCore all pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification on the simulator**

Open an account → Reconcile → enter a statement balance:
- **Add missing transaction** (pick Expense/Income, merchant, amount → Add): a new row appears in Transactions **already ticked** (green), and the tracker's Cleared/Difference + progress update.
- An account with a **pending** transaction shows a **"To confirm (N)"** section; tapping **Confirm & clear** removes it from there and it appears ticked in Transactions, with the tracker updating.
- Finish still works (Done when balanced).

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab accounts
```

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift
git commit -m "feat(ios): reconcile confirm-and-clear pending transactions"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-guided-reconcile-cp2-design.md`):
- Quick-add form (merchant + amount + expense/income) → `applyReturningId(.addTransaction)` (uncategorized, statement date, confirmed, signed) → `setCleared(newId, true)` → Task 1. ✓
- "To confirm (N)" pending section above the confirmed list + Confirm & clear (`confirmTransaction` + `setCleared`) → Task 2. ✓
- No engine/selector change; tracker updates via the live recompute; build iOS+macOS → Tasks 1-2. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `store.applyReturningId(.addTransaction, Args) -> String?` then `.setCleared(["id","cleared"])`; `.confirmTransaction(["id"])`; `store.transactions(for:)`/`Tx.pending/nativeAmount/amount/merchant/date`; `DecimalInput.parse`, `AppDate.isoDay`, `store.displayMoney(_:from:)` — all exist + used in CP1. New `@State` (addMerchant/addAmount/addIsExpense) referenced only in Task 1's section. ✓

---

## Out of scope

Inline category for the quick-added tx (uncategorized by design); engine/selector changes; the global account-picker reconcile entry. Completes the guided reconcile feature.
