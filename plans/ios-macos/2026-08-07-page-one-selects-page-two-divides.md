# Page One Selects, Page Two Divides — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Money is divided in exactly one place. The account and category pickers become pure tick-lists; page 2 divides every split, not just the grid.

**Architecture:** `PurchaseFlow.page2` already returns `.notNeeded` / `.list` / `.grid` but only `.grid` navigates — the list case is handled by a second amount editor buried inside each picker sheet. This deletes that editor, routes `.list` to page 2 as well, and moves the validation with it.

**Tech Stack:** Swift 5.9 / SwiftUI / GRDB, XCTest. App target `ios/FinchApp`; `ios/FinchCore` is untouched.

## Global Constraints

- **Branch:** `feat/one-amount-editor`, cut from `origin/feat/frontend`.
- **STOP AT THE LOCAL GATE.** Do not push and do not open a PR. The deliverable is `ci-local.sh --full --all` printing `all checks passed`.
- **No `Co-Authored-By` trailer in commits.**
- **iOS only.** No changes under `frontend/`, and none in `ios/FinchCore` — this is presentation and app-side validation only.
- **No new user-facing strings.** Every message this plan needs already exists in the catalog; the three `SplitAllocation.Problem` messages are *reused*, not replaced. Do not add a key.
- **Build:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` **and** `PATH="$DEVELOPER_DIR/usr/bin:$PATH"`.
- **Simulator:** `ios-finch-splits`. Never touch a sim with another name.
- **The gate has fast and full modes.** `--all` alone runs FAST and skips the 33 UI tests. This plan changes navigation and deletes UI that UI tests drive, so the verdict must come from `./scripts/ci-local.sh --full --all`.
- **`FinchApp.xcodeproj` is generated and gitignored.** Run `xcodegen generate` after branching, or the build fails on unrelated missing types.
- After any `xcodebuild` run, discard catalog churn:
  `git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings`

---

## Background: two amount editors, and the one that has to go

Splitting a purchase asks for the same numbers in two places.

**Inside the picker.** `SearchablePickerRow`'s `splitSection` (`:249-296`) and
`CategoryPickerRow`'s (`:178-221`) each render: a per-row amount field, an
"Allocated X / Y" line, and a red reason when it does not add up. Confirm is
disabled while `splitting.problem != nil`.

**On page 2.** `PurchaseGridSection` renders the same idea for cells, and
`PurchaseGridPage` gates ✓ on the total.

Page 2 only exists for the grid, so today the picker's editor is load-bearing
for a one-axis split. Deleting it means routing `.list` to page 2 as well —
which `PurchaseFlow.page2` already models and nothing yet uses.

### What actually breaks

1. **The trigger.** `usesGrid` is `PurchaseFlow.page2(accounts: accountAlloc.payload.count, categories: splitAlloc.payload.count) == .grid`, and `payload` returns only FUNDED rows (`funded = rows.filter { $0.amount > 0 }`, `SplitAllocation.swift:90`). With no amounts in the picker every row is 0, `payload` is empty, and **page 2 becomes unreachable**. The shape decision must key off *ticked* rows (`rows.count`); `payload` stays what gets written.

2. **The collapse rule.** Turning a split off keeps the largest leg
   (`dominantId`, `SearchablePickerRow.swift:224`). At pick time there are no
   amounts, so "largest" is undefined — but a split REOPENED in the Edit sheet
   does have amounts, so the rule still means something there. Keep it, and
   break ties by **last ticked**, which is both the most recent expression of
   intent and what the existing UI test expects.

3. **The row's displayed value.** Confirm sets `selection` to `dominantId` while
   split (`:237`), so the collapsed row names one option. Same fix as (2).

4. **Validation has to move.** The three `Problem` messages are already
   translated. Page 2 should use `problem` rather than the blunter
   `isBalanced`, so the reason survives instead of being deleted.

### The one accepted regression

A two-category purchase is fully editable inside the picker today; it will now
need a **Next** tap. One extra tap on a common flow, in exchange for one amount
editor instead of two. Accepted deliberately by the user.

A single-category, single-account purchase is unaffected: `page2` returns
`.notNeeded` and ✓ still saves from page 1.

---

## File structure

| File | Responsibility after this plan |
|---|---|
| `PurchaseCells.swift` | `page2` keyed on ticked counts; `splitAxis(...)` says which axis a list divides. |
| `SplitAllocation.swift` | `dominantId` breaks ties by last ticked. Everything else unchanged. |
| `SearchablePickerRow.swift` | Tick-list only: no amount fields, no Allocated line, no validation, no `splitLocked` copy. |
| `CategoryPickerRow.swift` | The same, for categories. |
| `PurchaseGridPage.swift` | Renders a flat list when only one axis is split; ✓ reports `problem`'s reason. |
| `AddTransactionSheet.swift` / `EditTransactionSheet.swift` | `usesPage2` replaces `usesGrid`; the save gate collapses to one check. |
| `PurchaseCellsTests.swift`, `SplitAllocationTests.swift` (existing) | Extended for the new trigger and tie-break. |
| `CategorySplitUITests.swift` | Drives page 2 instead of the picker's amount fields. |

---

## Task 1: The shape decision stops depending on amounts

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseCells.swift`
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitAllocation.swift` — `dominantId` at `:107-109`
- Test: `ios/FinchApp/Tests/FinchAppTests/PurchaseCellsTests.swift`, `SplitAllocationTests.swift`

**Interfaces:**
- Produces: `PurchaseFlow.splitAxis(accounts:categories:) -> SplitAxis` (`.accounts` / `.categories` / `.both` / `.none`), and a `dominantId` that prefers the LAST maximal row.
- `PurchaseFlow.page2(accounts:categories:)` keeps its signature — callers pass ticked counts instead of funded counts, which is a caller change, not a signature change.

- [ ] **Step 1: Write the failing tests.** Append to `PurchaseCellsTests`:

```swift
    /// The shape follows what is TICKED, not what is funded.
    ///
    /// `payload` returns funded rows only, and the pickers no longer collect
    /// amounts — so keying the decision off it would leave page 2 unreachable
    /// for every new purchase, which is exactly the bug this guards.
    func test_theShapeFollowsTickedRowsNotFundedOnes() {
        var accounts = SplitAllocation(total: 0)   // no amount typed yet
        accounts.tick("a1"); accounts.tick("a2")
        var categories = SplitAllocation(total: 0)
        categories.tick("c1"); categories.tick("c2")

        XCTAssertTrue(accounts.payload.isEmpty, "nothing is funded yet")
        XCTAssertEqual(PurchaseFlow.page2(accounts: accounts.rows.count,
                                          categories: categories.rows.count), .grid)
    }

    /// Which axis a one-axis split divides — page 2 renders a flat list for it
    /// rather than N sections of one row each.
    func test_theSplitAxisNamesWhatIsBeingDivided() {
        XCTAssertEqual(PurchaseFlow.splitAxis(accounts: 1, categories: 3), .categories)
        XCTAssertEqual(PurchaseFlow.splitAxis(accounts: 3, categories: 1), .accounts)
        XCTAssertEqual(PurchaseFlow.splitAxis(accounts: 2, categories: 2), .both)
        XCTAssertEqual(PurchaseFlow.splitAxis(accounts: 1, categories: 1), .none)
    }
