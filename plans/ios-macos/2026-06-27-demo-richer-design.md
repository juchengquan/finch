# Richer demo data: tags, pending, refund, transfer, installment, FX

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** Add six under-represented features to the simulator demo seed (`SimulatorDemoSeed.swift`) so they appear out of the box. All via existing actions — **no engine change**.

## Additions (all in `SimulatorDemoSeed.swift`, ledger `personal` unless noted)

### 1. Tags (`createTag` + `addTransaction` `tagIds`)
Create 4 tags (hex from the shared `TagPalette`):
```swift
        let tags: [(id: String, name: String, color: String)] = [
            ("tag-reimbursable", "reimbursable", "#00a5da"),
            ("tag-subscription", "subscription", "#7d7df9"),
            ("tag-business",     "business",     "#00af67"),
            ("tag-vacation",     "vacation",     "#ba8600"),
        ]
```
Apply to ~11 existing transactions via a new `tags` field on the txns tuple (subscriptions →
*subscription*; CVS/Costco → *reimbursable*; Uber/Lyft/Best Buy → *business*; Nordstrom/REI →
*vacation*).

### 2. Pending (`addTransaction` `status`)
The 2 most recent txns (Whole Foods d2, Blue Bottle d3) get `status: "pending"` → clock icon
+ swipe-confirm / guided reconcile.

### 3. Refund (`addTransaction` `kind: "refund"`)
New txn: `(11, "credit", +64.99, "Nordstrom Refund", "cat-shopping", kind "refund", tags [vacation])`
→ Refund badge.

### 4. Transfer (`createTransfer`)
```swift
        try apply("createTransfer", [
            "fromAccountId": .string("everyday"), "toAccountId": .string("savings"),
            "fromAmount": .double(500), "date": .string(ymd(15)), "time": .string("12:00")])
```
→ a real transfer row in the feed.

### 5. Installment plan (`createScheduled` + `installmentTotal`)
```swift
        try apply("createScheduled", [
            "ledgerId": .string("personal"), "name": .string("Furniture Plan"),
            "type": .string("expense"), "amount": .double(120), "frequency": .string("monthly"),
            "accountId": .string("credit"), "dayOfMonth": .double(12),
            "startDate": .string(monthStart(2)), "category": .string("cat-shopping"),
            "installmentTotal": .double(12)])
```
→ Scheduled shows "Installment 0/12 · Credit Card". (Paid stays 0 — not posting occurrences.)

### 6. FX rate (`setExchangeRate`)
```swift
        try apply("setExchangeRate", ["date": .string(ymd(1)), "currency": .string("EUR"), "rate": .double(1.08)])
```
→ EUR↔USD conversion for the Travel ledger (USD is the hub; only EUR stored).

## Mechanics — extend the personal txns tuple

```swift
let txns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String,
            kind: String?, status: String?, tags: [String]?)] = [ … ]
```
The full replacement array (existing 30 rows + 1 refund, with kind/status/tags) is in the plan.
Loop conditionally adds `kind`/`status`/`tagIds`:
```swift
            if let k = t.kind { args["kind"] = .string(k) }
            if let s = t.status { args["status"] = .string(s) }
            if let tg = t.tags { args["tagIds"] = .array(tg.map { .string($0) }) }
```

## Out of scope
- Posting installment occurrences (keep 0/12); receipt attachments (needs a bundled file).
  Engine/model changes — none. Travel ledger content — unchanged (just gets an FX rate).

## Testing
- **Build:** FinchApp (iOS).
- **Manual (sim):** fresh re-seed → Ledger feed shows **tag chips** (colored), a **pending clock**
  (Whole Foods/Blue Bottle), the **Nordstrom Refund** badge, and a **Transfer** row; **Scheduled**
  shows the **Furniture Plan** installment line; **Travel** ledger amounts convert sensibly (FX).
  DB spot-check: `tags`=4, ≥1 pending entry, a `refund`-kind entry, a transfer (2 legs), an
  `exchange_rates` EUR row, a scheduled with `installment_total=12`.

## Notes
- Collision: `SimulatorDemoSeed.swift` is our file (demo-only); no open PRs. Re-check before push.
  PR → `feat/frontend`.
