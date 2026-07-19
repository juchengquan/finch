# Numeric Input Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Numeric text fields can only hold a valid numeric string, filtered live as the user types or pastes — on iOS, iPad, and macOS.

**Architecture:** A pure `DecimalInput.filter` strips invalid characters; two `Binding<String>` transforms (`decimalInput`/`integerInput`) run it in the setter. Every numeric `TextField` swaps `text: $x` → `text: $x.decimalInput` (or `.integerInput`). `DecimalInput.parse` gets a comma-decimal normalization so filter and parse agree.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 floor); XCTest; XcodeGen; `xcodebuild`.

## Global Constraints

- **Worktree / branch:** `/tmp/finch-num` on `feat/ios-numeric-input` (off `origin/feat/frontend`). PR targets `feat/frontend`.
- **Environment:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`xcodegen`; run `xcodegen generate` (from `/tmp/finch-num/ios`) after adding a file. Sim `ios-finch2`; iOS `-derivedDataPath /tmp/dd-cat`, mac `/tmp/dd-catmac`.
- **Commits:** no `Co-Authored-By` trailer. Conventional `feat(ios): …` subjects.
- **No engine/schema change** (do not touch `FinchCore`). FinchApp only.
- **Filter rules (verbatim):** decimal = optional leading `-`, ASCII digits, and the **last** separator (`.` or `,`) as the decimal point with earlier separators dropped (grouping collapses); everything else stripped; no reformatting; intermediate states (`-`, `.`) preserved. Integer = optional leading `-` + digits only.
- **Negatives allowed on every field** (uniform; no per-field config).

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchApp/Sources/FinchApp/Common/DecimalInput.swift` | 1 | `filter` + `parse` comma-normalize + `Binding` extensions |
| `ios/FinchApp/Tests/FinchAppTests/DecimalInputTests.swift` | 1 (create) | filter + parse unit tests |
| 12 write-screen files (below) | 2 | wrap each numeric field's binding |

---

### Task 1: `DecimalInput.filter` + parse normalize + `Binding` transforms

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/DecimalInput.swift`
- Create: `ios/FinchApp/Tests/FinchAppTests/DecimalInputTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `DecimalInput.filter(_ s: String, allowsDecimal: Bool) -> String`; an updated `DecimalInput.parse(_:) -> Double?`; and `extension Binding where Value == String { var decimalInput: Binding<String>; var integerInput: Binding<String> }`. Task 2 wraps field bindings with `.decimalInput` / `.integerInput`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchApp/Tests/FinchAppTests/DecimalInputTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class DecimalInputTests: XCTestCase {
    // MARK: filter — decimal
    func test_keeps_plain_decimal() {
        XCTAssertEqual(DecimalInput.filter("12.34", allowsDecimal: true), "12.34")
    }
    func test_strips_letters_and_symbols() {
        XCTAssertEqual(DecimalInput.filter("1a2b.3c", allowsDecimal: true), "12.3")
        XCTAssertEqual(DecimalInput.filter("$1 234", allowsDecimal: true), "1234")
    }
    func test_keeps_comma_separator() {
        XCTAssertEqual(DecimalInput.filter("1,5", allowsDecimal: true), "1,5")
    }
    func test_last_separator_wins_grouping_collapses() {
        XCTAssertEqual(DecimalInput.filter("1,234.50", allowsDecimal: true), "1234.50")
        XCTAssertEqual(DecimalInput.filter("1.234,50", allowsDecimal: true), "1234,50")
        XCTAssertEqual(DecimalInput.filter("1.2.3", allowsDecimal: true), "12.3")
    }
    func test_leading_minus_kept_midstring_dropped() {
        XCTAssertEqual(DecimalInput.filter("-5.5", allowsDecimal: true), "-5.5")
        XCTAssertEqual(DecimalInput.filter("5-3", allowsDecimal: true), "53")
        XCTAssertEqual(DecimalInput.filter("--5", allowsDecimal: true), "-5")
    }
    func test_intermediate_states_preserved() {
        XCTAssertEqual(DecimalInput.filter("-", allowsDecimal: true), "-")
        XCTAssertEqual(DecimalInput.filter(".", allowsDecimal: true), ".")
        XCTAssertEqual(DecimalInput.filter("", allowsDecimal: true), "")
    }
    // MARK: filter — integer
    func test_integer_strips_separators() {
        XCTAssertEqual(DecimalInput.filter("12.5", allowsDecimal: false), "125")
        XCTAssertEqual(DecimalInput.filter("1,2a3", allowsDecimal: false), "123")
        XCTAssertEqual(DecimalInput.filter("-7", allowsDecimal: false), "-7")
    }
    // MARK: parse — comma normalize (locale-independent)
    func test_parse_dot_and_comma() {
        XCTAssertEqual(DecimalInput.parse("1.5"), 1.5)
        XCTAssertEqual(DecimalInput.parse("1,5"), 1.5)
        XCTAssertEqual(DecimalInput.parse("0,89"), 0.89)
        XCTAssertEqual(DecimalInput.parse("-5"), -5)
        XCTAssertEqual(DecimalInput.parse("1000"), 1000)
    }
    func test_parse_empty_and_junk_nil() {
        XCTAssertNil(DecimalInput.parse(""))
        XCTAssertNil(DecimalInput.parse("abc"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /tmp/finch-num/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/DecimalInputTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `cannot find 'filter' in scope` (and the parse comma cases fail against the current parse).

- [ ] **Step 3: Implement `filter`, the `Binding` transforms, and the parse normalize**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/Common/DecimalInput.swift` with:

