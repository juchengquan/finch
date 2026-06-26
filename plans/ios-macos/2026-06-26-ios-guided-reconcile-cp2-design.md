# Guided reconcile session — CP2 (quick-add + confirm-and-clear) (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** FinchApp UI only — additions to the existing guided `ReconcileSheet`. **No engine/selector change.** Completes the last web→iOS parity gap (CP2 of 2).

## Problem

CP1 shipped the guided reconcile session (tick cleared + tracker + finish). Two web behaviors remain:
1. **Quick-add a missing transaction** inline (statement has something the app doesn't) → added confirmed and auto-cleared.
2. **Confirm-and-clear** for pending rows — a pending transaction can't be cleared until confirmed; one tap does both.

## Key findings (verified — no engine work)

- `store.applyReturningId(_ action:, _ args:) -> String?` returns a new transaction's id. So quick-add = `applyReturningId(.addTransaction, …)` → `setCleared(newId, true)` (the same pattern `AddTransactionSheet` uses for splits/receipts).
- `addTransaction` accepts `{ ledgerId, accountId, amount, merchant, categoryId?, date, status?, … }`; `categoryId` may be omitted (uncategorized). Signed amount convention: income → `+abs`, expense → `−abs`.
- `confirmTransaction({ id })` flips a pending entry to confirmed. `setCleared({ id, cleared })` toggles the leg's `cleared_at`.
- `store.transactions(for:)` returns all txns; CP1 filters `pending != true`. The pending set is `filter { $0.pending == true }`.
- The CP1 `reconcileState` tracker recomputes from the store on every render, so both new actions update the tracker automatically.

## CP2 decisions (locked)

1. **Quick-add** posts **uncategorized** (omit `categoryId`) with the **statement date** (the sheet's `date`), to the reconcile account; then auto-clears the returned id.
2. **Expense/income** toggle controls the sign (`income ? +abs : −abs`).
3. **"To confirm" section** above the confirmed Transactions list (only when pending exist); per-row **"Confirm & clear"** → `confirmTransaction` + `setCleared(true)`.
4. **No new FinchCore logic** → no new unit test; verify via build + sim. (The underlying actions + the `reconcileState` selector are already tested.)

## Detailed design (`ReconcileSheet.swift`)

### Quick-add a missing transaction

- New `@State`: `addMerchant = ""`, `addAmount = ""`, `addIsExpense = true`.
- A `Section("Add missing transaction")` placed **between** `trackerSection(a)` and `transactionsSection(a)`:
  - a `Picker` (segmented) Expense / Income bound to `addIsExpense`;
  - a merchant `TextField`;
  - an amount `TextField` (`.decimalPad`);
  - an **Add** button (disabled until amount parses), which calls `quickAdd(a)`.
- `quickAdd(_ a:)`:
  ```swift
  guard let v = DecimalInput.parse(addAmount), v != 0 else { return }
  let signed = addIsExpense ? -abs(v) : abs(v)
  let args: [String: JSONValue] = [
      "ledgerId": .string(store.activeLedgerId), "accountId": .string(a.id),
      "amount": .double(signed), "merchant": .string(addMerchant.isEmpty ? "Reconcile" : addMerchant),
      "date": .string(AppDate.isoDay.string(from: date))]
  do {
      if let id = try store.applyReturningId(.addTransaction, Args(args)) {
          try store.apply(.setCleared, Args(["id": .string(id), "cleared": .bool(true)]))
      }
      addMerchant = ""; addAmount = ""
  } catch { errorMessage = i18nMessage(error) }
  ```

### Confirm-and-clear for pending

- In `transactionsSection` (or a sibling), add a **`Section("To confirm (\(pending.count))")`** shown only when `pending` is non-empty, where `pending = store.transactions(for: a.id).filter { $0.pending == true }`:
  - each row: merchant / date / native amount + a **"Confirm & clear"** button → `confirmAndClear(t)`.
- `confirmAndClear(_ t:)`:
  ```swift
  do {
      try store.apply(.confirmTransaction, Args(["id": .string(t.id)]))
      try store.apply(.setCleared, Args(["id": .string(t.id), "cleared": .bool(true)]))
  } catch { errorMessage = i18nMessage(error) }
  ```
- The confirmed Transactions list keeps its current `pending != true` filter (so a confirmed-and-cleared row moves from "To confirm" into the cleared list).

## Facts (verified)

- `FinchStore.applyReturningId(_ ActionName, _ Args) -> String?` (FinchStore.swift:140).
- `addTransaction` handler (Transactions.swift): `addTransactionReturningId` returns the new entry id; `categoryId` optional. `confirmTransaction({id})` + `setCleared({id, cleared})` exist.
- `AddTransactionSheet` signed-amount: `(kind == .income || kind == .refund) ? abs : -abs`.
- Current `ReconcileSheet` (post-CP1): per-account, statement inputs, `trackerSection`, `transactionsSection` filtered to `pending != true`, `toggleCleared`, conditional finish. `store.displayMoney(_:from:)`, `AppDate.isoDay`, `DecimalInput.parse` available.
- 0 open PRs touch Reconcile/Transactions; other session in Insights/charts + i18n/docs.

## Testing

- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests + FinchCore green (no new tests — pure UI on tested actions).
- **Manual (sim):** in reconcile, **Add missing** (merchant + amount + expense/income) → the new row appears ticked and the difference shrinks; a **pending** transaction shows under "To confirm" with **Confirm & clear**, which moves it into the cleared list and updates the tracker; finishing still works (Done when balanced).

## Out of scope

Editing the quick-added transaction's category inline (uncategorized by design — editable later from the feed); engine/selector changes; the global account-picker reconcile entry.
