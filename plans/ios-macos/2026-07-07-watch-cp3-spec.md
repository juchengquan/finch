# Spec: Watch sub-project CP3 — on-wrist quick-add

**Date:** 2026-07-07
**Status:** design approved, ready for implementation plan
**Scope:** native watchOS + iOS (`ios/`). Third and final checkpoint of the Watch sub-project (CP1 transport + glance #412; CP2 complication #415). Closes the Watch backlog row.

## Goal

Log an expense from the wrist: a minimal amount + category composer on the watch that enqueues a quick-add over the CP1 `WCSession` link; the phone applies it through the normal `store.apply` chokepoint as a **pending** transaction and pushes back a fresh snapshot, so the glance/complication update as the implicit ack.

## Motivation

- The wrist is where impulse spends happen (coffee, lunch, taxi). Capture-in-3-taps beats "remember to log it later" — and the existing **pending review** flow on the phone is the natural safety valve for terse wrist entries.
- CP1/CP2 built everything this rides on: the session, the shared wire-format file pattern, the snapshot feedback loop (`store.apply` → `WidgetSnapshotWriter.write` → `PhoneWatchLink.push` → watch persists + `reloadAllTimelines()`).
- The watch still needs zero FinchCore: the phone ships it a tiny entry catalog (account + top categories) inside the snapshot it already pushes.

## Current state (baseline, @ #416)

- **Phone:** `PhoneWatchLink` (iOS-only, `#if os(iOS)`) activates at launch and pushes `WatchSnapshotPayload` from `WidgetSnapshotWriter.write(from:)` — called on **every** `store.apply` write and on import. `FinchStore.apply/applyReturningId` is the single write chokepoint (Spotlight, notifications, widget snapshot, auto-backup, CloudKit log all hang off it).
- **Watch:** `WatchSnapshotStore` receives the context, persists to the watch App Group (`WatchStore.suite`/`.key`), publishes, and reloads complication timelines. `GlanceView` renders the four figures.
- **Shared:** `ios/Shared/WatchSnapshotPayload.swift` (+ `+Display.swift` with `WatchStore`, `shortMoney`, `isStale`) — Foundation-only, compiled into FinchApp, FinchWatch, FinchWatchComplication.
- **Add args shape** (from `AddTransactionSheet`): `.addTransaction` takes `ledgerId, accountId, amount` (signed; negative = expense), `merchant, categoryId, date, time`, optional `note/currency/status/tagIds`.

## Design

### 1. Catalog down — extend `WatchSnapshotPayload` (backward-compatibly)

- New nested type in `ios/Shared/WatchSnapshotPayload.swift`:
  ```swift
  struct WatchQuickAddCatalog: Codable, Equatable {
      struct Item: Codable, Equatable { var id: String; var name: String }
      var ledgerId: String
      var accountId: String        // default posting account
      var accountName: String
      var categories: [Item]       // top expense categories, ≤ 6
  }
  ```
- `WatchSnapshotPayload` gains `var quickAdd: WatchQuickAddCatalog?` — **optional**, so old payloads persisted on the watch decode fine and an old watch app ignores the new key (JSONDecoder both directions).
- Built in the phone's `WatchSnapshotPayload(widget:)` mapping site (`WidgetSnapshotWriter`): default account = the account most used by confirmed expenses in the last 90 days (fallback: first active account); categories = top ≤ 6 expense categories by 90-day confirmed-expense count (fallback: first 6 expense categories). Pure helper on FinchCore data in the app target, unit-tested.

### 2. Quick-add up — `WatchQuickAddPayload` + `transferUserInfo`

- New shared file `ios/Shared/WatchQuickAddPayload.swift` (Foundation-only):
  ```swift
  struct WatchQuickAddPayload: Codable, Equatable {
      var id: String               // UUID string — the phone-side dedupe key
      var ledgerId: String
      var accountId: String
      var categoryId: String
      var amount: Double           // positive magnitude; phone signs it negative
      var createdAt: Date
      func encoded() -> Data?; static func decode(_ data: Data) -> WatchQuickAddPayload?
  }
  ```
- Transport: `WCSession.default.transferUserInfo(["quickAdd": data])` — the **guaranteed FIFO queue** (the CP1 spec explicitly reserved it for this): survives unreachability, delivers in order, no coalescing (every tap is a distinct transaction — coalescing would drop spends).
- Delivery caveat (documented in the watch UI copy): userInfo transfers are handed over when the **phone app next runs**; the watch shows "Added — syncs to iPhone" rather than promising instant arrival.

### 3. Phone side — receive, dedupe, apply as pending

- `PhoneWatchLink` gains `session(_:didReceiveUserInfo:)`:
  1. Decode `userInfo["quickAdd"]` → `WatchQuickAddPayload`; ignore unknown keys.
  2. **Dedupe:** a persisted ring of the last 200 processed ids (`UserDefaults` key `finch.watch.processedQuickAddIds`) — WCSession redelivers on some failure paths, and a replayed id must not double-book. Ring logic = pure helper, unit-tested.
  3. On the main actor: `FinchStore.shared.apply(.addTransaction, ...)` with
     `ledgerId`/`accountId`/`categoryId` from the payload, `amount = -abs(payload.amount)`,
     `merchant` = the category's display name (reads naturally in the feed; the pending flow is where naming gets fixed), `date`/`time` from `createdAt`, **`status: "pending"`** — wrist entries land in Pending review for confirm/edit, mirroring how scheduled income/expense posts arrive.
     Guards: unknown account/category id (catalog staleness) → fall back to the current default account / first expense category rather than dropping the spend.
  4. No explicit ack message: the apply path already rewrites the widget snapshot and pushes a fresh `WatchSnapshotPayload` — the watch seeing new figures IS the ack.

### 4. Watch UI — `QuickAddView`

- Entry: a `+` toolbar button on the glance (`.toolbar` bottom bar). Disabled with "Open finch on your iPhone" copy when `snapshot?.quickAdd == nil` (no catalog yet).
- Composer (one screen, 3 taps for the common case):
  - **Amount:** large figure driven by `.digitalCrownRotation` (0…500 range, 0.5 steps) plus three quick-bump buttons (+1 / +5 / +10); long-press clears. Starts at 0; Add disabled at 0.
  - **Category:** horizontal chip row (or wheel picker) over `catalog.categories`, first item preselected.
  - **Add button:** encodes the payload (`UUID().uuidString`, `Date()`), calls `transferUserInfo`, shows a checkmark confirmation ("Added — syncs to iPhone"), auto-dismisses.
- Account is the catalog default — no account picker on the wrist (CP3 keeps the composer minimal; a picker can ride a later polish pass).
- Currency label next to the amount = `snapshot.currency` (entry is in the ledger base/display currency the glance already shows).

### 5. Out of scope (explicitly)

- Dictation/scribble merchant entry, account picker, income/transfer kinds, tags — the phone's Add sheet is for that; the wrist is expense capture only.
- A complication deep-link straight into the composer (tap already opens the app one tap from `+`; watchOS widget deep-links can ride a polish pass).
- `sendMessage` live-reachability path — `transferUserInfo` alone keeps semantics simple and guaranteed.
- Any FinchCore dependency on watchOS.

## Verification

- **FinchAppTests:** `WatchQuickAddPayload` round-trip + garbage decode; catalog builder (default account + top-6 categories from fixture rows, fallbacks); dedupe ring (drops replayed id, evicts past 200, persists).
- **Builds:** FinchApp (iOS sim) + FinchMac (`CODE_SIGNING_ALLOWED=NO`; all new phone-side code stays inside the existing `#if os(iOS)` guards) + FinchWatch (watchOS sim; app + complication).
- **By hand on paired simulators:** compose a quick-add on the watch → phone (foreground) books a **pending** transaction with the right amount/category/account → Pending screen shows it → confirming it updates the glance/complication figures via the snapshot push. Screenshot both sides for the PR.
