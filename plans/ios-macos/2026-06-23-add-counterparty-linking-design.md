# Add Transaction: counterparty linking (iOS)

**Date:** 2026-06-23
**Status:** Design approved, pending implementation
**Scope:** iOS Add Transaction form (expense/income). UI-only — no engine change.

## Problem

A transaction stores a free-text `merchant` *and* an optional `counterparty_id`
link to a reusable counterparty (payee/merchant) record. The Add form only sends
the free text, so users can't see existing counterparties or create one inline.

**Key finding — the engine is already correct.** `addTransaction` → `postSimple`/
`postEntry` already resolves the counterparty by name when none is passed
(`Entries.postEntry` line ~333: `e.counterpartyId ?? resolveCounterpartyIdByName(...)`),
matching the web's behavior (web tests: *exact name match → auto-resolve*; *unknown
name → null, no auto-create*). So:
- Typing a name that **exactly matches** an existing counterparty **already links**
  it on save today — it's just not discoverable.
- The engine **never auto-creates** a counterparty (deliberate, anti-spam).

So this feature is purely about **surfacing** existing counterparties and offering
an **explicit create** — no engine, `AddInput`, or parity changes.

## Goal

On the Add form (expense/income), as the user types a merchant:
- **Suggest** matching existing counterparties; tapping one fills the exact name
  (which the engine then auto-links on save).
- Offer an explicit **"Create '<name>'"** for a brand-new name, which creates the
  counterparty on save so it links too.
- Typing a new name without tapping Create stays unlinked plain text (unchanged).

## Design

### 1. Merchant suggestions section (expense/income only)

Beneath the existing Merchant `TextField`, add a suggestions `Section` shown when
`kind == .expense || kind == .income` and the trimmed merchant text is non-empty:

- **Matches:** up to 5 counterparties from `store.counterparties` (active ledger)
  whose name contains the typed text, case-insensitive, excluding an exact-name
  match (no point suggesting what's already typed). Each is a `Button` row; tapping
  sets `merchant = name` and clears the create flag.
- **Create row:** if the trimmed text matches **no** existing counterparty name
  exactly, a `Button` labeled `Create "<name>"` (with a `plus` icon). Tapping it
  sets `createCounterpartyOnSave = true` (the text is already the typed name).

Editing the merchant text resets `createCounterpartyOnSave = false` (the flag only
holds for the exact name the user opted to create).

### 2. Save path (expense/income)

In `save()`'s expense/income branch, **before** the `addTransaction` call:

```
if createCounterpartyOnSave {
    let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty, !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
        try store.apply(.createCounterparty, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(name)]))
    }
}
```

Then the existing `addTransaction` runs unchanged — `postEntry`'s resolve-by-name
links the (now-existing) counterparty. **No `counterpartyId` is passed**; linking
rides entirely on the engine resolver. The guard (`!contains`) avoids a duplicate
counterparty if the name already exists by the time of save.

`createCounterparty` and `addTransaction` are two sequential `store.apply` writes;
the first commits before the second resolves the name. Deferring creation to save
(not on tap) means cancelling the sheet never leaves an orphan counterparty.

### 3. State added to `AddTransactionSheet`

```swift
@State private var createCounterpartyOnSave = false
```

(plus a small `matchingCounterparties` computed property and a `suggest`/`pickCounterparty`
helper.) No other state; `merchant` already exists.

## Out of scope
- Transfer / adjust-balance (different actions; no merchant/counterparty).
- The Edit form (already links via merchant-rename → resolve).
- Engine / `AddInput` / parity changes (engine already correct).
- Passing an explicit `counterpartyId` (unnecessary — resolve-by-name covers it).
- A visual "linked" badge on the saved row (the link is real; a badge is a separate polish).

## Testing

**Engine (FinchCore — optional confidence test):**
- `addTransaction` with a merchant exactly matching an existing counterparty links
  it (`counterparty_id` set); an unknown name leaves it null. (Mirrors the web
  parity tests; the resolver is pre-existing.)

**App (build + manual sim — UI can't be unit-tested):**
- Seed a counterparty (e.g. "Starbucks"). Add → Expense, type "Star" → "Starbucks"
  suggested → tap → save → the transaction is linked (shows under that merchant /
  in reports).
- Type a new name "Bakery Co" → "Create 'Bakery Co'" appears → tap → save → a
  counterparty "Bakery Co" now exists (Power Tools › Merchants) and the tx links.
- Type "oneoff" and DON'T tap Create → save → no counterparty created, tx unlinked.
- Switch to Transfer/Adjust → no suggestions section.

## Notes
- `store.counterparties` is the active-ledger list (the cross-ledger guard in
  `addTransaction` already drops foreign-ledger ids, but we only ever use active).
- PR targets `feat/frontend`.
