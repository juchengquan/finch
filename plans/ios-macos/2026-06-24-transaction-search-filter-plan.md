# Transaction search & filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A filter sheet on the transaction feed (account · category · tag · status · type · date range · amount range) layered on the existing search, applied through the engine's `selectTransactions`.

**Architecture:** Add an optional `tagId` to `ListOptions`/`selectTransactions` (the rest is already supported). A new `TransactionFilterSheet` edits a `TxFilter` value type; `ActivityFeedView` adds a Filter button and routes `filter` + search through `selectTransactions`.

**Tech Stack:** Swift / SwiftUI, GRDB, XcodeGen.

Spec: `plans/ios-macos/2026-06-24-transaction-search-filter-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds (new file must be picked up).
- Engine tests: `cd ios/FinchCore && swift test`. App build: scheme `FinchApp`, `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Commits: **no `Co-Authored-By` trailer**.
- `tagId` is **optional, default-nil** ⇒ existing callers + web-parity selector fixtures unchanged ⇒ **`ParityTests` must stay green**. Single-tag only.
- PR targets `feat/frontend`.

---

### Task 1: Engine — optional `tagId` filter

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift` (`ListOptions`)
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (`selectTransactions`)
- Test: `ios/FinchCore/Tests/FinchCoreTests/SelectTransactionsTagTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FinchCore

final class SelectTransactionsTagTests: XCTestCase {
    private let txns = [
        Tx(id: "e1", merchant: "A", amount: -5, account: "a1", date: "2026-06-01", ledgerId: "l1", tags: ["t1"]),
        Tx(id: "e2", merchant: "B", amount: -5, account: "a1", date: "2026-06-02", ledgerId: "l1", tags: ["t2"]),
        Tx(id: "e3", merchant: "C", amount: -5, account: "a1", date: "2026-06-03", ledgerId: "l1", tags: nil),
    ]

    func test_tagFilter_keepsOnlyTagged() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", tagId: "t1"))
        XCTAssertEqual(out.map(\.id), ["e1"])
    }

    func test_noTagFilter_unchanged() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1"))
        XCTAssertEqual(Set(out.map(\.id)), ["e1", "e2", "e3"])
    }
}
```

- [ ] **Step 2: Run — expect compile failure (no `tagId` yet)**

Run: `cd ios/FinchCore && swift test --filter SelectTransactionsTagTests 2>&1 | tail -15`
Expected: FAIL — `ListOptions` has no `tagId` argument.

- [ ] **Step 3: Add `tagId` to `ListOptions`**

In `Models.swift`, in `struct ListOptions`, after `public var maxAmount: Double?` add:

```swift
    public var tagId: String?
