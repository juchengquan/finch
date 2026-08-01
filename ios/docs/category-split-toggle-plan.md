# Split-in-the-Category-subpage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move splitting out of a separate editor and into the Category subpage, as a toggle that turns the category tree multi-select, with the amounts pinned above it.

**Architecture:** All allocation arithmetic lives in one pure value type (`SplitAllocation`) with no SwiftUI in it, so every rule is unit-testable without driving a sheet. The subpage and the two transaction sheets become thin consumers of it. `SplitEditorView` is deleted at the end, once nothing references it. The FinchCore engine is not touched.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 deployment), XCTest + XCUITest, XcodeGen, `bun` for the i18n catalog scripts.

**Design doc:** `ios/docs/category-split-toggle-design.md` — read it first. It records *why* each rule is what it is, including three that fall out of existing code.

## Global Constraints

- Base branch is `feat/frontend`. Work on `feat/category-split-toggle`.
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`simctl`.
- Run `xcodegen generate --spec project.yml,project-mac.yml` from `ios/` after adding or removing any `.swift` file.
- **Never commit `Co-Authored-By` trailers.**
- Splits divide the transaction total. Amounts are magnitudes; the engine applies the sign.
- **Do not modify FinchCore.** `setTransactionSplits`, `TxSplit`, and the validation tolerances stay exactly as they are.
- A category id of `""` means Uncategorized in view code; convert to `nil` only at the write boundary.
- Money comparisons use the tolerances already in the codebase: `0.01 × rowCount` client-side.
- New user-facing strings must go through the catalog — see the i18n loop in Task 4.
- Every task ends green and committed. Run the task's own tests before committing; run `ios/scripts/ci-local.sh` at the end of Task 8.

## File Structure

| File | Responsibility |
|---|---|
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitAllocation.swift` | **new** — rows, ticking, pinning, even division, collapse, merge, validation. Pure. |
| `ios/FinchApp/Tests/FinchAppTests/SplitAllocationTests.swift` | **new** — the bulk of the coverage. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/CategoryPickerRow.swift` | modified — row drops the branch button; sheet gains toggle + pinned amounts + checkbox mode. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` | modified — feed split state through the row; re-divide on amount change. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift` | modified — staged splits; `save()` writes them. |
| `ios/FinchApp/Tests/FinchAppUITests/CategorySplitUITests.swift` | **new** — end-to-end, including the Edit-then-Cancel regression. |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitEditorView.swift` | **deleted** in Task 8. |

---

### Task 1: `SplitAllocation` — ticking and even division

**Files:**
- Create: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitAllocation.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/SplitAllocationTests.swift`

**Interfaces:**
- Produces: `struct SplitAllocation` with `init(total: Double)`, `mutating func tick(_ id: String)`, `var rows: [SplitAllocation.Row]` where `Row` has `id: String`, `amount: Double`, `pinned: Bool`; `var allocated: Double`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FinchApp

/// The split's arithmetic, with no sheet involved. Every allocation rule lives in
/// `SplitAllocation` precisely so it can be tested here instead of by tapping.
final class SplitAllocationTests: XCTestCase {