```

and to `SplitAllocationTests`:

```swift
    /// Turning a split off keeps the largest leg. With no amounts yet — which is
    /// every freshly ticked split now the pickers collect none — every row is
    /// equal, so the tie goes to the LAST ticked: the most recent choice, and
    /// the one the collapse UI test expects.
    func test_theDominantRowBreaksTiesByLastTicked() {
        var a = SplitAllocation(total: 0)
        a.tick("c1"); a.tick("c2"); a.tick("c3")
        XCTAssertEqual(a.dominantId, "c3", "all equal, so the newest wins")
    }

    /// A reopened split HAS amounts, and there the largest still wins outright.
    func test_theDominantRowIsStillTheLargestWhenAmountsExist() {
        var a = SplitAllocation.merging([(id: Optional("c1"), amount: 70),
                                         (id: Optional("c2"), amount: 30)], total: 100)
        XCTAssertEqual(a.dominantId, "c1")
        a.setAmount("c2", 90)
        XCTAssertEqual(a.dominantId, "c2", "the largest, not the newest")
    }
```

- [ ] **Step 2: Run them and record the failure.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests/PurchaseCellsTests \
  -only-testing:FinchAppTests/SplitAllocationTests test 2>&1 | grep -E "error:|Executed"
```
Expected: does not compile (`splitAxis` missing), and
`test_theDominantRowBreaksTiesByLastTicked` fails once it does — `max(by:)`
keeps the FIRST among equals.

