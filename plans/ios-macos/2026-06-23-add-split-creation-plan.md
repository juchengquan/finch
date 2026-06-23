# Add Transaction: split creation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Add form (expense/income) split a new transaction across ≥2 categories in one flow.

**Architecture:** Refactor `SplitEditorView` to be transaction-agnostic (driven by a `Target` enum — `.existing(id:)` for Edit, `.draft(onSave:)` for Add — so `store` is only touched in `body`, never `init`). Add opens it in draft mode against the entered amount, stores the result, and on save runs `addTransaction` (→ id via the existing `applyReturningId`) then `setTransactionSplits(eid, …)`.

**Tech Stack:** Swift / SwiftUI, GRDB, XcodeGen.

Spec: `plans/ios-macos/2026-06-23-add-split-creation-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App build/test: scheme `FinchApp`, `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Commits: **no `Co-Authored-By` trailer**.
- **No engine changes** (`setTransactionSplits` + `applyReturningId` exist). Scope: **expense/income** only.
- **Edit must keep identical behavior** — the `SplitEditorView(txn:)` call site in `EditTransactionSheet` stays unchanged.
- PR targets `feat/frontend`.

---

### Task 1: FinchCore guardrail — add then split builds N legs

Locks the engine path the Add-split save relies on. The actions exist, so it **passes immediately**.

**Files:**
- Test: `ios/FinchCore/Tests/FinchCoreTests/AddThenSplitTests.swift` (create)

- [ ] **Step 1: Write the test**

```swift
import XCTest
import GRDB
@testable import FinchCore

final class AddThenSplitTests: XCTestCase {
    func test_addTransaction_thenSetTransactionSplits_buildsTwoCategoryLegs() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createCategory",
                        args: Args(["id": .string("c2"), "ledgerId": .string("l1"), "name": .string("Household"), "kind": .string("expense")]))
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-30),
            "merchant": .string("Market"), "categoryId": .string("c1"), "date": .string("2026-06-01")]))
        try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args([
            "id": .string(eid!),
            "splits": .array([
                .object(["categoryId": .string("c1"), "amount": .double(20)]),
                .object(["categoryId": .string("c2"), "amount": .double(10)]),
            ])]))
        let catLegs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [eid!])
        }
        XCTAssertEqual(catLegs, 2)
    }
}
```

- [ ] **Step 2: Run (expect PASS — guardrail on existing actions)**

Run: `cd ios/FinchCore && swift test --filter AddThenSplitTests 2>&1 | tail -15`
Expected: PASS. If the `createCategory` arg shape differs and the test errors on setup, read `Categories.swift`'s `createCategory` and fix the args (keep the assertion). If the assertion itself fails, STOP and report — the engine path differs from the design.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchCore/Tests/FinchCoreTests/AddThenSplitTests.swift
git commit -m "test(ios): addTransaction then setTransactionSplits builds N category legs (guardrail)"
```

---

### Task 2: Refactor `SplitEditorView` to be transaction-agnostic

Decouple from `Tx`; keep Edit identical. **Rewrite the whole file** (it's small).

**Files:**
- Rewrite: `ios/FinchApp/Sources/FinchApp/WriteScreens/SplitEditorView.swift`

**Interfaces — Produces:**
- `SplitEditorView.Target` (`.existing(id:)` | `.draft(onSave:)`)
- `init(txn: Tx)` (unchanged call site) and `init(total:isIncome:currency:initialSplits:target:editingExistingSplit:)`

- [ ] **Step 1: Replace the file contents**

```swift
import SwiftUI
import FinchCore