    // The first ticked category takes the whole transaction — splitting one way is
    // just categorising, and it means the second tick has something to halve.
    func test_firstTickTakesTheWholeTotal() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries")
        XCTAssertEqual(a.rows.map(\.id), ["groceries"])
        XCTAssertEqual(a.rows[0].amount, 58.20, accuracy: 0.001)
    }

    func test_secondTickSplitsItEvenly() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries"); a.tick("household")
        XCTAssertEqual(a.rows.map(\.amount), [29.10, 29.10])
    }

    // 58.20 / 3 does not divide evenly. The last row absorbs the remainder, which is
    // what the engine itself does with the final leg (Transactions.swift:57-62), so
    // the rows always add up to exactly the total rather than to 58.19.
    func test_unevenDivisionPutsTheRemainderOnTheLastRow() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b"); a.tick("c")
        XCTAssertEqual(a.rows.map(\.amount), [33.33, 33.33, 33.34])
        XCTAssertEqual(a.allocated, 100, accuracy: 0.0001)
    }

    func test_rowsKeepTickOrder() {
        var a = SplitAllocation(total: 30)
        a.tick("c"); a.tick("a"); a.tick("b")
        XCTAssertEqual(a.rows.map(\.id), ["c", "a", "b"])
    }

    // "" is the Uncategorized row — a legal split leg (the engine takes a nil category).
    func test_uncategorisedIsATickableRow() {
        var a = SplitAllocation(total: 10)
        a.tick("groceries"); a.tick("")
        XCTAssertEqual(a.rows.map(\.id), ["groceries", ""])
        XCTAssertEqual(a.rows.map(\.amount), [5, 5])
    }

    func test_tickingTwiceIsIdempotent() {
        var a = SplitAllocation(total: 10)
        a.tick("groceries"); a.tick("groceries")
        XCTAssertEqual(a.rows.count, 1)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate --spec project.yml,project-mac.yml
UDID=$(xcrun simctl list devices | grep "<your session sim> (" | grep -oE '[0-9A-F-]{36}')
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" \
  -only-testing:FinchAppTests/SplitAllocationTests 2>&1 | grep -iE "error:|passed|failed"
```

Expected: compile error, `cannot find 'SplitAllocation' in scope`. That is the correct failure — the type does not exist yet.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// The rows of a split and the arithmetic that keeps them adding up to the total.
///
/// Deliberately free of SwiftUI: this is where every allocation rule lives, so the
/// rules are tested directly instead of through a sheet. The view owns presentation
/// only. See `ios/docs/category-split-toggle-design.md` for why each rule is what it is.
struct SplitAllocation: Equatable {

    /// One ticked category. `pinned` means the user typed this amount, so it is held
    /// fixed and the unpinned rows divide whatever is left around it.
    struct Row: Equatable, Identifiable {
        /// Category id; `""` is the Uncategorized row (a `nil` leg to the engine).
        var id: String
        var amount: Double
        var pinned: Bool
    }

    private(set) var rows: [Row] = []
    private(set) var total: Double

    init(total: Double) { self.total = total }

    var allocated: Double { rows.reduce(0) { $0 + $1.amount } }
    func isTicked(_ id: String) -> Bool { rows.contains { $0.id == id } }

    mutating func tick(_ id: String) {
        guard !isTicked(id) else { return }
        rows.append(Row(id: id, amount: 0, pinned: false))
        redistribute()
    }

    /// Divide what the pinned rows have not claimed evenly across the unpinned ones,
    /// giving the last of them the remainder so the rows sum to the total exactly —
    /// the same trick the engine uses on its final leg rather than leaving a residue.
    private mutating func redistribute() {
        let claimed = rows.filter(\.pinned).reduce(0) { $0 + $1.amount }
        let free = rows.indices.filter { !rows[$0].pinned }
        guard !free.isEmpty else { return }
        let remaining = max(0, Self.round2(total - claimed))
        let share = Self.round2(remaining / Double(free.count))
        var used = 0.0
        for (n, i) in free.enumerated() {
            let isLast = n == free.count - 1
            rows[i].amount = isLast ? Self.round2(remaining - used) : share
            if !isLast { used += share }
        }
    }

    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Same command as Step 2. Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitAllocation.swift \
        ios/FinchApp/Tests/FinchAppTests/SplitAllocationTests.swift
git commit -m "feat(ios): SplitAllocation — ticking and even division"
```

---

### Task 2: Pinning, unticking, and total changes

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitAllocation.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/SplitAllocationTests.swift`

**Interfaces:**
- Consumes: `SplitAllocation` from Task 1.
- Produces: `mutating func setAmount(_ id: String, _ amount: Double?)` (a value pins the row, `nil` unpins it), `mutating func untick(_ id: String)`, `mutating func setTotal(_ total: Double)`.

- [ ] **Step 1: Write the failing test** (append to `SplitAllocationTests.swift`)

```swift
extension SplitAllocationTests {

    // Typing an amount pins that row; the others re-divide around it. This is the
    // rule that stops a later tick from wiping an amount the user chose.
    func test_typingAnAmountPinsThatRowAndTheOthersAbsorbTheRest() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries"); a.tick("household"); a.tick("dining")
        a.setAmount("dining", 10)
        XCTAssertEqual(a.rows.map(\.amount), [24.10, 24.10, 10.00])
        XCTAssertEqual(a.rows.map(\.pinned), [false, false, true])
        XCTAssertEqual(a.allocated, 58.20, accuracy: 0.0001)
    }

    func test_unpinningLetsTheRowFloatAgain() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 80)
        XCTAssertEqual(a.rows.map(\.amount), [80, 20])
        a.setAmount("a", nil)
        XCTAssertEqual(a.rows.map(\.amount), [50, 50])
    }

    func test_untickingGivesTheMoneyBackToTheUnpinnedRows() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries"); a.tick("household"); a.tick("dining")
        a.setAmount("dining", 10)
        a.untick("household")
        XCTAssertEqual(a.rows.map(\.id), ["groceries", "dining"])
        XCTAssertEqual(a.rows.map(\.amount), [48.20, 10.00])
    }

    // Changing the transaction's amount re-divides the unpinned rows. It must NOT
    // discard the split — AddTransactionSheet used to null pendingSplits outright on
    // any amount change, which silently threw the user's work away.
    func test_changingTheTotalRedividesTheUnpinnedRows() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 30)
        a.setTotal(200)
        XCTAssertEqual(a.rows.map(\.amount), [30, 170])
    }

    // Pinned rows are an explicit instruction, so they are never silently rescaled.
    // The unpinned rows go to zero and the imbalance is surfaced (see Task 3).
    func test_pinnedRowsExceedingTheTotalAreNotRescaled() {
        var a = SplitAllocation(total: 50)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 80)
        XCTAssertEqual(a.rows.map(\.amount), [80, 0])
    }

    // Every row pinned and one removed leaves a genuine shortfall. Nothing is
    // invented to cover it — the same as deleting a row in the old editor.
    func test_untickingWhenEveryRowIsPinnedLeavesAShortfall() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b"); a.tick("c")
        a.setAmount("a", 50); a.setAmount("b", 30); a.setAmount("c", 20)
        a.untick("b")
        XCTAssertEqual(a.allocated, 70, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run and watch fail**

Expected: `value of type 'SplitAllocation' has no member 'setAmount'`.

- [ ] **Step 3: Implement** (add to `SplitAllocation`)

```swift
    /// A value pins the row (the user typed it); `nil` unpins it so it floats again.
    mutating func setAmount(_ id: String, _ amount: Double?) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        if let amount {
            rows[i].amount = Self.round2(amount)
            rows[i].pinned = true
        } else {
            rows[i].pinned = false
        }
        redistribute()
    }

    mutating func untick(_ id: String) {
        rows.removeAll { $0.id == id }
        redistribute()
    }

    mutating func setTotal(_ total: Double) {
        self.total = total
        redistribute()
    }
```

- [ ] **Step 4: Run and watch pass**

- [ ] **Step 5: Commit**

```bash
git add -u && git commit -m "feat(ios): SplitAllocation — pinning, unticking, total changes"
```

---

### Task 3: Collapse, merge, and validation

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitAllocation.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/SplitAllocationTests.swift`

**Interfaces:**
- Produces: `var dominantCategoryId: String?`, `static func merging(_ splits: [(categoryId: String?, amount: Double)], total: Double) -> SplitAllocation`, `enum Problem`, `var problem: Problem?`, `var payload: [(categoryId: String?, amount: Double)]`.

- [ ] **Step 1: Write the failing test** (append)

```swift
extension SplitAllocationTests {

    // Toggling split off keeps the largest leg. Not arbitrary: it is the same rule
    // Projection.swift:136-148 uses to decide which category a split DISPLAYS, so the
    // survivor is the category the row was already showing.
    func test_dominantCategoryIsTheLargestLeg() {
        var a = SplitAllocation(total: 66.20)
        a.tick("groceries"); a.tick("household"); a.tick("dining")
        a.setAmount("groceries", 40); a.setAmount("household", 18.20); a.setAmount("dining", 8)
        XCTAssertEqual(a.dominantCategoryId, "groceries")
    }

    // The web writes to the same ledger with free-form split rows, so a stored
    // transaction can repeat a category. Checkboxes cannot express that, so repeats
    // fold together. Lossless: the only field separating two same-category legs is
    // `description`, which the UI never writes and the projection reads back as nil.
    func test_mergingFoldsRepeatedCategoriesAndSumsThem() {
        let a = SplitAllocation.merging([
            (categoryId: "groceries", amount: 10),
            (categoryId: "groceries", amount: 20),
            (categoryId: "household", amount: 28.20),
        ], total: 58.20)
        XCTAssertEqual(a.rows.map(\.id), ["groceries", "household"])
        XCTAssertEqual(a.rows.map(\.amount), [30.00, 28.20])
    }

    // Loaded rows are amounts the user set previously, so they arrive pinned and are
    // not re-divided the moment the sheet opens.
    func test_mergedRowsArrivePinned() {
        let a = SplitAllocation.merging([
            (categoryId: "a", amount: 70), (categoryId: "b", amount: 30),
        ], total: 100)
        XCTAssertEqual(a.rows.map(\.pinned), [true, true])
        XCTAssertEqual(a.rows.map(\.amount), [70, 30])
    }

    func test_mergingMapsNilCategoryToTheUncategorisedRow() {
        let a = SplitAllocation.merging([
            (categoryId: nil, amount: 5), (categoryId: "a", amount: 5),
        ], total: 10)
        XCTAssertEqual(a.rows.map(\.id), ["", "a"])
    }

    // Fewer than two ticked is a plain single-category transaction, which is legal —
    // and is what the engine demands, since it rejects a one-row split outright.
    func test_fewerThanTwoRowsIsLegal() {
        var a = SplitAllocation(total: 100)
        XCTAssertNil(a.problem)
        a.tick("a")
        XCTAssertNil(a.problem)
    }

    func test_twoRowsThatAddUpAreLegal() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        XCTAssertNil(a.problem)
    }

    // The toggle is usable before an amount is entered; this is what stops Confirm,
    // and the reason has to be sayable in the sheet.
    func test_noTotalYetIsReportedAsNeedsAmount() {
        var a = SplitAllocation(total: 0)
        a.tick("a"); a.tick("b")
        XCTAssertEqual(a.problem, .needsAmount)
    }

    func test_pinnedRowsThatDoNotAddUpAreReported() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 80); a.setAmount("b", 5)
        XCTAssertEqual(a.problem, .sumMismatch)
    }

    // Zero-amount rows drop out, so two ticks with only one funded is "needs two".
    func test_onlyOneFundedRowIsReportedAsNeedsTwo() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 100); a.setAmount("b", 0)
        XCTAssertEqual(a.problem, .needsTwo)
    }

    func test_payloadDropsZeroRowsAndMapsUncategorised() {
        var a = SplitAllocation(total: 100)
        a.tick(""); a.tick("b"); a.tick("c")
        a.setAmount("", 60); a.setAmount("b", 40); a.setAmount("c", 0)
        let p = a.payload
        XCTAssertEqual(p.count, 2)
        XCTAssertNil(p[0].categoryId)
        XCTAssertEqual(p[1].categoryId, "b")
    }
}
```

- [ ] **Step 2: Run and watch fail**

- [ ] **Step 3: Implement** (add to `SplitAllocation`)

```swift
    /// Why Confirm is blocked, or nil when the selection is writable.
    enum Problem: Equatable {
        /// Two-plus ticked but the transaction has no amount to divide yet.
        case needsAmount
        /// Two-plus ticked but fewer than two carry a positive amount.
        case needsTwo
        /// Funded rows do not add up to the total.
        case sumMismatch
    }

    private var funded: [Row] { rows.filter { $0.amount > 0 } }

    var problem: Problem? {
        // Fewer than two ticked is not a split at all — it is a plain single-category
        // transaction, which is legal and is all the engine will accept below two.
        guard rows.count >= 2 else { return nil }
        guard total > 0 else { return .needsAmount }
        guard funded.count >= 2 else { return .needsTwo }
        let sum = funded.reduce(0) { $0 + $1.amount }
        // Same tolerance the split editor used, and looser than the engine's own.
        guard abs(sum - total) <= 0.01 * Double(funded.count) else { return .sumMismatch }
        return nil
    }

    /// The category a collapse keeps — the largest leg, matching the rule the
    /// projection already uses to pick the category a split displays.
    var dominantCategoryId: String? {
        rows.max { $0.amount < $1.amount }?.id
    }

    /// What gets written. Zero rows drop out; `""` becomes a nil (uncategorised) leg.
    var payload: [(categoryId: String?, amount: Double)] {
        funded.map { (categoryId: $0.id.isEmpty ? nil : $0.id, amount: $0.amount) }
    }

    /// Load stored splits, folding repeats into one row each. Rows arrive PINNED:
    /// they are amounts the user set before, and must not be re-divided on open.
    static func merging(_ splits: [(categoryId: String?, amount: Double)], total: Double) -> SplitAllocation {
        var out = SplitAllocation(total: total)
        for s in splits {
            let id = s.categoryId ?? ""
            if let i = out.rows.firstIndex(where: { $0.id == id }) {
                out.rows[i].amount = round2(out.rows[i].amount + abs(s.amount))
            } else {
                out.rows.append(Row(id: id, amount: round2(abs(s.amount)), pinned: true))
            }
        }
        return out
    }
