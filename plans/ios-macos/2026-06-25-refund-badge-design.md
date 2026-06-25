# Refund badge on transaction rows

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** Add a "Refund" badge to `kind == "refund"` rows in the transaction feed (`TxRow`). UI-only; web parity. No engine change.

## Problem

A refund (`kind == "refund"`) is a positive entry that nets against its category.
In the feed, a refund row shows the uturn icon (green) and a positive green amount —
but **no label**, so it can be misread as ordinary income. The web marks these rows
with a small **"Refund" badge** (`components/ui/refund-badge.tsx` — a success-tinted
pill with a sync icon + "Refund" text); iOS has no equivalent.

## Design

In `TxRow` (in `ActivityTab.swift`), in the merchant `HStack` — after the existing
`pending` clock and anomaly indicators — add, when `txn.kind == "refund"`:

```swift
                    if txn.kind == "refund" {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.uturn.left")
                            Text("Refund")
                        }
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                        .accessibilityLabel("Refund")
                    }
```

- A small green-tinted capsule (`arrow.uturn.left` + "Refund"), consistent with the
  row's existing green refund icon + positive amount and with the web's
  success-tinted `RefundBadge`.
- Sits inline next to the merchant, alongside the pending/anomaly markers.
- Appears wherever `TxRow` is used (the whole feed — Activity tab, Ledger home,
  "All Transactions").

## Out of scope
- A "of <original transaction>" reference in the badge.
- Badging the *original* expense as "refunded" (the web doesn't either).
- Any engine / data change — `Tx.kind` already carries `"refund"`.

## Testing

**Build:** FinchApp (iOS) + FinchMac (macOS) — `TxRow` is shared.

**Manual (sim):** a transaction of kind **refund** (create via Add → Refund) shows
a green **"Refund"** pill on its feed row; non-refund rows show none.

## Notes
- Pure-view change; no unit test.
- PR targets `feat/frontend`.