/// Split a transaction across ≥2 category legs. Amounts are magnitudes that must
/// sum to the total; the engine applies the sign. Transaction-agnostic: Edit drives
/// it with `.existing(id:)` (applies `setTransactionSplits`); Add drives it with
/// `.draft(onSave:)` (returns the splits to the caller). `store` is read only in
/// `body`, never `init`.
struct SplitEditorView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    typealias DraftSplit = (categoryId: String?, amount: Double)
    enum Target {
        case existing(id: String)
        case draft(onSave: ([DraftSplit]) -> Void)
    }

    private let target: Target
    private let total: Double
    private let isIncome: Bool
    private let currencyOverride: String?       // nil → fall back to store.baseCurrency
    private let editingExistingSplit: Bool      // controls "Remove split" visibility

    private struct Row: Identifiable { let id = UUID(); var categoryId: String; var amount: String }
    @State private var rows: [Row]
    @State private var errorMessage: String?

    private var displayCurrency: String { currencyOverride ?? store.baseCurrency }
    private var allocated: Double { rows.reduce(0) { $0 + (DecimalInput.parse($1.amount) ?? 0) } }
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { isIncome ? $0.kind == "income" : $0.kind != "income" }
    }

    /// Designated initializer (used by Add for draft mode).
    init(total: Double, isIncome: Bool, currency: String?,
         initialSplits: [DraftSplit]?, target: Target, editingExistingSplit: Bool = false) {
        self.total = total
        self.isIncome = isIncome
        self.currencyOverride = currency
        self.target = target
        self.editingExistingSplit = editingExistingSplit
        if let s = initialSplits, s.count >= 2 {
            _rows = State(initialValue: s.map { Row(categoryId: $0.categoryId ?? "", amount: String(format: "%g", abs($0.amount))) })
        } else if let first = initialSplits?.first {
            // Seed row 1 from the single source category + total; row 2 empty.
            _rows = State(initialValue: [
                Row(categoryId: first.categoryId ?? "", amount: String(format: "%g", abs(first.amount))),
                Row(categoryId: "", amount: ""),
            ])
        } else {
            _rows = State(initialValue: [Row(categoryId: "", amount: ""), Row(categoryId: "", amount: "")])
        }
    }

    /// Convenience for the Edit flow — unchanged call site `SplitEditorView(txn:)`.
    init(txn: Tx) {
        let alreadySplit = (txn.splits?.count ?? 0) >= 2
        let initial: [DraftSplit]? = alreadySplit
            ? txn.splits!.map { (categoryId: $0.categoryId, amount: abs($0.amount)) }
            : [(categoryId: txn.category, amount: abs(txn.nativeAmount ?? txn.amount))]
        self.init(total: abs(txn.nativeAmount ?? txn.amount),
                  isIncome: txn.amount > 0,
                  currency: txn.currency,
                  initialSplits: initial,
                  target: .existing(id: txn.id),
                  editingExistingSplit: alreadySplit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Transaction total", value: Money.format(total, currency: displayCurrency))
                    LabeledContent("Allocated", value: Money.format(allocated, currency: displayCurrency))
                        .foregroundStyle(abs(allocated - total) <= 0.01 ? .primary : .secondary)
                }
                Section("Splits") {
                    ForEach($rows) { $row in
                        HStack {
                            Picker("", selection: $row.categoryId) {
                                Text("Uncategorized").tag("")
                                ForEach(categories) { Text($0.name).tag($0.id) }
                            }.labelsHidden()
                            Spacer()
                            TextField("0.00", text: $row.amount)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    Button("Add split") { rows.append(Row(categoryId: "", amount: "")) }
                }
                if editingExistingSplit, case .existing = target {
                    Section {
                        Button("Remove split (single category)", role: .destructive) { removeSplit() }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let parsed: [DraftSplit] = rows.compactMap { r in
            guard let a = DecimalInput.parse(r.amount), a > 0 else { return nil }
            return (categoryId: r.categoryId.isEmpty ? nil : r.categoryId, amount: a)
        }
        guard parsed.count >= 2 else { errorMessage = "Add at least two splits with amounts."; return }
        let sum = parsed.reduce(0) { $0 + $1.amount }
        guard abs(sum - total) <= 0.01 * Double(parsed.count) else {
            errorMessage = "Splits must add up to \(Money.format(total, currency: displayCurrency))."
            return
        }
        switch target {
        case .draft(let onSave):
            onSave(parsed)
            dismiss()
        case .existing(let id):
            let payload: [JSONValue] = parsed.map { .object([
                "categoryId": $0.categoryId.map(JSONValue.string) ?? .null, "amount": .double($0.amount)]) }
            do { try store.apply(.setTransactionSplits, Args(["id": .string(id), "splits": .array(payload)])); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }

    private func removeSplit() {
        guard case .existing(let id) = target else { return }
        do { try store.apply(.setTransactionSplits, Args(["id": .string(id), "splits": .array([])])); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 2: Build + run the full app suite (Edit path must still work)**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD FAILED|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`. (`EditTransactionSheet`'s `SplitEditorView(txn:)` call is unchanged.)

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/SplitEditorView.swift
git commit -m "refactor(ios): SplitEditorView is transaction-agnostic (Target enum)"
```

---

### Task 3: Add-form integration — "Split…" + save

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

**Interfaces — Consumes:** `SplitEditorView(total:isIncome:currency:initialSplits:target:)`, `store.applyReturningId`, `setTransactionSplits`.

- [ ] **Step 1: Add state**

After `@State private var createCounterpartyOnSave = false`, add:

```swift
    @State private var pendingSplits: [SplitEditorView.DraftSplit]? = nil
    @State private var showingSplit = false
```

- [ ] **Step 2: Add the Split row + hide Category when split is active**

In `expenseIncomeFields`, replace the Category picker line:

```swift
            SearchablePickerRow(title: "Category",
                options: categories.map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
```

with:

```swift
            if pendingSplits == nil {
                SearchablePickerRow(title: "Category",
                    options: categories.map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
            }
            if DecimalInput.parse(amount) ?? 0 != 0 {
                Button {
                    showingSplit = true
                } label: {
                    HStack {
                        Text(pendingSplits == nil ? "Split…" : "Split across \(pendingSplits!.count) categories")
                        Spacer()
                        if pendingSplits != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
```

- [ ] **Step 3: Present the editor in draft mode**

In `AddTransactionSheet`'s `body`, alongside the other `.sheet`s (e.g. near the bottom of the view, after the existing sheets/toolbar), add:

```swift
            .sheet(isPresented: $showingSplit) {
                SplitEditorView(
                    total: abs(DecimalInput.parse(amount) ?? 0),
                    isIncome: kind == .income,
                    currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode,
                    initialSplits: pendingSplits ?? (categoryId.isEmpty ? nil : [(categoryId: categoryId, amount: abs(DecimalInput.parse(amount) ?? 0))]),
                    target: .draft(onSave: { pendingSplits = $0 }))
            }
```

- [ ] **Step 4: Clear pending splits when the amount changes**

Add an `.onChange(of: amount)` next to the existing `.onChange(of: merchant)` modifier:

```swift
            .onChange(of: amount) { _, _ in pendingSplits = nil }
```

- [ ] **Step 5: Apply the splits on save**

In `save()`'s expense/income branch, replace:

```swift
                let eid = try store.applyReturningId(.addTransaction, Args(args))
                if let eid, let photo = pickedPhoto {
                    Task { try? await AttachmentWriter.write(item: photo, entryId: eid, store: store) }
                }
```

with:

```swift
                let eid = try store.applyReturningId(.addTransaction, Args(args))
                if let eid, let splits = pendingSplits {
                    let payload: [JSONValue] = splits.map { .object([
                        "categoryId": $0.categoryId.map(JSONValue.string) ?? .null, "amount": .double($0.amount)]) }
                    try store.apply(.setTransactionSplits, Args(["id": .string(eid), "splits": .array(payload)]))
                }
                if let eid, let photo = pickedPhoto {
                    Task { try? await AttachmentWriter.write(item: photo, entryId: eid, store: store) }
                }
```

- [ ] **Step 6: Build**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift
git commit -m "feat(ios): Add form — create a split (expense/income)"
```

---

### Task 4: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name before taps.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Add → Expense, amount 30, tap **Split…** → editor opens with total 30 → allocate 20 + 10 across two categories → Save → back on Add the row shows "Split across 2 categories" and the Category picker is hidden → Save → open the tx in Edit: it shows "Split across 2 categories" with those legs.
  - After splitting, change the amount → the row resets to "Split…" (pending cleared).
  - Cancel the split sheet → normal single-category add.
  - Transfer/Adjust → no Split row.
  - **Edit regression:** open an existing tx → Split across categories… → still works (split / re-split / remove split).
  - Screenshot evidence to `/tmp/add-split-<state>.png`.

- [ ] **Step 3 (no commit):** report results; if any check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: editor refactor + Edit-unchanged via `init(txn:)` (T2), draft-mode open (T3 S3), Split row + hide-category (T3 S2), amount-clears-splits (T3 S4), add-then-setTransactionSplits save (T3 S5), engine path guardrail (T1), manual incl. Edit regression (T4). ✓
- Type consistency: `SplitEditorView.DraftSplit`, `Target.draft(onSave:)`/`.existing(id:)`, `pendingSplits`, `applyReturningId`, `setTransactionSplits` used consistently. ✓
- No engine changes; transfer/adjust untouched. ✓