```

- [ ] **Step 4: Run and watch pass** — all of `SplitAllocationTests` (≈23 tests).

- [ ] **Step 5: Commit**

```bash
git add -u && git commit -m "feat(ios): SplitAllocation — collapse, merge, validation"
```

---

### Task 4: The subpage — toggle, checkbox tree, pinned amounts

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/CategoryPickerRow.swift`

**Interfaces:**
- Consumes: `SplitAllocation`; the existing `CategoryTreeRow`, `flattenCategories`, `categoryForest`.
- Produces: `CategoryPickerSheet` gains `splitting: Binding<SplitAllocation>?` and `currency: String`. `nil` ⇒ today's single-select sheet, unchanged.

**Reuse note:** the checkbox tree already exists — `CategoryMultiPickerSheet` in `CategoryMultiPickerRow.swift` renders exactly this using the same shared `CategoryTreeRow`. Copy its tick handling; do not invent a new row view.

- [ ] **Step 1: Add the sheet's split mode**

Extend `CategoryPickerSheet`. Keep the existing single-select path untouched when `splitting == nil`.

```swift
    /// The sheet has no store today and needs one for `displayNative` (which is also
    /// what makes the amounts honour privacy mode).
    @EnvironmentObject private var store: FinchStore
    /// Non-nil ⇒ this sheet can also split. The toggle drives it; nil means the
    /// plain single-select picker that Settings › Categories and ScheduledSheet use.
    var splitting: Binding<SplitAllocation>? = nil
    /// Currency for the amount fields; only read in split mode.
    var currency: String = ""
    @State private var splitOn = false
    @State private var amountText: [String: String] = [:]
```

