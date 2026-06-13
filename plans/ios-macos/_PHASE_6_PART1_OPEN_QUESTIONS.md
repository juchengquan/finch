# Phase 6 (part 1) — open questions parked during implementation

Built in one pass: **6.1 Spotlight, 6.2 Notifications, 6.3 Biometric, 6.4 App
Intents**. Rather than interrupt, I parked genuine product/scope questions here
with the default I chose, to reconcile at the end.

> Status legend: ⏳ open · ✅ resolved

## 6.1 — Spotlight

- ⏳ **Deep-link depth.** The design routes a tapped Spotlight result to a
  *detail* screen (Transaction Detail / Account Detail). Those detail screens
  don't exist yet (deferred to Phase 3/4). **Default chosen:** route to the
  owning *tab* (tx/counterparty → Activity, account → Accounts, category/budget
  → Budgets) and stash the tapped id in `DeepLinkRouter.focusedId` for a future
  detail/filter consumer. Revisit when Phase 3/4 add detail screens.
- ⏳ **Thumbnails.** The design wants per-entity thumbnail PNGs (category/account
  icons). **Default chosen:** omit `thumbnailURL` (Spotlight shows a default
  glyph) to avoid a PNG-generation subsystem in this pass. Low value vs. cost.

## 6.2 — Notifications

- (parked questions added as they arise)

## 6.3 — Biometric

- (parked questions added as they arise)

## 6.4 — App Intents

- (parked questions added as they arise)
