# Numeric input validation — design

**Date:** 2026-07-19
**Status:** Design agreed in a `/grill-me` interview; plan follows.
**Scope:** FinchApp UI + a small pure helper in `Common/DecimalInput.swift`. No
FinchCore/engine/schema change. No web change.

## Purpose

Numeric text fields (amounts, FX rates, shares, prices, balances, budgets, filter
min/max, day-of-month, installments…) accept **any** characters while typing.
`.decimalPad` is the only guard — and it does nothing on **macOS**, an iPad/Mac
**hardware keyboard**, or against **paste**. Invalid input then silently parses to
`0` at save (via `DecimalInput.parse(...) ?? 0`), which is a real correctness bug
(you can "enter" an amount that saves as zero). Add **live input filtering** so a
numeric field can only ever hold a valid numeric string.

## Approach

A **live-sanitizing binding** (chosen over commit-time validation and over a UIKit
`UITextField` representable). A pure `DecimalInput.filter(...)` strips invalid
characters; it's exposed as `Binding<String>` transforms whose *setter* filters
before the value is stored, so the field can only hold valid text. This runs
identically on iOS/iPad/macOS, handles paste, and — being a pure function — is fully
unit-testable. No UIKit (SwiftUI-first; see "Not UIKit" below).

## Decisions (from the interview)

1. **Decimal filter rules.** Keep: an optional leading `-`, digits `0–9`, and
   **exactly one** decimal separator — accept `.` **or** `,`, keep the **first** one
   typed, drop any subsequent separators. Strip everything else (letters, spaces,
   currency symbols, grouping/thousands separators). **No live decimal-place cap**
   (save-time rounding handles precision). **Filter only — never reformat while
   typing** (no inserting leading zeros, no grouping); display formatting stays at
   read time via `displayNative`. Intermediate states (`-`, `.`, `-.`) are allowed so
   typing isn't blocked.
2. **Integer filter rules.** Optional leading `-` + digits only; no separator.
3. **Negatives allowed on every field for now** (uniform; no per-field config).
   Lower-risk than restricting: minus is already typeable/parseable today, so this
   only ever *adds* filtering of clearly-invalid characters without changing any
   existing sign behavior. Per-field tightening (e.g. magnitudes vs. balances) is
   deferred.
4. **Parse parity.** `DecimalInput.parse` must interpret whatever the filter allows.
   It is already locale-aware with a `.` fallback; add a `,`→`.` fallback so a
   comma-decimal string (`"0,89"`) parses regardless of the device locale. Small,
   tested addition — keeps filter and parse consistent.
5. **Not UIKit.** The binding transform's only weakness is a rare cursor-jump on a
   *mid-string* edit; for short, append-typed numeric fields that's marginal, and a
   `UITextField`/`NSTextField` representable would mean two per-platform
   implementations, re-wiring TextField styling/focus, and a SwiftUI-first exception
   used in ~23 places. Escape hatch: swap a *single* field to a representable only if
   a concrete cursor problem later earns it.
6. **Scope.** Convert **all** numeric `TextField`s across the write screens in one
   PR (the ~21 `.decimalPad` fields + the ~2 `.numberPad` integer fields), each a
   one-word binding wrap. Piecemeal would leave inconsistent behavior users notice.

## Components

- **`Common/DecimalInput.swift`** (the only logic):
  - `static func filter(_ s: String, allowsDecimal: Bool) -> String` — the pure
    filter implementing decision 1/2.
  - Extend `parse(_:)` with the `,`→`.` fallback (decision 4).
  - `extension Binding where Value == String { var decimalInput: Binding<String> {…}
    var integerInput: Binding<String> {…} }` — getters pass through; setters run
    `filter(_, allowsDecimal:)`.
- **Write-screen files** (mechanical): wrap each numeric field's binding —
  `text: $x` → `text: $x.decimalInput` (decimal) or `text: $x.integerInput`
  (integer). No changes to `.keyboardType`, `.frame`, `.multilineTextAlignment`, or
  layout. The current set spans: `AddTransactionSheet`, `EditTransactionSheet`,
  `SplitEditorView`, `BudgetSheet`, `BudgetDetailView`, `AccountSheet`,
  `AdjustBalanceSheet` (balance), `ReconcileSheet`, `ScheduledSheet` (+ integer
  `installmentTotal`), `HoldingsView`, `TransactionFilterSheet`, `CurrenciesView`,
  `RulesManagerView` (+ integer "Day 1–31"). The implementation plan enumerates the
  exact lines.

## Data flow & error handling

Unchanged except the filter now runs in the binding setter before the value is
stored. Save-time `parse` is unchanged aside from the comma fallback; existing
"Enter an amount." messaging (where present) still guards an empty field.

## Testing

- **Unit (FinchAppTests):** exhaustive `DecimalInput.filter` tests — letters/symbols
  stripped; one separator kept, extras dropped; `.` and `,` both accepted; leading
  `-` kept, mid-string `-` dropped; empty stays empty; intermediate `-`/`.` allowed;
  integer variant rejects separators. Plus `parse` tests for the `,`→`.` fallback.
- **Builds:** FinchApp + FinchMac (macOS is a key motivation — no `.decimalPad` there).
- No UI tests (the 23 call sites are a mechanical wrap).

## Out of scope

Reformatting-as-you-type (grouping, leading zeros), per-field live decimal caps,
per-field negative config (deferred), a commit-time error-message overhaul, and web.