```

Add `tagId: String? = nil` as the **last** init parameter (so existing calls are unaffected). Change the init signature's final line from:

```swift
                maxAmount: Double? = nil, limit: Int? = nil, offset: Int? = nil) {
```
to:
```swift
                maxAmount: Double? = nil, limit: Int? = nil, offset: Int? = nil,
                tagId: String? = nil) {
```
and add `self.tagId = tagId` to the init body (e.g. on the `self.limit = limit; self.offset = offset` line):

```swift
        self.limit = limit; self.offset = offset; self.tagId = tagId
```

- [ ] **Step 4: Apply the filter in `selectTransactions`**

In `Selectors.swift`, after the `maxAmount` filter line
(`if let hi = opts.maxAmount { out = out.filter { abs($0.amount) <= hi } }`) add:

```swift
        if let tag = opts.tagId { out = out.filter { ($0.tags ?? []).contains(tag) } }
```

- [ ] **Step 5: Run — expect PASS**

Run: `cd ios/FinchCore && swift test --filter SelectTransactionsTagTests 2>&1 | tail -15`
Expected: both PASS.

- [ ] **Step 6: Full engine suite incl. ParityTests**

Run: `cd ios/FinchCore && swift test 2>&1 | tail -8`
Expected: all pass (optional field, default nil ⇒ ParityTests green). If ParityTests fail, STOP and report.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Project/Models.swift \
        ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/SelectTransactionsTagTests.swift
git commit -m "feat(ios): selectTransactions optional tagId filter"
```

---

### Task 2: `TransactionFilterSheet` + `TxFilter`

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift`

**Interfaces — Produces:** `struct TxFilter` (with `isActive`, `fromYMD`, `toYMD`); `struct TransactionFilterSheet { init(filter: Binding<TxFilter>) }`.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import FinchCore

/// The filter state for the transaction feed. Value type; `fromYMD`/`toYMD` convert
/// the picked dates to the "yyyy-MM-dd" strings `ListOptions` expects.
struct TxFilter: Equatable {
    var direction: String? = nil       // nil = all, "in", "out"
    var accountId: String? = nil
    var categoryId: String? = nil
    var tagId: String? = nil
    var status: String? = nil          // nil = all, "pending", "confirmed"
    var from: Date? = nil
    var to: Date? = nil
    var minAmount: Double? = nil
    var maxAmount: Double? = nil

    var isActive: Bool {
        direction != nil || accountId != nil || categoryId != nil || tagId != nil
            || status != nil || from != nil || to != nil || minAmount != nil || maxAmount != nil
    }

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    var fromYMD: String? { from.map { Self.ymd.string(from: $0) } }
    var toYMD: String? { to.map { Self.ymd.string(from: $0) } }
}

/// Edits a `TxFilter` in a sheet (apply on Done; Cancel discards).
struct TransactionFilterSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TxFilter

    @State private var draft: TxFilter
    @State private var minText: String
    @State private var maxText: String
    @State private var useFrom: Bool
    @State private var useTo: Bool
    @State private var fromDate: Date
    @State private var toDate: Date

    init(filter: Binding<TxFilter>) {
        _filter = filter
        let f = filter.wrappedValue
        _draft = State(initialValue: f)
        _minText = State(initialValue: f.minAmount.map { String(format: "%g", $0) } ?? "")
        _maxText = State(initialValue: f.maxAmount.map { String(format: "%g", $0) } ?? "")
        _useFrom = State(initialValue: f.from != nil)
        _useTo = State(initialValue: f.to != nil)
        _fromDate = State(initialValue: f.from ?? Date())
        _toDate = State(initialValue: f.to ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $draft.direction) {
                        Text("All").tag(String?.none)
                        Text("Money in").tag(String?.some("in"))
                        Text("Money out").tag(String?.some("out"))
                    }
                }
                Section {
                    Picker("Account", selection: $draft.accountId) {
                        Text("Any").tag(String?.none)
                        ForEach(store.accounts) { Text($0.name ?? "—").tag(String?.some($0.id)) }
                    }
                    Picker("Category", selection: $draft.categoryId) {
                        Text("Any").tag(String?.none)
                        ForEach(store.pickableCategories) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    if !store.tags.isEmpty {
                        Picker("Tag", selection: $draft.tagId) {
                            Text("Any").tag(String?.none)
                            ForEach(store.tags) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
                    Picker("Status", selection: $draft.status) {
                        Text("All").tag(String?.none)
                        Text("Pending").tag(String?.some("pending"))
                        Text("Confirmed").tag(String?.some("confirmed"))
                    }
                }
                Section("Date range") {
                    Toggle("From", isOn: $useFrom)
                    if useFrom { DatePicker("From date", selection: $fromDate, displayedComponents: .date).labelsHidden() }
                    Toggle("To", isOn: $useTo)
                    if useTo { DatePicker("To date", selection: $toDate, displayedComponents: .date).labelsHidden() }
                }
                Section("Amount range") {
                    HStack { Text("Min"); Spacer(); TextField("0", text: $minText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Max"); Spacer(); TextField("∞", text: $maxText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
                Section {
                    Button("Clear all", role: .destructive) {
                        draft = TxFilter(); minText = ""; maxText = ""; useFrom = false; useTo = false
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(); dismiss() }.bold()
                }
            }
        }
    }

    private func apply() {
        draft.from = useFrom ? fromDate : nil
        draft.to = useTo ? toDate : nil
        draft.minAmount = DecimalInput.parse(minText)
        draft.maxAmount = DecimalInput.parse(maxText)
        filter = draft
    }
}
```

- [ ] **Step 2: Build**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **` (the sheet compiles standalone; not yet referenced).
If `AccountRow.name` isn't optional, drop the `?? "—"`; if `DecimalInput.parse` lives elsewhere, match the call used in `AddTransactionSheet`.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift
git commit -m "feat(ios): TransactionFilterSheet + TxFilter"
```

---

### Task 3: Wire the filter into `ActivityFeedView`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

**Interfaces — Consumes:** `TxFilter`, `TransactionFilterSheet`, `Selectors.selectTransactions`, `ListOptions`.

- [ ] **Step 1: Add state**

Alongside the other `@State` vars in `ActivityFeedView` (e.g. after `@State private var searchQuery`), add:

```swift
    @State private var filter = TxFilter()
    @State private var showingFilter = false
```

- [ ] **Step 2: Add the Filter toolbar button**

In the `.toolbar { … }`, add a new item (e.g. right after the `Select` `ToolbarItem`):

```swift
            ToolbarItem(placement: .primaryAction) {
                Button { showingFilter = true } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
```

- [ ] **Step 3: Present the sheet**

Next to the other `.sheet(...)` modifiers, add:

```swift
        .sheet(isPresented: $showingFilter) { TransactionFilterSheet(filter: $filter) }
```

- [ ] **Step 4: Recompute when the filter changes**

Next to the existing `.onChange(of: searchQuery) { _, _ in recompute() }`, add:

```swift
        .onChange(of: filter) { _, _ in recompute() }
```

- [ ] **Step 5: Route through `selectTransactions`**

Replace the existing `filteredTxns()`:

```swift
    private func filteredTxns() -> [Tx] {
        guard !searchQuery.isEmpty else { return store.txns }
        let q = searchQuery.lowercased()
        return store.txns.filter { $0.merchant.lowercased().contains(q) }
    }
```
with:
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
(`selectTransactions` already scopes to the active ledger and applies the stable date-desc sort, replacing the old manual pass.)

- [ ] **Step 6: Build**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): feed filter button + selectTransactions routing"
```

---

### Task 4: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name; use AXPress on elements where coordinate taps miss.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Open the feed (Activity tab / Ledger home / All Transactions) → a **Filter** button shows; tapping opens the sheet.
  - Set **Type = Money out** + a **Category** → list narrows; the Filter icon shows **filled** (active). **Clear all** → resets.
  - **Tag** filter shows only tagged txns; **date range** + **amount range** narrow correctly; combine with the search box.
  - Filter present on all three feed surfaces.
  - Screenshot evidence to `/tmp/txfilter-<state>.png`.

- [ ] **Step 3 (no commit):** report; if any check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: engine tagId + test + ParityTests (T1), TxFilter + sheet w/ all controls + Clear (T2), feed Filter button + active badge + selectTransactions routing + onChange (T3), manual on all surfaces (T4). ✓
- Type consistency: `TxFilter`/`fromYMD`/`toYMD`/`isActive`, `ListOptions(... tagId:)`, `Selectors.selectTransactions`, `store.accounts/pickableCategories/tags/activeLedgerId` consistent. ✓
- Parity: `tagId` optional/default-nil ⇒ fixtures unchanged. ✓
