# Add Transaction: tags + status on transfers (iOS)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS Add Transaction form — let the **transfer** type carry tags + status. Optional engine params on `postTransfer`/`createTransfer`. Receipt NOT added to transfers.

## Problem

The Add form's other line-item types (expense/income/refund) can set status and
tags, but **transfer** can't — `Transfers.create` → `Entries.postTransfer` accept
only from/to/amount/date/time/note, with no status or tags.

**Parity note (important):** the **web also lacks this** — its `Transfer` model and
`createTransfer`/`postTransfer` carry no status/tags. So this is a NEW capability,
not iOS catching up. It's feasible because the schema already supports it: every
entry has a `status` column (transfers default `confirmed`), and `entry_tags` works
for any entry. A transfer is a single entry with two account legs, so status sits on
that entry and tags attach to it.

**This is a deliberate iOS-ahead-of-web divergence** (like the existing "Force
import" override): tags/status set on a transfer here persist in the DB but the web
UI won't surface them. Accepted.

## Goal

On the Add form, the **transfer** type shows the Status picker and Tags section
(same as expense/income/refund), and saving carries them onto the transfer entry.
Receipt remains expense/income/refund only.

## Design

### 1. Engine — optional `status` + `tagIds` (parity-safe)

- **`Entries.postTransfer`** gains two optional params, defaulting to current
  behavior:
  ```swift
  status: Status? = nil, tagIds: [String]? = nil
  ```
  It already returns the new entry id. Pass `status` into the `NewEntry(...,
  status: status, ...)` it builds (postEntry applies it), and after the entry is
  created insert `entry_tags` for `tagIds` (reuse the same insert pattern as
  `Transactions.insertTags` — a small shared/duplicated `INSERT OR IGNORE`).
- **`Transfers.create`** — its decoded struct gains `status: String?` and
  `tagIds: [String]?`; pass them through to `postTransfer`
  (`status: a.status.flatMap(Entries.Status.init(rawValue:))`, `tagIds: a.tagIds`).
- Both default to nil ⇒ when callers (incl. the web parity `WRITE_SEQUENCE`,
  `postScheduled`, reconcile) don't set them, behavior is byte-identical ⇒
  **`ParityTests` unaffected**.

### 2. Add form — show Status + Tags for transfers

The Status picker + Tags sections are currently gated `if isLineItem` (expense/
income/refund). Widen that gate to **`kind != .adjust`** (adds transfer). The
**Receipt** section stays gated `isLineItem` (no receipt on transfers).

Concretely, split the existing extras block:
- `if kind != .adjust { Status picker; if !store.tags.isEmpty { Tags section } }`
- `if isLineItem { Receipt section }`

The transfer field set (`transferFields`) and everything else is unchanged.

### 3. Save — transfer branch carries them

In `save()`'s transfer branch (the `if kind == .transfer` block that builds the
`createTransfer` args), before `store.apply(.createTransfer, …)` add:

```swift
                args["status"] = .string(status.rawValue)
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
```

(`status`/`selectedTags` already exist as form state from the tags/status feature.)
No `applyReturningId` needed — `postTransfer` sets status + tags inline.

## Out of scope
- Receipt on transfers; splits/counterparty on transfers.
- Editing tags/status on an existing transfer (Edit) — the Edit form already
  supports tags on any tx via `setTransactionTags`; transfer status-in-Edit is a
  possible follow-up, not this task.
- Web changes (the divergence is intentional and iOS-local).

## Testing

**Engine (FinchCore):**
- `createTransfer` with `status: "pending"` + `tagIds: ["t1"]` → the transfer entry
  has `status = pending` and an `entry_tags` row for `t1`.
- A plain `createTransfer` (no status/tags) is unchanged (status `confirmed`, no
  tags) — guards the default path.
- `ParityTests` green (`swift test`).

**App (build + manual sim):**
- Add → **Transfer**: Status picker + Tags section appear; **no Receipt**.
- Save a transfer marked Pending with a tag → the transfer entry is pending and
  tagged (visible via the tag, and a pending transfer where the app shows pending).
- Expense/income/refund unchanged; Adjust shows neither Status nor Tags.

## Notes
- `postTransfer` is also called by reconcile / `postScheduled` paths — they pass no
  status/tags, so the new optional params don't affect them.
- Document the divergence inline (a comment near the transfer status/tags wiring)
  mirroring the "Force import (iOS only)" precedent.
- PR targets `feat/frontend`.
