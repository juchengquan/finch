# Add Transaction: split creation (iOS)

**Date:** 2026-06-23
**Status:** Design approved, pending implementation
**Scope:** iOS Add Transaction form (expense/income) + a refactor of `SplitEditorView`. Transfer/adjust excluded. Engine unchanged.

## Problem

You can split a transaction across ≥2 category legs only *after* creating it
(Edit → `SplitEditorView` → `setTransactionSplits`). The Add form can't create a
split in one pass.

The pieces already exist:
- **`setTransactionSplits(id, splits)`** — rebuilds an existing entry's legs into N
  category splits (a verbatim web port; handles base/FX).
- **`applyReturningId`** — `addTransaction` returns the new entry id (added for the
  receipt feature).
- **`SplitEditorView`** — the split UI, but hardwired to an existing `Tx`.

So Add-then-split is: `addTransaction` → `setTransactionSplits(eid, …)`. The work is
(a) making the split editor reusable without a `Tx`, and (b) wiring it into Add.

## Goal

On the Add form (expense/income), once an amount is entered, a **"Split…"** entry
opens the split editor against that amount; on save the new transaction is created
**and** split in one flow.

## Design

### 1. Make `SplitEditorView` transaction-agnostic

Decouple the editor from `Tx`. It takes plain inputs:

```swift
init(total: Double, isIncome: Bool, currency: String,
     initialSplits: [(categoryId: String?, amount: Double)]?,
     onSave: @escaping ([(categoryId: String?, amount: Double)]) -> Void,
     onRemove: (() -> Void)? = nil)
```

- Body uses these stored props instead of `txn` (total, the income/expense category
  filter, currency for `Money.format`, seed rows from `initialSplits`).
- **Save** runs the existing validation (≥2 rows with amounts; sum ≈ total within the
  current tolerance) then calls `onSave(splits)` instead of applying
  `setTransactionSplits` directly. `dismiss()` after.
- **"Remove split"** shows only when `onRemove != nil` (i.e. the Edit path); calls
  `onRemove()`.
- **Edit keeps identical behavior** via a convenience initializer:

  ```swift
  init(txn: Tx) // derives total/isIncome/currency/initialSplits from txn;
                // onSave → store.apply(.setTransactionSplits, [id, splits]);
                // onRemove → store.apply(.setTransactionSplits, [id, []])
  ```

  `EditTransactionSheet`'s call site (`SplitEditorView(txn: txn)`) is unchanged.

### 2. Add-form integration (expense/income only)

New state in `AddTransactionSheet`:

```swift
@State private var pendingSplits: [(categoryId: String?, amount: Double)]? = nil
@State private var showingSplit = false
```

- In `expenseIncomeFields`, when a valid amount is entered, show a **Split row**:
  - no splits yet → a `Button` "Split…".
  - `pendingSplits` set → "Split across N categories" (tap to re-open/edit).
- When `pendingSplits != nil`, **hide the single Category picker** (splits own the
  categories — mirrors Edit hiding category for split txns).
- `.sheet(isPresented: $showingSplit)` presents the editor in draft mode:

  ```swift
  SplitEditorView(total: abs(DecimalInput.parse(amount) ?? 0),
                  isIncome: kind == .income,
                  currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode,
                  initialSplits: pendingSplits,
                  onSave: { pendingSplits = $0 })
  ```
  (No `onRemove` → the editor shows no "Remove split"; the user cancels for no split.)

- **Amount sync:** in the existing `.onChange(of: amount)` (or a new one), set
  `pendingSplits = nil` whenever the amount text changes — a split is defined against
  a fixed total, so editing the amount invalidates it and the user re-splits.

### 3. Save (expense/income branch)

After the existing `addTransaction` call that yields `eid`:

```swift
let eid = try store.applyReturningId(.addTransaction, Args(args))
if let eid, let splits = pendingSplits {
    let payload: [JSONValue] = splits.map { .object([
        "categoryId": $0.categoryId.map(JSONValue.string) ?? .null,
        "amount": .double($0.amount)]) }
    try store.apply(.setTransactionSplits, Args(["id": .string(eid), "splits": .array(payload)]))
}
// (receipt Task stays after this, unchanged)
```

`addTransaction` creates the entry with its single (seeded) category leg;
`setTransactionSplits` then rebuilds it into the N splits. The `categoryId` arg
passed to `addTransaction` is harmless (overwritten by the split rebuild).

## Out of scope
- Transfer / adjust-balance.
- Engine changes (`setTransactionSplits` + `applyReturningId` already exist).
- New split *validation* rules — reuse the editor's existing ≥2 / sum-≈-total checks.

## Testing

**Engine (FinchCore):**
- `addTransaction` → `applyReturningId` gives `eid`; `setTransactionSplits(eid, [two
  splits summing to the total])` → the entry has **2 category legs** with the
  expected category ids/amounts (and one account leg). Confirms the Add-then-split
  path end to end.

**App (build + manual sim — UI can't be unit-tested):**
- Add → Expense, enter $30, tap **Split…**, allocate $20 Groceries + $10 Household →
  save → the saved tx shows "Split across 2 categories" in Edit with those legs.
- Change the amount after splitting → the split row resets to "Split…" (pending
  cleared).
- Cancel the split sheet → no split; normal single-category add.
- Transfer/Adjust → no Split row.
- Edit → existing `SplitEditorView` still works (split, re-split, remove split).

## Notes
- FX + split rides the existing `setTransactionSplits` (verbatim web port) — same
  behavior as splitting an FX transaction from Edit today; no new path.
- The split editor refactor is the main risk; the `init(txn:)` convenience keeps the
  Edit flow byte-for-byte unchanged.
- PR targets `feat/frontend`.