- [ ] **Step 3: Add `splitAxis`.** In `PurchaseCells.swift`, inside `enum PurchaseFlow`, beside `page2`:

```swift
    /// Which axis a split divides. Page 2 lays a one-axis split out as a flat
    /// list; three cards against a single category would otherwise render as
    /// three sections of one row each, which reads as a grid that is not one.
    enum SplitAxis: Equatable { case none, accounts, categories, both }

    static func splitAxis(accounts: Int, categories: Int) -> SplitAxis {
        switch (accounts > 1, categories > 1) {
        case (true, true):   return .both
        case (true, false):  return .accounts
        case (false, true):  return .categories
        case (false, false): return .none
        }
    }
```

- [ ] **Step 4: Break `dominantId`'s tie towards the newest.** Replace it in `SplitAllocation.swift`:

```swift
    /// The row a collapse keeps — the largest leg, matching the rule the
    /// projection already uses to pick the category a split displays.
    ///
    /// **Ties go to the LAST ticked.** The pickers no longer collect amounts, so
    /// a freshly ticked split is all zeros and every row ties; the newest choice
    /// is the most recent thing the user actually said. A REOPENED split does
    /// carry amounts, and there the largest still wins outright.
    ///
    /// `max(by:)` cannot express this — it keeps the first among equals — so the
    /// scan is explicit.
    var dominantId: String? {
        var best: Row?
        for row in rows where best == nil || row.amount >= best!.amount { best = row }
        return best?.id
    }
```

- [ ] **Step 5: Run — both files green.** Same command as Step 2. Expected: 0 failures.

- [ ] **Step 6: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "refactor: the split shape follows what is ticked, not what is funded

payload returns funded rows only. The pickers are about to stop collecting
amounts, so keying the list/grid decision off it would leave page 2 unreachable
for every new purchase — the rows would all be zero and payload empty.

splitAxis names which axis a one-axis split divides, so page 2 can lay it out
as a flat list rather than N sections of one row each.