```swift
import SwiftUI

/// Locale-aware parse + live input filtering for numeric text fields.
enum DecimalInput {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f
    }()

    /// Parse decimal text to a Double. The input carries at most one separator (the
    /// filter guarantees it), so a lone comma is normalized to a dot first — this
    /// makes comma-decimal users parse correctly regardless of device locale. Falls
    /// back to the locale formatter last (for any grouping-formatted seed strings).
    static func parse(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if !t.contains("."), t.contains(",") {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        if let d = Double(t) { return d }
        return formatter.number(from: t)?.doubleValue
    }

    /// Strip a live text-field string to a valid numeric string. Keeps an optional
    /// leading "-" and ASCII digits; for decimals, keeps the LAST separator ("." or
    /// ",") as the decimal point and drops earlier separators (so pasted grouping
    /// like "1,234.50" collapses to "1234.50", while a typed "1,5" stays "1,5").
    /// Everything else is removed. Does NOT reformat; intermediate "-"/"." survive.
    static func filter(_ s: String, allowsDecimal: Bool) -> String {
        let negative = s.first == "-"
        var kept = s.filter { ($0.isASCII && $0.isNumber) || (allowsDecimal && ($0 == "." || $0 == ",")) }
        if allowsDecimal, let lastSep = kept.lastIndex(where: { $0 == "." || $0 == "," }) {
            let intPart = kept[..<lastSep].filter { $0 != "." && $0 != "," }
            let fracPart = kept[kept.index(after: lastSep)...]
            kept = intPart + String(kept[lastSep]) + fracPart
        }
        return (negative ? "-" : "") + kept
    }
}

extension Binding where Value == String {
    /// A decimal-only mirror of this string binding: the setter runs
    /// `DecimalInput.filter(_, allowsDecimal: true)` so the field can only hold a
    /// valid decimal string. Reads pass through unchanged.
    var decimalInput: Binding<String> {
        Binding(get: { wrappedValue },
                set: { wrappedValue = DecimalInput.filter($0, allowsDecimal: true) })
    }
    /// Integer-only mirror (optional leading "-", digits, no separator).
    var integerInput: Binding<String> {
        Binding(get: { wrappedValue },
                set: { wrappedValue = DecimalInput.filter($0, allowsDecimal: false) })
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /tmp/finch-num/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/DecimalInputTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (10 tests). The existing call sites (which use `text: $x`, not the new transforms yet) compile unchanged.

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-num && git add ios/FinchApp/Sources/FinchApp/Common/DecimalInput.swift ios/FinchApp/Tests/FinchAppTests/DecimalInputTests.swift && git commit -m "feat(ios): DecimalInput.filter + numeric Binding transforms + comma-decimal parse"
```

---

### Task 2: Wrap every numeric field binding

Mechanical: for each field below, change the `TextField`'s `text:` argument by appending `.decimalInput` (decimal) or `.integerInput` (integer). Nothing else on the line changes (keyboardType, frame, alignment all stay). Edit the exact `text: <binding>` fragment shown.

**Files & edits:**

- [ ] **Step 1: Decimal fields — apply `.decimalInput`**

Change `text: <X>` → `text: <X>.decimalInput` in each:

- `WriteScreens/SplitEditorView.swift` — `text: $row.amount` → `text: $row.amount.decimalInput`
- `WriteScreens/BudgetSheet.swift` — `text: $amount` → `text: $amount.decimalInput`; and `text: $rolloverCap` → `text: $rolloverCap.decimalInput`
- `WriteScreens/BudgetDetailView.swift` — `text: $amount` → `text: $amount.decimalInput`
- `WriteScreens/AccountSheet.swift` — `text: $openingBalance` → `text: $openingBalance.decimalInput`
- `WriteScreens/EditTransactionSheet.swift` — in `transferAmountRow`, `TextField("0.00", text: text)` → `text: text.decimalInput`; and `text: $amountText` → `text: $amountText.decimalInput`
- `WriteScreens/AddTransactionSheet.swift` — `text: $amount` → `text: $amount.decimalInput`; and in `transferAmountRow`, `TextField("0.00", text: text)` → `text: text.decimalInput`
- `WriteScreens/HoldingsView.swift` — `text: $shares`, `text: $costBasis`, `text: $lastPrice`, `text: $price` each get `.decimalInput`
- `WriteScreens/TransactionFilterSheet.swift` — `text: $minText` and `text: $maxText` each get `.decimalInput`
- `WriteScreens/ScheduledSheet.swift` — `text: $amount` → `text: $amount.decimalInput`
- `WriteScreens/ReconcileSheet.swift` — `text: $statementBalance` and `text: $addAmount` each get `.decimalInput`
- `PowerTools/RulesManagerView.swift` — `TextField("Amount", text: c.value)` → `text: c.value.decimalInput`; and `TextField("and", text: c.value2)` → `text: c.value2.decimalInput`
- `WriteScreens/CurrenciesView.swift` — `text: $rate` → `text: $rate.decimalInput`

- [ ] **Step 2: Integer fields — apply `.integerInput`**

- `WriteScreens/ScheduledSheet.swift` — `text: $installmentTotal` → `text: $installmentTotal.integerInput`
- `PowerTools/RulesManagerView.swift` — `TextField("Day (1–31)", text: c.value)` → `text: c.value.integerInput` (the "Day (1–31)" placeholder distinguishes it from the "Amount" `c.value` above)

- [ ] **Step 3: Build FinchApp**

```bash
cd /tmp/finch-num/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`. (If a `text: $x` fragment isn't found, the binding name differs — grep the file for `keyboardType(.decimalPad)`/`.numberPad` and wrap that TextField's `text:` argument.)

- [ ] **Step 4: Build FinchMac (the key motivation — no `.decimalPad` there)**

```bash
cd /tmp/finch-num/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-catmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Confirm no numeric TextField was missed**

```bash
cd /tmp/finch-num && grep -rn "keyboardType(.decimalPad)\|keyboardType(.numberPad)" ios/FinchApp/Sources/FinchApp 2>/dev/null | grep -v "decimalInput\|integerInput" | grep "TextField" || echo "all inline-binding numeric fields wrapped"
```

Expected: only the multi-line fields (where `text:` is on a preceding line — SplitEditorView, BudgetSheet rolloverCap, AccountSheet, both `transferAmountRow`s) may still print here since their `keyboardType` line has no `text:`; visually confirm each of those preceding `TextField(... text: …)` lines now carries `.decimalInput`.

- [ ] **Step 6: Run the DecimalInput tests (regression)**

```bash
cd /tmp/finch-num/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/DecimalInputTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /tmp/finch-num && git add -A ios/FinchApp/Sources/FinchApp/WriteScreens ios/FinchApp/Sources/FinchApp/PowerTools && git commit -m "feat(ios): live numeric filtering on all amount/rate/balance fields"
```

---

## Manual sim verification (controller / human, after Task 2)

On `ios-finch2` (and ideally FinchMac, where it matters most): open the Add sheet, focus Amount, and via a hardware keyboard / paste try `12a3.4x`, `1,234.56`, `--5`, `abc` — the field should hold only `123.4`, `1234.56`, `-5`, `` respectively. Spot-check a balance field (negative allowed) and the two integer fields (no separator).

## Out of scope

Reformatting-as-you-type, per-field decimal caps, per-field negative config, commit-time error overhaul, web.

## Self-Review

**Spec coverage:** live-sanitizing binding (Task 1 `filter` + `Binding` transforms); decimal rules incl. last-separator grouping-collapse (Task 1 `filter`); integer rules (Task 1); negatives everywhere (uniform — the transforms don't strip a leading `-`); parse comma-normalize (Task 1 `parse`); all ~23 fields wrapped (Task 2); no UIKit (pure SwiftUI binding); tests (Task 1); FinchApp + FinchMac builds (Task 2). All covered.

**Placeholder scan:** none — complete code and exact per-field edits.

**Type consistency:** `filter(_:allowsDecimal:) -> String`, `parse(_:) -> Double?`, and the `Binding.decimalInput`/`.integerInput` computed properties defined in Task 1 are used with those exact names in Task 2's wraps and in the tests. The 21 decimal + 2 integer split matches the enumerated fields.
