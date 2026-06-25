# Merchant detail → filtered Activity feed deep-link

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** A "See in Activity feed" action on the merchant detail screen that switches to the Activity tab pre-filtered to that merchant. UI/navigation only, no engine change.

## Problem

The merchant detail screen (#306) lists a merchant's transactions in a static
sub-screen (Settings → Power Tools → Merchants → detail). The feed gained a
**counterparty filter** (#308), but there's no way to jump from the detail into the
live, fully-interactive feed for that merchant.

## Design

Reuse the existing `DeepLinkRouter` (singleton; `@Published selectedTab` drives the
shell on iOS bottom-tabs + macOS sidebar) with a one-shot filter hand-off — same
spirit as its `focusedId`.

### 1. `DeepLinkRouter` — a pending-filter slot

In `DeepLink/DeepLinkRouter.swift`, alongside `focusedId`:

```swift
    @Published var pendingFilter: TxFilter?   // one-shot: consumed by the Activity feed
```
(Internal, not `public` — `TxFilter` is internal and lives in the same `FinchApp`
module. The class stays `public`; an internal stored property is fine.)

### 2. `ActivityFeedView` — consume it (Activity tab only)

In `Tabs/ActivityTab.swift`, add a flag so only the canonical Activity-tab instance
consumes the hand-off (the Ledger tab + Accounts' "All Transactions" reuse the same
view and must not race for it):

```swift
    var consumesPendingFilter: Bool = false
```
Apply the pending filter on appear and on change (mirrors the existing `focusedId`
handling). A small helper:

```swift
    private func consumePendingFilter() {
        guard consumesPendingFilter, let pending = router.pendingFilter else { return }
        searchQuery = ""
        filter = pending            // existing .onChange(of: filter) → recompute()
        router.pendingFilter = nil
    }
```
Wire it into the existing modifiers:

```swift
        .onAppear { consumeFocus(); consumePendingFilter(); recompute() }
        .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        .onChange(of: router.pendingFilter) { _, _ in consumePendingFilter() }
```
And the Activity tab opts in — `ActivityTab.body`:

```swift
        NavigationStack { ActivityFeedView(consumesPendingFilter: true) }
```
(The Ledger/Accounts instances keep the default `false`.)

### 3. `CounterpartyDetailView` — the button

In `PowerTools/CounterpartyDetailView.swift`, when the merchant has transactions, a
button that sets the filter then switches tab (uses `DeepLinkRouter.shared` directly,
as the App Intents do):

```swift
            if !txns.isEmpty {
                Section {
                    Button {
                        DeepLinkRouter.shared.pendingFilter = TxFilter(counterpartyId: counterparty.id)
                        DeepLinkRouter.shared.selectedTab = .activity
                    } label: {
                        Label("See in Activity feed", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
```
(Placed after the existing summary `Section`, before/around the Transactions section.)

## Behavior
- The deep-link **replaces** the feed's filter/search with `TxFilter(counterpartyId:)`
  (a clean "show me this merchant" jump); the Filter icon shows active; the user can
  **Clear** to reset.
- iOS: switches to the Activity bottom tab. macOS: selects Activity in the sidebar.
  Both observe `router.selectedTab`.

## Out of scope
- Carrying other filters across (always a fresh counterparty filter).
- Reaching the feed filtered from anywhere else (transaction-row merchant, etc.).
- Engine/parity changes — none; reuses the #308 counterparty filter path.

## Testing

**App (build + manual sim — UI/nav only):**
- Settings → Power Tools → Merchants → a merchant with transactions → **See in Activity
  feed** → app switches to the **Activity** tab, feed shows only that merchant's
  transactions (matches the detail's list), Filter icon active; **Clear** resets.
- A merchant with no transactions shows no button.
- iOS + macOS build.

No unit test — tab-switch + `@State` filter adoption isn't unit-testable; the
filtering itself is covered by #306/#308.

## Notes
- `DeepLinkRouter.shared` is the same instance the shell observes, so setting
  `selectedTab`/`pendingFilter` on it drives the UI (App Intents use this pattern).
- PR targets `feat/frontend`.