dominantId breaks ties towards the last ticked. A freshly ticked split is all
zeros and every row ties, so the newest choice — the most recent thing the user
said — wins; a reopened split carries real amounts and the largest still wins
outright. max(by:) keeps the first among equals and cannot express that."
```

---

## Task 2: The pickers become tick-lists

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SearchablePickerRow.swift` — `splitSection` `:249-296`, `message(for:)`, `amountBinding`, the `store` dependency, `Confirm`'s `.disabled`
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/CategoryPickerRow.swift` — the same members

**Interfaces:**
- Consumes: `SplitAllocation.tick/untick/rows`, `dominantId` from Task 1.
- Produces: pickers that stage a selection and nothing else. `splitting:` stays — the toggle still turns the list multi-select — but no amount reaches the binding from here.

**Delete, in both files:** the ticked-rows `Section` with its `TextField`s, the
`LabeledContent("Allocated")` line, the `problem` message block, the
`message(for:)` helper, `amountBinding`, and the now-unused `amountText` state.
Keep the toggle `Section`, and keep `splitCurrencyMismatch`'s message in
`SearchablePickerRow` — that is a currency rule, not an amount one.

- [ ] **Step 1: Strip `SearchablePickerRow`'s split section.** Replace `splitSection` with:

```swift
    /// The toggle. Turning it on makes the list multi-select; the AMOUNTS are
    /// page 2's job, so nothing here asks for one.
    ///
    /// This sheet used to host a second amount editor — per-row fields, an
    /// Allocated line and a blocking check — duplicating page 2 and disagreeing
    /// with it the moment either was edited. Page 1 selects; page 2 divides.
    @ViewBuilder private var splitSection: some View {
        Section {
            Toggle("Split across accounts", isOn: $splitOn)
                .accessibilityIdentifier("account.splitToggle")
            if splitOn, !splitCurrencyMismatch.isEmpty {
                Text("Only \(currency) accounts can be part of a split.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
```

Then delete `private static func message(for:)`, `private func amountBinding(...)`,
and `@State private var amountText: [String: String] = [:]`, and drop
`amountText.removeAll()` from the `onChange(of: splitOn)` body.

- [ ] **Step 2: Stop disabling Confirm.** In the same file's toolbar:

```swift
                    Button {
                        // Splitting still names a single option — the dominant leg —
                        // so the field stays meaningful even while split.
                        selection = splitOn ? (splitting?.wrappedValue.dominantId ?? staged) : staged
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Confirm")
                        .confirmCheckmarkStyle()
```

(The `.disabled(splitOn && splitting?.wrappedValue.problem != nil)` line goes:
there is nothing left in this sheet that can fail to add up.)

- [ ] **Step 3: Do the same to `CategoryPickerRow`.** Its `splitSection` becomes:

```swift
    /// The toggle. Turning it on makes the tree multi-select; the AMOUNTS are
    /// page 2's job, so nothing here asks for one. See `SearchablePickerRow`.
    @ViewBuilder private var splitSection: some View {
        Section {
            Toggle("Split across categories", isOn: $splitOn)
                .accessibilityIdentifier("category.splitToggle")
        }
    }
```

and delete its `message(for:)`, `amountBinding`, `amountText`, and its
Confirm `.disabled(...)` the same way.

- [ ] **Step 4: Drop the dead `splitLocked` plumbing.** Both sheets take
`splitLocked` and render "Turn off the category/account split first." It has
been `false` at every call site since the grid shipped (`categorySplitBlocked`
and `accountSplitBlocked` are literal `false` in `AddTransactionSheet.swift:222-223`),
because the engine now stores both axes. Remove the parameter from both
`*PickerRow` and `*PickerSheet`, and from every call site.

- [ ] **Step 5: Build.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`. Unused-variable warnings for `store` in either
sheet mean the `@EnvironmentObject` is now dead — remove it if so, keep it if
the row content still uses it.

- [ ] **Step 6: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "refactor: the pickers select, they no longer divide

Both picker sheets hosted a second amount editor — per-row fields, an Allocated
line and a blocking check — duplicating page 2 and disagreeing with it the
moment either was edited. Page 1 selects; page 2 divides.

Confirm is no longer disabled: nothing in these sheets can fail to add up.

splitLocked goes with them. It rendered \"turn off the other split first\" and
has been false at every call site since the grid shipped, because the engine
stores both axes now."
```

---

## Task 3: Page 2 divides every split

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseGridPage.swift`
- Create: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/PurchaseListSection.swift`

**Interfaces:**
- Consumes: `PurchaseFlow.splitAxis`, `SplitAllocation.problem`, `PurchaseFlow.cellKey`.
- Produces: `PurchaseGridPage` renders `PurchaseListSection` when `splitAxis` is `.accounts` or `.categories`, and `PurchaseGridSection` when `.both`. **Its signature does not change** — both sections resolve names from the store themselves, as `PurchaseGridSection` already does.

**Reuse the reason, do not re-word it.** ✓'s blocked state uses
`SplitAllocation.problem`, whose three messages already exist and are already
translated. Do not introduce a new string.

- [ ] **Step 1: Create the list section.**

```swift
import SwiftUI
import FinchCore

/// Page 2 for a ONE-axis split: divide a total across N things.
///
/// A flat section, not `PurchaseGridSection`. That renders one section per card
/// with a row per category, which is right for a grid and wrong here: three
/// cards against a single category would become three sections of one row each,
/// reading as a grid that is not one.
///
/// The cells are the same `SplitAllocation` either way — keyed
/// `"<account>|<category>"` — so the payload the sheet builds does not care
/// which of the two rendered it.
struct PurchaseListSection: View {
    @EnvironmentObject private var store: FinchStore
    @Binding var alloc: SplitAllocation
    /// One of these has a single member; the other is what is being divided.
    let accountIds: [String]
    let categoryIds: [String?]
    let currency: String

    var body: some View {
        Section {
            ForEach(rows, id: \.key) { row in
                HStack {
                    Text(row.label).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 2) {
                        Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                        TextField("0.00", text: amountBinding(row.key))
                            .numericInput(amountBinding(row.key))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .fixedSize()
                            .accessibilityIdentifier("split.amount.\(row.key)")
                    }
                }
            }
            LabeledContent("Allocated") {
                Text(verbatim: "\(store.displayNative(alloc.allocated, currency: currency)) / \(store.displayNative(alloc.total, currency: currency))")
            }
            .accessibilityIdentifier("split.allocated")
        }
    }

    private var rows: [(key: String, label: String)] {
        accountIds.flatMap { account in
            categoryIds.map { category in
                (PurchaseFlow.cellKey(account: account, category: category),
                 accountIds.count > 1 ? accountName(account) : categoryName(category))
            }
        }
    }

    // Resolved here from the store, exactly as `PurchaseGridSection` does — the
    // page does not need to know which kind of id it is holding.
    private func accountName(_ id: String) -> String {
        store.accounts.first { $0.id == id }?.name ?? id
    }
    private func categoryName(_ id: String?) -> String {
        guard let id else { return String(localized: "Uncategorized") }
        return store.categoryName(id) ?? String(localized: "Uncategorized")
    }

    private func amountBinding(_ key: String) -> Binding<String> {
        Binding(
            get: {
                guard let row = alloc.rows.first(where: { $0.id == key }) else { return "" }
                return row.amount == 0 ? "" : String(format: "%g", row.amount)
            },
            set: { alloc.setAmount(key, DecimalInput.parse($0)) })
    }
}
```

- [ ] **Step 2: Route page 2 by axis, and report the reason.** Replace `PurchaseGridPage`'s body:

```swift
    var body: some View {
        Form {
            if axis == .both {
                PurchaseGridSection(alloc: $alloc, accountIds: accountIds,
                                    categoryIds: categoryIds, currency: currency)
            } else {
                PurchaseListSection(alloc: $alloc, accountIds: accountIds,
                                    categoryIds: categoryIds, currency: currency)
            }
            if let problem = alloc.problem {
                // The reason ✓ is blocked, in the words the pickers used before
                // this page took the job over — already written, already
                // translated. Do not invent a new one.
                Section { Text(Self.message(for: problem, axis: axis)).font(.footnote).foregroundStyle(.red) }
            }
        }
        .finchSheetForm()
        .navigationTitle(Text(verbatim: store.displayNative(alloc.total, currency: currency)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSave) { Image(systemName: "checkmark") }
                    .accessibilityLabel("Save")
                    .confirmCheckmarkStyle()
                    .disabled(alloc.problem != nil)
                    .accessibilityIdentifier("grid.save")
            }
        }
    }

    private var axis: PurchaseFlow.SplitAxis {
        PurchaseFlow.splitAxis(accounts: accountIds.count, categories: categoryIds.count)
    }

    /// Both `needsTwo` wordings already exist in the catalog, one per axis —
    /// picking blind would tell someone splitting by category to give two
    /// ACCOUNTS an amount. A grid takes the category wording: `needsTwo` there
    /// means fewer than two funded cells, and the cells are the categories.
    private static func message(for problem: SplitAllocation.Problem,
                                axis: PurchaseFlow.SplitAxis) -> LocalizedStringKey {
        switch problem {
        case .needsAmount: return "Enter an amount to split."
        case .needsTwo:
            return axis == .accounts ? "Give at least two accounts an amount."
                                     : "Give at least two categories an amount."
        case .sumMismatch: return "Splits must add up to the transaction total."
        }
    }
```

- [ ] **Step 3: Build.** Same command as Task 2 Step 5. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit** with Task 4 — the two are one behavioural change and the sheets must route to the page for either to be exercised.

---

## Task 4: Both sheets route every split to page 2

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` — `usesGrid` `:227-230`, `categorySplitBlocked`/`accountSplitBlocked` `:222-223`, the destination, the save gate
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` — the same members

**Interfaces:**
- Consumes: `PurchaseFlow.page2`, `PurchaseFlow.splitAxis`, `PurchaseGridPage` (signature unchanged).
- Produces: nothing later tasks consume.

- [ ] **Step 1: Replace `usesGrid` with `usesPage2` in both sheets.**

```swift
    /// Whether the money is divided on page 2 — for ANY split, one axis or two.
    ///
    /// Counts TICKED rows, not `payload`: the pickers no longer collect amounts,
    /// so every row is zero until page 2 and `payload` would be empty.
    private var usesPage2: Bool {
        PurchaseFlow.page2(accounts: accountAlloc.rows.count,
                           categories: splitAlloc.rows.count) != .notNeeded
    }
```

In `AddTransactionSheet` also delete `categorySplitBlocked` and
`accountSplitBlocked` (both literal `false`) and their `splitLocked:` arguments.

- [ ] **Step 2: Point every `usesGrid` reference at `usesPage2`.** In both sheets that is the toolbar's Next/✓ choice, `openGrid()`, the `navigationDestination`, the save-path branch that builds cells, and the save gate. Pass the name resolver into the page:

```swift
            .navigationDestination(isPresented: $showingGrid) {
                PurchaseGridPage(
                    alloc: $gridAlloc,
                    accountIds: accountAlloc.rows.map(\.id),
                    categoryIds: splitAlloc.rows.map { $0.id.isEmpty ? nil : $0.id },
                    currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode,
                    onSave: save)
            }
```

**Note the id sources changed**: `accountAlloc.rows.map(\.id)` not
`accountAlloc.payload.map { ... }`, for the same reason as Step 1. In
`EditTransactionSheet` the currency fallback is `accountCurrency`, not
`currency(of: accountId)`.

- [ ] **Step 3: Collapse the save gate.** Both sheets currently branch on grid vs margins. With page 2 owning every split there is one check:

```swift
        // Page 2 owns every split now, so its cells are the only thing that can
        // fail to add up. The margin allocations are selection state — they carry
        // no amounts at all until page 2 fills them.
        if usesPage2, gridAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total.")
            return
        }
```

Delete the `accountAlloc.problem` / `splitAlloc.problem` gates entirely.

- [ ] **Step 4: Build both targets and run the unit tests.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests test 2>&1 | grep -E "error:|Executed [0-9]+ tests"
```
Expected: `BUILD SUCCEEDED`, 0 unit-test failures. The UI tests are expected to
FAIL at this point — Task 5 moves them.

- [ ] **Step 5: Commit Tasks 3 and 4 together.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: page 2 divides every split, not just the grid

PurchaseFlow.page2 has always returned .notNeeded/.list/.grid, and only .grid
navigated — the list case was handled by the picker's own amount editor. Now
both go to page 2: a flat list for one axis, the grid for two.

A one-axis split gets PurchaseListSection rather than the grid's one-section-
per-card layout, which would render three cards against a single category as
three sections of one row each — a grid that is not one.

The blocked reason comes from SplitAllocation.problem, in the words the pickers
used before this page took the job over. Already written, already translated.

The save gate collapses to one check: the margin allocations are selection state
now and carry no amounts until page 2 fills them."
```

---

## Task 5: The UI tests drive page 2

**Files:**
- Modify: `ios/FinchApp/Tests/FinchAppUITests/CategorySplitUITests.swift`

The three tests that type into `category.splitAmount.N` / read
`category.allocated` must move to page 2. The identifiers there are
`split.amount.<key>` and `split.allocated` (list) or `grid.cell.<key>` (grid),
and the page is reached by tapping **Next**.

- [ ] **Step 1: Add a helper for the new hop.** Beside `confirmSubpage()`:

```swift
    /// Page 1 selects; page 2 divides. Any split — one axis or two — now goes
    /// through this hop, where the picker used to collect the amounts itself.
    private func goToPageTwo() {
        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 15), "no Next button — the split did not register")
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "split.allocated")
                        .firstMatch.waitForExistence(timeout: 15),
                      "Next did not open page 2")
    }
