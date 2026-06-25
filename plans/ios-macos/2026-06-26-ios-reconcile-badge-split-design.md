# Reconcile status badge + pending/confirmed split (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** FinchCore (`AccountRow` + projection + a stale helper) + `AccountDetailView`. **No engine/schema change.** Tier-2 parity (the reconcile cluster, part 1). The guided reconcile session + quick-add is deferred to its own feature.

## Problem

Two Tier-2 account-detail gaps vs the web:
1. **No reconcile-status badge** — the engine already records `last_reconciled_at` / `last_reconciled_balance` (the `accounts` table has the columns; the `reconcileAccount` action stamps them), but the iOS projection drops them and `AccountRow` lacks the fields, so nothing surfaces "last reconciled / stale."
2. **No pending/confirmed split** — `AccountDetailView`'s transaction list is flat; the web separates a "To confirm" section.

## Non-goals

- **Not** the guided reconcile session (tick cleared txns + cleared-vs-target progress + quick-add-missing + confirm-and-clear) — iOS's `ReconcileSheet` is a simpler statement-balance→adjustment form; rebuilding it is a separate, larger feature.
- No engine/schema/action change (the data + write path already exist).

## Key decisions (locked)

1. **Badge = projection-surfacing + UI** (engine data exists). Stale threshold **35 days** (boundary: 35 = fresh, 36 = stale), matching the web.
2. **"days ago" measured against `store.today`** (iOS's max-tx-date anchor, consistent with the rest of the app) — not wall-clock.
3. **Badge balance in the account's native currency** (`Money.format(bal, currency: account.currency)`) — the checkpoint is stored native, per the schema comment.
4. **Pending/confirmed split** = pure UI over `Tx.pending`.

## Detailed design

### FinchCore

- `AccountRow` (`Project/Models.swift`) gains `public var lastReconciledAt: String?` + `public var lastReconciledBalance: Double?` (defaulted `nil` in the init so other call sites compile).
- The `accounts` projection (`Projections+State.swift`) SELECTs `last_reconciled_at`, `last_reconciled_balance` and maps them onto `AccountRow`.
- New pure helper (e.g. in `Selectors`):
  ```swift
  public enum ReconcileStatus: Equatable, Sendable { case never; case fresh(days: Int); case stale(days: Int) }
  /// `today`/`lastReconciledAt` are "YYYY-MM-DD". `> staleDays` ⇒ stale.
  public static func reconcileStatus(_ lastReconciledAt: String?, _ today: String, staleDays: Int = 35) -> ReconcileStatus
  ```
  - nil/empty `lastReconciledAt` ⇒ `.never`.
  - `days = daysBetween(lastReconciledAt, today)` (whole days; clamp negatives to 0). `days > staleDays` ⇒ `.stale(days)`, else `.fresh(days)`. (Reuse an existing day-diff helper if one exists in `AppDate`/`TimeSeries`; otherwise a small UTC `Calendar` diff.)

### FinchApp — `AccountDetailView`

- **`ReconcileStatusBadge(account:)`** (new small view), placed in the header near the balance:
  - `switch Selectors.reconcileStatus(account.lastReconciledAt, store.today)`:
    - `.never` → neutral/secondary: icon `checkmark.seal` + "Never reconciled".
    - `.fresh(d)` → green: icon `checkmark.seal.fill` + "Reconciled to \(bal) · \(ago(d))".
    - `.stale(d)` → orange: icon `exclamationmark.triangle` + same text.
  - `bal = Money.format(account.lastReconciledBalance ?? 0, currency: account.currency ?? store.baseCurrency)` (native).
  - `ago(d)`: `d == 0 ? "today" : d == 1 ? "1 day ago" : "\(d) days ago"`.
- **Pending/confirmed split:** the existing transactions area splits the account's txns by `Tx.pending == true`:
  - A **"To confirm (\(n))"** `Section` (only when `n > 0`) listing pending rows (same row layout as today).
  - The existing **"Transactions"** `Section` then lists the confirmed rows.
  - (Same per-row display as now: merchant / date / amount.)

### Reuse / helpers

`Money.format(_:currency:)`, `store.today`, `store.baseCurrency`, `Tx.pending`; the existing `AccountDetailView` tx fetch (split its result).

## Facts (verified)

- `accounts` schema has `last_reconciled_at TEXT` + `last_reconciled_balance REAL` (`Storage/Schema.swift`); `reconcileAccount` (`Store/Domain/Transactions.swift`) `UPDATE accounts SET last_reconciled_at = ?, last_reconciled_balance = ?` — writes them (statement date + native balance). The `accounts` projection (`Projections+State.swift`) currently omits both.
- `AccountRow` (`Project/Models.swift`) — no last-reconciled fields today. `Tx.pending: Bool?` available.
- `AccountDetailView` transactions section is a flat `ForEach(txns)`.
- Web parity: `reconcile-status.tsx` (`STALE_AFTER_DAYS = 35`; never → "Never reconciled"; else green/amber "Reconciled to $X · N days ago"); account detail separates a "To confirm" section from confirmed.

## Testing

- **FinchCore:**
  - projection carries the fields — seed via `reconcileAccount` (statementBalance + statementDate), project `accounts`, assert `lastReconciledAt`/`lastReconciledBalance`; an un-reconciled account projects `nil`.
  - `reconcileStatus`: `nil` → `.never`; same-day → `.fresh(0)`; 35 days → `.fresh(35)`; 36 days → `.stale(36)`; a future `lastReconciledAt` → `.fresh(0)` (clamped).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** reconcile an account (existing ReconcileSheet) → its detail shows a green badge "Reconciled to $X · today"; an account never reconciled shows "Never reconciled"; an account with pending txns shows a "To confirm (N)" section above Transactions.

## Out of scope

The guided reconcile session (tick cleared txns / cleared-vs-target / quick-add-missing / confirm-and-clear); engine/schema/action changes; the accounts-list-row badge (detail only for CP1).
