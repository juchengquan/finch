# Add Transaction: tags + status + receipt (iOS)

**Date:** 2026-06-22
**Status:** Design approved, pending implementation
**Scope:** iOS Add Transaction form (expense/income kinds) + the `addTransaction` engine action. Transfer / adjust-balance excluded. Edit form unchanged except a shared receipt helper.

## Problem

The Add Transaction form is missing three fields the engine/Edit form already support:
- **Tags** — Edit has a tag multi-select; Add has none.
- **Status** (pending vs confirmed) — `AddInput` accepts `status` but the form never sets it.
- **Receipt attachment** — Edit can attach a photo; Add can't.

The blocker for tags/receipt on Add: they need the *new* entry's id, but the iOS write chokepoint (`FinchStore.apply` → `Apply.apply`) returns `Void`. `addTransaction` already computes the new id internally (`let eid = try Entries.postEntry(...)`); it just isn't surfaced.

## Goal

On the Add form, for **expense/income** transactions, let the user:
- pick **tags** (multi-select),
- choose **status** (Confirmed / Pending; default Confirmed),
- attach a **receipt** photo,

all saved atomically with the new transaction. Transfer/adjust unchanged.

## Design

### 1. Engine — tags inline + surface the new id (`FinchCore`)

- **`AddInput` gains `tagIds: [String]?`.** Inside `addTransaction`, after the entry is created (both the same-currency and foreign-currency branches produce `eid`), insert `entry_tags (entry_id, tag_id)` rows for each id — within the same `dbQueue.write`, so tags commit atomically with the entry. `status` already flows via `AddInput.status` (no change).
- **Surface the new entry id.** Add `Apply.applyReturningId(dbQueue:action:args:) throws -> String?` — same guards as `apply`, returns the new `eid` for `.addTransaction`, `nil` for every other action. `Transactions` exposes an `addTransactionReturningId(_:_:) -> String` that does the work; the existing Void `addTransaction` registry handler wraps it and discards.
- **Store wrapper.** Add `FinchStore.applyReturningId(_ action:_ args:) throws -> String?` that calls `Apply.applyReturningId` and then runs the **same** re-projection + side-effects block as `apply`. `apply(_:_:)` becomes `_ = try applyReturningId(...)` so the side-effect block lives once (DRY).

### 2. Add form — three controls (expense/income only)

Shown only when `kind == .expense || kind == .income` (not transfer/adjust):

- **Status** — `Picker("Status", selection: $status)` with cases Confirmed / Pending. New `@State status: TxStatus = .confirmed`. Default **Confirmed** preserves today's behavior. On save, pass `"status": .string("confirmed"|"pending")`.
- **Tags** — a `Section("Tags")` of selectable rows mirroring the Edit form (`ForEach(store.tags)` + `@State selectedTags: Set<String>`), shown when `!store.tags.isEmpty`. On save, pass `"tagIds": .array(selectedTags.map(.string))` when non-empty.
- **Receipt** — a `Section("Receipt")` with a `PhotosPicker` mirroring Edit; `@State pickedPhoto: PhotosPickerItem?` holds the selection until save. On save:
  1. build the `addTransaction` args (incl. tagIds/status),
  2. `let eid = try store.applyReturningId(.addTransaction, Args(args))`,
  3. if a photo was picked, write the file + record it via `setEntryAttachment(entryId: eid, …)` — reusing the shared helper below.

The transfer/adjust save paths (`createTransfer` / `adjustAccountBalance`) are unchanged and continue to use `store.apply`.

### 3. DRY — shared receipt writer

Extract the Edit form's `addReceipt(_ item:)` logic into a small shared helper (e.g. `AttachmentWriter.write(_ item: PhotosPickerItem, entryId: String, store:) async throws`) that: loads the image data, writes it under `attachments/<entryId>/<attId>.jpg` in the live attachments tree, and applies `setEntryAttachment`. Both Add and Edit call it. Edit's existing behavior is preserved (just relocated).

## Out of scope
- Tags/status/receipt on **transfer** or **adjust-balance** (different engine actions; additive follow-up if ever wanted).
- Counterparty linking, split creation, refund linking (separate gaps).
- Web parity for `tagIds` on `addTransaction` (iOS engine is separate Swift code; mirror later if desired).

## Testing

**Engine (FinchCore `swift test`):**
- `addTransaction` with `tagIds: ["t1","t2"]` creates two `entry_tags` rows for the new entry.
- `addTransaction` with `status: "pending"` yields an entry whose status is `pending`; default (omitted) yields `confirmed`.
- `applyReturningId(.addTransaction, …)` returns a non-nil id that matches the created entry; `applyReturningId` for another action returns `nil`.

**App (build + manual sim — UI can't be unit-tested):**
- Add an expense with tags + Pending + a receipt photo → saved tx shows the tags, pending state, and the receipt in Edit.
- Transfer/adjust forms unchanged (no new fields).

## Notes
- `Entries.Status` is `pending | confirmed`. The Picker exposes exactly these two.
- Atomicity: tags commit with the entry (same write). The receipt is written *after* the entry exists (it needs the id) — consistent with how Edit attaches receipts; a failed photo write surfaces an error but leaves the (already-saved) transaction intact.
- PR targets `feat/frontend`.
