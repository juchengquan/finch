# Design record: Watch quick-add **templates** (companion to CP3)

**Date:** 2026-07-07 · **Status:** shipped in #417 (implementation in the same PR).
**Relationship to CP3:** the canonical CP3 spec/plan (`2026-07-07-watch-cp3-{spec,plan}.md`, #418 — the crown-driven amount+category composer, posting as pending) was authored concurrently in another session and **remains to be implemented**. This increment shipped first and covers the *repeat-last* case: one tap re-adds a recent expense. The two share the transport, the pending-status policy, and the dedupe ring; the composer rides on top (its `WatchQuickAddCatalog` / `WatchQuickAddPayload` types are additive next to the template types below).

## What shipped (#417)

- **Wire:** `WatchSnapshotPayload.recents: [WatchQuickAddItem]?` (optional — CP1/CP2 payloads decode as nil, both directions tested) — up to 3 templates from `Selectors.recentExpenses`, ledger stamped at push time. `WatchQuickAddRequest { id, item }` is the watch→phone body; `WatchMoney.short(_:currency:)` extracted so rows format in the item's native currency.
- **Watch:** a "Quick add" section on the glance; tap → `transferUserInfo(["quickAdd": data])` (queued, survives unreachability) → checkmark meaning *queued*.
- **Phone:** `PhoneWatchLink.didReceiveUserInfo` → `QuickAddDedupe` (persisted 200-id ring, `finch.watch.processedQuickAddIds`, per the CP3 spec §3) → `store.apply(.addTransaction, …)` via the pure `quickAddArgs` mapping — `-abs` amount, today's date, **`status: "pending"`** (adopted from the CP3 spec: wrist entries are provisional; Pending review is the confirm surface) → immediate `WidgetSnapshotWriter.write` push-back as the ack.

## Deliberate divergences from the composer spec (recorded, not accidental)

- **Merchant:** templates carry the original row's real merchant (better data than the composer's category-name placeholder — the merchant is known here).
- **Category:** the template's own category rides along (the composer picks from a catalog).
- No entry catalog needed — templates are self-contained; the catalog arrives with the composer build.

## Verification

+7 FinchAppTests (payload/request round-trips, legacy decode, args mapping incl. pending status, dedupe ring first-seen/persistence/eviction). Builds ride CI (FinchApp/FinchMac/FinchWatch). Paired-sim round-trip is a by-hand step: tap template → phone Pending shows the row → confirm → watch figures update on the push.