Adding `@EnvironmentObject` means every presentation of this sheet must have `FinchStore` in the environment. It is presented from within the transaction sheets, which do — but check the Settings › Categories and `ScheduledSheet` call sites at runtime, not just at compile time: a missing environment object traps only when the view renders.

Sheet body, above the searchable list:

```swift
    if let splitting {
        Section {
            Toggle("Split across categories", isOn: $splitOn)
        }
        if splitOn {
            Section {
                ForEach(splitting.wrappedValue.rows) { row in
                    HStack {
                        Text(name(of: row.id))
                        Spacer(minLength: 8)
                        HStack(spacing: 2) {
                            Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                            TextField("0.00", text: amountBinding(row.id))
                                .numericInput(amountBinding(row.id))
                                .keyboardType(.decimalPad).fixedSize()
                        }
                    }
                }
                LabeledContent("Allocated",
                               value: "\(store.displayNative(splitting.wrappedValue.allocated, currency: currency)) / \(store.displayNative(splitting.wrappedValue.total, currency: currency))")
                    .foregroundStyle(splitting.wrappedValue.problem == nil ? .primary : .secondary)
                if let problem = splitting.wrappedValue.problem {
                    Text(message(for: problem)).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }
```

Rules to implement alongside it:

- Tree rows are `isSelected: splitOn ? alloc.isTicked(id) : id == staged`, and `onTap` ticks/unticks in split mode, stages in single mode.
- `amountBinding(id)` reads `amountText[id]` falling back to the formatted row amount, and on commit calls `setAmount(id, DecimalInput.parse(text))` — an unparseable or emptied field calls `setAmount(id, nil)` to unpin.
- **Turning the toggle off** collapses: `staged = alloc.dominantCategoryId ?? staged`, then clear the allocation.
- **Turning the toggle on** seeds from the current single selection: `alloc.tick(staged)` when `staged` is non-empty, so the category you already picked becomes the first row and holds the whole total.
- Confirm is `.disabled(splitOn && splitting?.wrappedValue.problem != nil)` — the toolbar sits outside the `if let splitting` block, so it unwraps optionally.

