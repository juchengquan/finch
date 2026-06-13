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

- ✅ **Settings storage: UserDefaults vs app_state.** **Resolved (user
  confirmed): UserDefaults.** A biometric policy is a *device* preference — it
  must not travel inside an exported `.finch` pack onto another device. Diverges
  intentionally from the design's `app_state`.
- ✅ **Sensitive-action gating coverage.** **Resolved (user): expand to
  change-base.** `confirmSensitive()` now gates both **Export** and
  **changeLedgerBase** (the ledger editor) when sensitive-actions is on. A future
  delete-all should call it too.
- ⏳ **`onIdle` precision.** Implemented as "now − lastActivity > timeout",
  re-evaluated on foreground/interaction rather than via a live idle timer (no
  background timer firing while truly idle). Adequate for a lock-on-return model;
  a true idle timer is a refinement.

## 6.4 — App Intents

- ⏳ **Siri AddTransaction sign = expense.** A voiced "add a $6 coffee" posts a
  negative (expense) amount. **Default chosen:** always expense via Siri; income
  isn't distinguished (no clean way to phrase it). A future `AddIncomeIntent`
  could cover it.
- ⏳ **MarkCleared default count = 5.** "Mark my transactions cleared" with no
  number clears the 5 most-recent (setCleared). Arbitrary default; matches the
  design's example phrasing.
- ⏳ **No biometric re-auth for Siri writes.** Per the design's non-goal: a
  Siri-dispatched write isn't gated by Phase 6.3 (the user already authed to the
  device). Revisit if sensitive Siri actions should re-prompt.
- ⏳ **Account/category fallback.** When Siri omits account/category, the intent
  uses the *first* account / first non-system category rather than a
  most-recently-used heuristic (the design's `mostRecentAccountId` convenience
  isn't built). Good enough; an MRU heuristic is a refinement.