```

- [ ] **Step 2: Update `testTickingTwoCategoriesDividesTheAmountEvenly`.** It asserts the even division; that now happens on page 2. Replace its assertion phase with `goToPageTwo()` followed by reading `split.amount.*`, keeping the same expected figures (two ticks over 100 → 50/50).

- [ ] **Step 3: Update `testCancellingTheEditSheetDiscardsSplitChanges`.** The flow gains the Next hop before Cancel. Cancel must still discard — dismissing from page 2 must leave the ledger untouched, which is the point of the test and worth keeping explicit in its comment.

- [ ] **Step 4: `testTogglingSplitOffKeepsTheLargestCategory` and `testClearingACategoryActuallyClearsIt` should need no change** — they collapse to a single category and never reach page 2. Run them first to confirm that prediction rather than assuming it.

- [ ] **Step 5: Run the whole UI class.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppUITests/CategorySplitUITests test 2>&1 | grep -E "passed \(|failed \(|error:"
```
Expected: 4 passed.

- [ ] **Step 6: Commit.**

```bash
git add ios/FinchApp
git commit -m "test(ios): the split UI tests drive page 2

The picker no longer collects amounts, so the tests that typed into
category.splitAmount.N and read category.allocated now take the Next hop and
assert on page 2.

Toggling split off and clearing a category never reach page 2 and are unchanged."
```

