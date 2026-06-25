# Activity saved searches (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** FinchApp only — `TxFilter: Codable`, a `SavedSearch` model + `SavedSearchStore` (UserDefaults), and a saved-search chip row on `ActivityTab`. **No engine/DB change.** Tier-2 parity.

## Problem

The Activity feed's filters are session-only; the web persists **named filter chips per-ledger** (localStorage) that re-apply with one tap. iOS has no persistence for filter state.

## Goal

Match the web: per-ledger **saved searches** — save the current (non-default) filter under a name, see them as chips on the feed, tap to re-apply, delete individually.

## Non-goals

- No engine/DB/schema change (this is a client preference, like the web's localStorage).
- **No change to `TransactionFilterSheet.swift`** (the save trigger lives on the feed chip row) — keeps us out of the hottest shared file.
- No sync/iCloud of saved searches; no rename (delete + re-save).

## Key decisions (locked)

1. **Per-ledger** (web parity) — `SavedSearch.ledgerId`; the chip row shows the active ledger's searches.
2. **UserDefaults persistence** (iOS analogue of the web's localStorage) — not the engine/DB.
3. **Save trigger = a "＋ Save" chip** on the feed (shown only when `filter != TxFilter()`); **delete = context menu** on each chip. `TransactionFilterSheet` untouched.

## Detailed design

### FinchApp — model + store

- **`TxFilter: Codable`** — add the conformance (members are `String?` / `Set<String>` / `Date?` / `Double?`, all Codable). No field changes.
- **`SavedSearch`** (new): `struct SavedSearch: Identifiable, Codable, Equatable { let id: String; var name: String; let ledgerId: String; let filter: TxFilter }`.
- **`SavedSearchStore`** (new, `ObservableObject`): UserDefaults-backed list under a single key (e.g. `"finch.savedSearches"`), JSON-encoded `[SavedSearch]`. Inject the `UserDefaults` (default `.standard`) for testability.
  - `func all(ledgerId: String) -> [SavedSearch]` — filtered to that ledger, insertion order.
  - `func save(name: String, filter: TxFilter, ledgerId: String)` — append (new UUID id; trims name; ignores empty name); persist; publish.
  - `func remove(_ id: String)` — drop + persist + publish.
  - Decoding tolerates a missing/corrupt blob (→ empty list).

### FinchApp — `ActivityTab`

- Hold a `@StateObject private var savedSearches = SavedSearchStore()` (or `@EnvironmentObject` if one already exists — use a local `@StateObject` otherwise).
- **Chip row** (a horizontal `ScrollView`), placed under the search/filter header, rendered only when `!store.savedSearches.all(activeLedgerId).isEmpty` **or** a non-default filter is active:
  - For each saved search: a chip (capsule) with its `name`; **tap → `filter = s.filter`** (apply to the feed's existing `@State`/`@Binding` filter); the chip highlights when `filter == s.filter`. A `.contextMenu` with **Delete** → `savedSearches.remove(s.id)`.
  - A trailing **"＋ Save"** chip, shown only when `filter != TxFilter()` and the current filter isn't already saved: tap → presents a name alert (`TextField`) → on confirm `savedSearches.save(name:, filter: filter, ledgerId: activeLedgerId)`.
- The feed's existing filter `@State` (`TxFilter`) is the single source of truth; applying a saved search just assigns it (the feed already re-filters on filter change).

### Reuse / helpers

`TxFilter` (+ its default `TxFilter()` for the "non-default" check via `Equatable`); the feed's existing filter state + filtering; `store.activeLedgerId`. A name-entry alert (`.alert` with a `TextField`, iOS 16+).

## Facts (verified)

- `TxFilter` is an `Equatable` value struct (`direction/accountId/categoryId/tagIds:Set<String>/status/from:Date?/to:Date?/minAmount/maxAmount`) in `WriteScreens/TransactionFilterSheet.swift`; the sheet edits a draft and assigns to a `@Binding var filter`.
- Web parity (`frontend/app/(main)/activity/page.tsx` + `lib/use-saved-searches.ts`): `SavedSearch {id, name, ledgerId, filter}`, localStorage, scoped to `activeId`; "any non-default filter is saveable"; chips apply on tap + a per-chip delete; a save dialog with a name field.
- 0 open PRs touch `ActivityTab`/`TransactionFilterSheet` (collision-checked); re-verify before the impl PR.

## Testing

- **FinchApp (`SavedSearchStore` against a test `UserDefaults(suite:)`):**
  - `save` then `all(ledgerId)` returns it; a second ledger's `all` excludes it (per-ledger scoping).
  - `remove` drops it; persists across a fresh `SavedSearchStore(defaults:)` (durability).
  - `save` trims/ignores an empty name.
  - **`TxFilter` Codable round-trip** — encode→decode equals the original (incl. `from`/`to` dates + `tagIds`).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** apply some filters → a "＋ Save" chip appears → name it → it shows as a chip; clear filters, tap the chip → filters re-apply; delete via long-press; switch ledger → only that ledger's chips show.

## Out of scope

`TransactionFilterSheet` changes; rename; iCloud/sync of saved searches; engine/DB changes.