- [ ] **Step 2: Give the new controls accessibility identifiers**

The UI tests in Tasks 6–7 address these exact strings, so add them now, following the
existing `addtx.*` convention (`AddTransactionSheet.swift:306,312`):

| Control | Identifier |
|---|---|
| The toggle | `category.splitToggle` |
| A row's amount field | `category.splitAmount.<index>` — index, not category id: a UI test cannot know the seeded ids |
| The Allocated line | `category.allocated` |

- [ ] **Step 3: Add the strings to the catalog**

New user-facing strings: `"Split across categories"` (already exists as an accessibility label — reuse the key), `"Allocated"`, and one message per `Problem` case, e.g. `"Enter an amount to split."`, `"Give at least two categories an amount."`, `"Splits must add up to the transaction total."`

```bash
cd ios && bun run scripts/build-xcstrings.ts
git diff --stat -- FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings
```

**Commit the catalog with the code.** The guard diffs against `HEAD`, so an intentional `.xcstrings` change fails CI until it is committed.

- [ ] **Step 4: Build both platforms**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" 2>&1 | grep -iE "error:|BUILD"
xcodebuild build -project FinchMac.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD"
```

macOS matters here: `.keyboardType` is iOS-only and will fail `FinchMac` if it escapes an `#if os(iOS)`.