---

## Task 6: The local gate

**STOP HERE.** Do not push, do not open a PR.

- [ ] **Step 1: Confirm the base.**

```bash
git fetch -q origin && git rev-list --count HEAD..origin/feat/frontend
```
Expected `0`; rebase and re-run Task 5 Step 5 if not.

- [ ] **Step 2: Run the FULL gate.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  SIM_NAME=ios-finch-splits ./scripts/ci-local.sh --full --all
```
Expected: `all checks passed`. `--all` alone runs FAST and skips the 33 UI
tests, which are exactly what this plan rewrites — `fast checks passed` is not
an acceptable verdict here.

- [ ] **Step 3: Discard catalog churn and confirm the tree is clean.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git status --short
git diff --stat origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/
```
Expected: `git status` silent, and the second diff EMPTY — this plan touches
neither the web nor the engine.

- [ ] **Step 4: Report the gate verdict and the diffstat, and stop.**

---

## Out of scope

- **The engine.** No `ios/FinchCore` changes; the payload shape is unchanged.
- **The web.**
- **Removing the split TOGGLE.** It still distinguishes "one of these" from "several", which is a selection question, not an amount one.
- **Mixed-currency splits in the editor.** Still parked.
- **Rules.** Frozen, flagged for its own design review.

## Verification checklist

- [ ] `ci-local.sh --full --all` prints `all checks passed`
- [ ] Neither picker sheet contains an amount field, an Allocated line, or a blocked Confirm
- [ ] A two-category, one-account purchase reaches page 2 and saves correctly
- [ ] A two-account, one-category purchase renders as a FLAT list, not N one-row sections
- [ ] A 2×2 purchase still renders as the grid
- [ ] A one-category, one-account purchase shows ✓ on page 1 and never a Next
- [ ] Turning a split off keeps the last-ticked option when nothing is funded, and the largest when amounts exist
- [ ] Reopening a saved split in the Edit sheet still lands on page 2 with its stored amounts
- [ ] No new catalog key; `git status` shows no `.xcstrings` change
- [ ] `git diff origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/` is empty
