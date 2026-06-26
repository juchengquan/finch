# Guided reconcile session — CP1 (core) (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** FinchCore (`reconcileState` selector) + a guided `ReconcileSheet` that **replaces** the current statement-balance-only sheet. **No engine change** (the `setCleared` + `reconcileAccount` actions already exist). The last open web→iOS parity gap; CP1 of a 2-CP feature.

## Problem

iOS reconcile is a one-shot "type the statement balance → auto-post an adjustment" form. The web has a **guided session**: tick individual transactions as *cleared*, watch a **cleared-balance vs statement-target** tracker converge, and finish (Done when balanced, or post an adjustment for any residual). CP1 ports the core of that.

## Key findings (verified — no engine work)

- **`setCleared(id, cleared)`** action exists (`Store/Domain/Transactions.swift`): toggles `postings.cleared_at` for the transaction's account leg (per-leg). `Tx.clearedAt: String?` is projected.
- **`reconcileAccount`** action exists: stamps `last_reconciled_at`/`last_reconciled_balance`; with `postAdjustment: true` it posts a reconcile adjustment for `statementBalance − Σ(confirmed cleared)` and clears it.
- **Balance math anchor:** `current_balance = SUM(p.amount) WHERE status='confirmed'` — **excludes pending**, includes the opening leg (which `postOpening` creates already-cleared). So the cleared balance can be derived without any opening field (see below). `p.amount` is the account's **native** currency.

## CP1 decisions (locked)

1. **Replace** the simple sheet with the guided one; **per-account** (launched from the account's Reconcile action, preselected).
2. **`clearedBalance = account.balance − Σ(confirmed, *un*cleared account txns)`** in native currency — equivalent to `opening + Σ(confirmed cleared)` because the opening leg is always cleared and `balance` already includes it. No new model field.
3. Native amounts via `Tx.nativeAmount ?? Tx.amount` (the projected `Tx.amount` is base; `nativeAmount` is native = `p.amount`).
4. **Deferred to CP2:** quick-add-missing (add → auto-clear) and confirm-and-clear for pending. CP1 lists **confirmed** transactions for ticking.

## Detailed design

### FinchCore — `reconcileState` selector (pure)

New `Selectors/ReconcileState.swift`:
```swift
public struct ReconcileState: Equatable, Sendable {
    public let clearedBalance: Double
    public let difference: Double     // statementBalance − clearedBalance
    public let balanced: Bool         // |difference| < 0.005
    public let clearedCount: Int
    public let unclearedCount: Int
}

extension Selectors {
    /// Live reconcile tracker for `account` against a `statementBalance` (native currency).
    /// clearedBalance = balance − Σ(confirmed, uncleared account-leg txns), which equals
    /// opening + Σ(confirmed cleared) since the opening leg is always cleared.
    public static func reconcileState(_ account: AccountRow, _ txns: [Tx], _ statementBalance: Double) -> ReconcileState
}
```
- Account-leg txns for this account: `txns.filter { $0.account == account.id }` (Projection emits one Tx per account leg, opening excluded).
- `confirmed = $0.pending != true`. `nativeAmt = { $0.nativeAmount ?? $0.amount }`.
- `unclearedConfirmed = confirmed && clearedAt == nil`; `clearedConfirmed = confirmed && clearedAt != nil`.
- `clearedBalance = r2(account.balance − Σ nativeAmt(unclearedConfirmed))`; `difference = r2(statementBalance − clearedBalance)`; `balanced = abs(difference) < 0.005`.
- `clearedCount = clearedConfirmed.count` (opening excluded from the list — fine, it's a count of tickable rows); `unclearedCount = unclearedConfirmed.count`.

### FinchApp — guided `ReconcileSheet`

Rewrite `WriteScreens/ReconcileSheet.swift` (keep the entry point — `ReconcileSheet(preselect:)` from `AccountDetailView`):
- **Inputs:** statement balance (decimal) + statement date (the account is fixed = preselect; drop the picker for the guided per-account flow).
- **Tracker** (from `reconcileState`): "Cleared `{clearedBalance}` of `{statementBalance}` · `{difference}` to go", a progress bar, and "Cleared N · To review M".
- **Transactions:** the account's confirmed txns (reuse the existing row look — merchant/date/native amount) each with a leading **cleared checkbox** (filled when `clearedAt != nil`); tapping toggles `store.apply(.setCleared, Args(["id": .string(tx.id), "cleared": .bool(!cleared)]))`. Cleared rows get a subtle highlight. (After the store round-trip, `txns` refresh and the tracker recomputes.)
- **Finish (toolbar / footer):**
  - **Done** — enabled only when `balanced`; dispatches `reconcileAccount(accountId, statementBalance, statementDate, postAdjustment: false)` → dismiss.
  - **Post adjustment (`{difference}`)** — shown when not balanced; dispatches with `postAdjustment: true` → dismiss.
- Money shown in the account's native currency (the statement is native) via the native formatter; reuse what `AccountDetailView` uses.

### Reuse

`store.apply(.setCleared / .reconcileAccount, ...)`, `store.transactions(for:)`, `Selectors.reconcileState`, `Tx.clearedAt/pending/nativeAmount/amount`, `AccountRow.balance/currency`, `AppDate.isoDay`.

## Facts (verified)

- `current_balance` recompute (`Entries.recomputeAccountFromPostings`): `SUM(p.amount) WHERE status='confirmed'` — excludes pending, native. `postOpening` creates the opening account leg with `clearedAt` set.
- `setCleared` args: `{ id: String, cleared: Bool }` → sets/clears `postings.cleared_at` on the leg.
- `reconcileAccount` args: `{ accountId, statementBalance, statementDate?, postAdjustment? }`.
- Current `ReconcileSheet`: `preselect`, `accountId`, `statementBalance`, `date`; dispatches `reconcileAccount` with `postAdjustment: true`; launched from `AccountDetailView` (`showingReconcile`).
- `Tx` exposes `account`, `pending`, `clearedAt`, `amount` (base), `nativeAmount` (native), `merchant`, `date`.
- 0 open PRs touch Reconcile/AccountDetail/Transactions (other session is in Insights/charts + i18n).

## Testing

- **FinchCore — `reconcileState`:** seed an account (opening 100) + confirmed txns (e.g. −30 uncleared, +50 then `setCleared`); assert `clearedBalance == 150`, `unclearedCount == 1`, `clearedCount == 1`; with `statementBalance == 150` → `balanced == true`, `difference == 0`; with a wrong target → `balanced == false` + correct `difference`.
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests + FinchCore green.
- **Manual (sim):** open an account → Reconcile → enter the statement balance → tick transactions; the tracker/progress converges; when it reaches the target, **Done** enables and finishing stamps the checkpoint (the reconcile badge updates); when not balanced, **Post adjustment** is offered.

## Out of scope (CP2)

Quick-add-missing transaction (add → auto-clear); confirm-and-clear for pending rows; any engine change; the global (account-picker) reconcile entry — CP1 is per-account.