- [ ] **Step 5: Eyeball it on the simulator**

Build, install, open Add → Category, flip the toggle, tick two categories. Confirm the amounts halve, the tree still expands, and the existing single-select path is unchanged with the toggle off.

- [ ] **Step 6: Commit**

```bash
git add -u && git commit -m "feat(ios): the Category subpage can split"
```

---

### Task 5: The Category row drops the branch button

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/CategoryPickerRow.swift`

**Interfaces:**
- Produces: `CategoryPickerRow` gains `splitting: Binding<SplitAllocation>?` and `currency: String`; **removes** `splitEnabled` and `onSplit`. `splitSummary` stays.

- [ ] **Step 1: Replace the trailing button**

Delete the `arrow.triangle.branch` button (`:46-58`). `trailing:` becomes just `FieldRowChevron()`. The row's tap always opens the sheet now — including when split, where the sheet opens with the toggle already on (`splitOn = splitting?.wrappedValue.rows.count ?? 0 >= 2`).

- [ ] **Step 2: Confirm the three other call sites still compile untouched**

They pass no split state, so they keep the plain picker for free:

```bash
cd ios && rg -n -F "CategoryPickerRow(" --type swift
# expect: CategoriesView.swift:507, ScheduledSheet.swift:97, ScheduledSheet.swift:107
#         + the two transaction sheets (fixed in Tasks 6-7)
```

- [ ] **Step 3: Build** — the two transaction sheets will fail here because they still pass `onSplit`. That is expected; Tasks 6 and 7 fix them. If you want a green build at this boundary, do Tasks 5–7 as one commit.

- [ ] **Step 4: Commit** (with Tasks 6–7 if the build must stay green)

---

### Task 6: Add sheet wiring

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift`

- [ ] **Step 1: Swap the state**

Replace `@State private var pendingSplits: [SplitEditorView.DraftSplit]?` (`:64`) with `@State private var splitAlloc = SplitAllocation(total: 0)`.

- [ ] **Step 2: Re-divide on amount change instead of discarding**

`:215` currently reads `.onChange(of: amount) { _, _ in pendingSplits = nil }` — it throws the whole split away on any keystroke in the amount field. Replace with:

```swift
            .onChange(of: amount) { _, newValue in
                // Re-divide rather than discard: the old sheet nulled the split on any
                // amount edit, so typing a corrected total silently lost the split.
                splitAlloc.setTotal(abs(DecimalInput.parse(newValue) ?? 0))
            }
```

- [ ] **Step 3: Pass split state to the row, delete the split sheet**

`:308-311` loses `splitEnabled:`/`onSplit:` and gains `splitting: $splitAlloc, currency: …`. Delete the `.sheet(isPresented: $showingSplit)` block at `:216-223` and the `showingSplit` state. Refunds pass `splitting: nil`.

- [ ] **Step 4: Write from the allocation**

At `:624`, `if let eid, let splits = pendingSplits` becomes a check on `splitAlloc.payload` having ≥2 entries, sending `splitAlloc.payload`.

- [ ] **Step 5: Add the UI test**

Create `ios/FinchApp/Tests/FinchAppUITests/CategorySplitUITests.swift`:

```swift
import XCTest

/// End-to-end cover for splitting from the Category subpage. The allocation rules
/// themselves are unit-tested in `SplitAllocationTests`; these drive the WIRING —
/// that ticking reaches the allocation, and that the allocation reaches the ledger.
final class CategorySplitUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws { app?.terminate(); app = nil }

    /// The floating add button, the same entry point `TabChromeUITests` uses.
    func openAddSheet() {
        let fab = app.buttons["Add Transaction"]
        XCTAssertTrue(fab.waitForExistence(timeout: 30), "no add-transaction button")
        fab.tap()
    }

    func enterAmount(_ text: String) {
        let field = app.textFields["addtx.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "no amount field")
        field.tap()
        field.typeText(text)
    }

    func openCategorySubpage() {
        let row = app.descendants(matching: .any).matching(identifier: "addtx.category").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no category row")
        row.tap()
    }

    var splitToggle: XCUIElement { app.switches["category.splitToggle"] }
    var allocated: XCUIElement { app.staticTexts["category.allocated"] }

    func turnSplitOn() {
        XCTAssertTrue(splitToggle.waitForExistence(timeout: 15), "no split toggle")
        splitToggle.tap()
        XCTAssertEqual(splitToggle.value as? String, "1", "the toggle did not switch on")
    }

    func tickCategory(_ name: String) {
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no category named \(name)")
        row.tap()
    }

    func confirmSheet() { app.buttons["Confirm"].firstMatch.tap() }

    // Ticking two categories divides the amount with no typing, and the split
    // survives all the way to the saved transaction.
    func testSplittingAcrossTwoCategoriesKeepsTheTotal() throws {
        openAddSheet()
        enterAmount("100")
        openCategorySubpage()
        turnSplitOn()
        tickCategory("Groceries")
        tickCategory("Household")

        // Two ticks, no typing: evenly divided and therefore already balanced.
        XCTAssertTrue(allocated.waitForExistence(timeout: 10), "no allocated line")
        XCTAssertTrue(allocated.label.contains("100"), "allocated reads \(allocated.label)")

        confirmSheet()

        // Back on the form, the Category row names both halves.
        let row = app.descendants(matching: .any).matching(identifier: "addtx.category").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Groceries") && row.label.contains("Household"),
                      "the category row does not show both splits: \(row.label)")
    }
}
```

If `splitToggle.tap()` proves flaky, press it instead (`press(forDuration: 0.25)`) — switches on this project have needed a held press when driven synthetically. The `XCTAssertEqual(value, "1")` above is there to catch that rather than let the test sail on with the toggle still off.

- [ ] **Step 6: Build, run the test, commit**

---

### Task 7: Edit sheet — staged splits, and `save()` writes them

**This is the task that can put wrong legs in the ledger. Do the failing test first, genuinely.**

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/EditTransactionSheet.swift`
- Modify: `ios/FinchApp/Tests/FinchAppUITests/CategorySplitUITests.swift`

- [ ] **Step 1: Write the regression test FIRST and watch it fail against today's build**

```swift
extension CategorySplitUITests {

    /// Opens the first transaction in the Activity list for editing.
    func openFirstTransaction() {
        app.buttons["All Transactions"].firstMatch.tap()
        let firstRow = app.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 20), "no transactions to edit")
        firstRow.tap()
    }

    func openCategorySubpageInEdit() {
        let row = app.descendants(matching: .any).matching(identifier: "edittx.category").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no category row in the edit sheet")
        row.tap()
    }

    // Splits used to be written the moment the split editor was confirmed, so
    // cancelling the Edit sheet reverted your notes and date but silently KEPT your
    // splits. Staging them makes Cancel mean cancel.
    func testCancellingTheEditSheetDiscardsSplitChanges() throws {
        openFirstTransaction()
        let categoryRow = app.descendants(matching: .any).matching(identifier: "edittx.category").firstMatch
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 15))
        let before = categoryRow.label

        openCategorySubpageInEdit()
        turnSplitOn()
        tickCategory("Groceries")
        tickCategory("Household")
        confirmSheet()

        // Cancel the EDIT sheet — the split must never have reached the ledger.
        app.buttons["Cancel"].firstMatch.tap()

        // Reopen and assert the category is exactly what it was.
        openFirstTransaction()
        let after = app.descendants(matching: .any).matching(identifier: "edittx.category").firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 15))
        XCTAssertEqual(after.label, before,
                       "cancelling the edit sheet still applied the split")
    }
}
```

**Two things this step depends on.** `EditTransactionSheet`'s category rows carry no
accessibility identifier today — add `edittx.category` to both of them (`:147` and
`:189`), matching the `addtx.*` convention. And confirm the edit sheet's dismiss control
is actually labelled `Cancel`; if it is an `xmark` like the picker sheets, address it the
same way they do.

Run this against `HEAD` before touching `save()`. If it passes before your change, it is
not testing the behaviour — fix the test, not the code.

- [ ] **Step 2: Make `isSplit` staged**

`:56` currently reads the stored transaction:

```swift
    private var isSplit: Bool { (liveTxn.splits?.count ?? 0) >= 2 }
```

It has to reflect the staged allocation instead. It gates four things — the amount field and category patch (`save():409`), reclassification (`:88`), and the section branches at `:127`, `:143`, `:211`. Check every one after changing it.

- [ ] **Step 3: Seed the allocation from the stored splits**

It must be seeded in `init(txn:)` — a `@State` default cannot reference `txn`. The init
already does exactly this for the other fields (`:71-77`), so follow that shape:

```swift
    @State private var splitAlloc: SplitAllocation          // seeded in init

    init(txn: Tx) {
        …
        _splitAlloc = State(initialValue: .merging(
            (txn.splits ?? []).map { (categoryId: $0.categoryId, amount: $0.amount) },
            total: abs(txn.nativeAmount ?? txn.amount)))
    }
```

`merging` handles the repeated-category case; rows arrive pinned so opening the sheet does not re-divide them.

- [ ] **Step 4: Teach `save()` to write splits**

`save():409` short-circuits with `if !isSplit` and never touches categories when split. It now needs, after the `updateTransaction` apply:

```swift
        // Splits are staged like every other field and land in the same save, so
        // cancelling the sheet leaves the ledger untouched.
        if splitAlloc.payload.count >= 2 {
            let payload: [JSONValue] = splitAlloc.payload.map { .object([
                "categoryId": $0.categoryId.map(JSONValue.string) ?? .null,
                "amount": .double($0.amount)]) }
            try store.apply(.setTransactionSplits, Args(["id": .string(txn.id), "splits": .array(payload)]))
        } else if (txn.splits?.count ?? 0) >= 2 {
            // Collapsed back to a single category — clear the legs.
            try store.apply(.setTransactionSplits, Args(["id": .string(txn.id), "splits": .array([])]))
        }
```

- [ ] **Step 5: Add the collapse UI test**

```swift
    // Toggling split off keeps the largest leg — the same category the row was
    // already displaying, per Projection.swift's dominant-leg rule.
    //
    // 100 across three rows is 33.33 / 33.33 / 33.34: the LAST row takes the
    // remainder and is therefore the largest, with nothing typed. That keeps the
    // test deterministic without depending on which categories the seed provides.
    func testTogglingSplitOffKeepsTheLargestCategory() throws {
        openAddSheet()
        enterAmount("100")
        openCategorySubpage()
        turnSplitOn()
        tickCategory("Groceries")
        tickCategory("Household")
        tickCategory("Dining")

        splitToggle.tap()
        XCTAssertEqual(splitToggle.value as? String, "0", "the toggle did not switch off")
        confirmSheet()

        let row = app.descendants(matching: .any).matching(identifier: "addtx.category").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Dining"),
                      "collapse did not keep the largest leg — row reads \(row.label)")
        XCTAssertFalse(row.label.contains("Groceries"), "collapse left more than one category")
    }
```

- [ ] **Step 6: Run the tests, watch them pass, commit**

---

### Task 8: Retire `SplitEditorView`, then full CI

**Files:**
- Delete: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitEditorView.swift`

- [ ] **Step 1: Confirm nothing references it**

```bash
cd ios && rg -n -F "SplitEditorView" --type swift
```

Expected: no hits outside the file itself. `SplitShellVC`, `SplitDisplayMode`, and `SplitSelectionUITests` are `UISplitViewController` and must NOT be touched — a naming collision only.

- [ ] **Step 2: Delete and regenerate**

```bash
git rm ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/SplitEditorView.swift
cd ios && xcodegen generate --spec project.yml,project-mac.yml
```

`SplitSummaryTests` covers `splitSummaryText`, which lives in `CategoryPickerRow.swift` and stays — that suite should still pass untouched.

- [ ] **Step 3: Full local CI**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ios/scripts/ci-local.sh --sim "<your session sim>"
```

All must pass: catalog reproducible, FinchCore `swift test`, FinchApp build+test, UIKit strings guard, extracted keys current, FinchMac, FinchWatch. If it reports the `.xcstrings` churned during the run, discard it as the summary instructs.

- [ ] **Step 4: Verify on the simulator by hand**

The engine-level split tests (`AddThenSplitTests`, `TagsSplitsTests`) prove the write path, but walk the flows once: split from Add; edit an existing split; toggle off and confirm the largest survives; cancel an Edit and confirm nothing moved; check Settings › Categories' Parent picker and ScheduledSheet still show no toggle.

- [ ] **Step 5: Commit and open the PR**

```bash
git commit -m "refactor(ios): retire SplitEditorView"
git push -u origin feat/category-split-toggle
gh pr create --base feat/frontend --title "feat(ios): split moves into the Category subpage"
```

---

## Notes for whoever picks this up

- **The pure type is the point.** If you find yourself reaching for allocation arithmetic inside a SwiftUI `body`, it belongs in `SplitAllocation` with a test in Task 1–3's suite.
- **Tasks 5–7 may need to land as one commit** to keep the build green, since Task 5 changes an API that 6 and 7 consume. Splitting them here is about review boundaries, not about forcing three commits.
- **The riskiest line in the whole change** is `EditTransactionSheet.save()`. Engine-level split behaviour is already covered by `AddThenSplitTests`, `TagsSplitsTests` and `LegMetadataTests` — if any of those break, the wiring is wrong, not the engine.
