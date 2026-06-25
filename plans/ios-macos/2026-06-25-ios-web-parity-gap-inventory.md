# iOS ↔ web parity gap inventory

**Date:** 2026-06-25
**Status:** Reference inventory (not a plan). A survey snapshot to pick future work from.
**Method:** Three domain surveys (money-management; analytics/viz; entry/admin/data/settings) cross-read web `frontend/` ↔ native `ios/FinchApp/`, then a 20-item confirm/refute verification pass against the iOS source. Only **verified** gaps are listed — several survey-claimed gaps were false (see "Already at parity").

Direction is **web → iOS** (features the web has that iOS lacks) unless noted. Severity is user-facing impact; effort is a rough guess.

## Tier 1 — biggest user-facing gaps

- **Scheduled: calendar view** — iOS `ScheduledTab` is a plain list; web has a month grid with per-day colored dots + day-detail pane + quick-add. *(High; ~5–6h)*
  - iOS: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift` (list only, no grid).
- **Scheduled: occurrence status** — no upcoming/pending/done state surfaced on generated occurrences. *(Med–High; ~3–4h)*
- **Budgets: rollover UI** — the model already projects `rollover`/`rolloverLimit`/`carryForward` (`Project/Budget.swift`, `Projections+State.swift:92-104`), but the **form can't set rollover** and the **detail doesn't show carried-forward**. UI-only work — the engine/data already support it. *(Med–High; low-ish effort)*
  - iOS: `WriteScreens/BudgetSheet.swift` (no rollover fields), `WriteScreens/BudgetDetailView.swift` (no carryForward display).
- **Insights: advice/rules engine** — iOS `InsightsTab` renders chart cards only; web runs ~6 narrative rules (spending trend, over-budget, pending-to-review, top-category mover, weekday skew, goal progress) from `frontend/lib/insights.ts`. *(Med–High; ~Med — port rules as `Selectors` + a card)*

## Tier 2 — solid wins

- **Accounts: reconcile status badge** — no "last reconciled / stale" indicator (web tracks `lastReconciledAt`/`lastReconciledBalance` with a 35-day stale threshold). *(Med; ~2–3h)*
  - iOS: `WriteScreens/AccountDetailView.swift`, `WriteScreens/ReconcileSheet.swift`.
- **Accounts: quick-add missing tx during reconcile** — the reconcile sheet can't add a missing transaction inline. *(Med; ~4–5h)*
- **Accounts: pending vs confirmed split** in account detail — currently one flat transaction list (web separates a "To confirm" section). *(Med; ~2–3h)*
- **Activity: saved searches** — filters are session-only; web persists named filter chips per-ledger (localStorage → UserDefaults on iOS). *(Med; ~3h)*
  - iOS: `TransactionFilterSheet.swift` (ephemeral filter state).
- **Budgets: per-account filter** — budgets match by category only; web also matches by account (multi-select). *(Med; ~3–4h)*

## Tier 3 — polish

- **Insights primitives:** `Ring` + `StackedBar` not ported (web uses them for budget/forecast viz; `frontend/components/primitives.tsx`). *(Low)*
- **Accounts: opening-balance display** in detail/edit (shown only at account creation). *(Low)*
- **Settings: theme toggle + locale/language picker** absent (`Tabs/SettingsTab.swift`). *(Low)*
- **Budgets: add-form frequencies** — the *create* sheet (`BudgetSheet`) offers 4 (weekly/monthly/quarterly/yearly); the change-cycle sheet already offers all 6 (adds daily/biweekly). Minor inconsistency. *(Low)*

## Already at parity (verified — no action)

These were checked and are present on iOS (some were falsely flagged as gaps by the raw surveys):
- **Ledger admin (recent work):** categories (hierarchy/icons/colors/search/reorder), tags (colors + counts), merchants (incl. **delete**), rules (full multi-condition builder), FX (source badge + currency picker). ✓
- **Transaction entry:** tags in **add** sheet, splits, transfers (FX), refunds, receipt attachments (add + edit), currency picker, soft duplicate detection, category suggestion. ✓
- **Accounts:** 30-day forecast + trough (`Selectors.accountForecast`, `AccountDetailView.forecastSection`), include-in-net-worth toggle (edit), account types/groups/archiving/colors. ✓
- **Budgets:** pending-amount display (`BudgetDetailView`), cycle-change sheet (`updateBudgetCycle`), category filters, contribution tracking, 3-color progress + days-left. ✓
- **Activity:** bulk recategorize + bulk delete + bulk confirm, anomaly badge (`isAnomaly`/`Selectors.anomalyScore`), filters (direction/date/amount/tag/status), day grouping. ✓
- **Goals:** by design = income budgets (web redirects `/goals` → budgets). ✓
- **Reports:** by design = a mode of Insights (Breakdown tab) on both. ✓

## iOS is *ahead* (web → would need to catch up; informational)

Not in our usual build-direction, but for completeness — iOS has these and web doesn't:
- CSV statement import (`StatementImport`), attachments in the **add** form (web is edit-only), iCloud + auto-backup + row-level sync, biometric app-lock / security policy, per-kind notifications.

## Shipped since this snapshot (iOS-original; not web→iOS parity)

Landed after `9406714` — mostly iOS-original UX, not parity catch-up:
- Edit-form parity with Add: **status / account / refund-link** (#283), **currency** (#296), **counterparty suggestions** (#312).
- Feed: **result count + no-results state** (#293), **filter by merchant** (#308).
- Rows: **refund badge** (#298), **tag colors** (#301).
- **In-app receipt preview** (Quick Look, #289); **merchant detail screen** (stats + transactions, #306).
- Infra: CI ~halved (#276) + docs-only skip (#278); SwiftUI-vs-UIKit policy (`ios/swiftui-vs-uikit.md`).

## iOS-original enhancement backlog (not web parity)

Ideas surfaced while building the above (out-of-scope cuts + product asks). These are
**not** web→iOS gaps — track separately from the parity tiers. Re-confirm none have
since shipped before picking.

**Small**
- Multi-tag filter (AND/OR) — the feed filter is single-tag.
- Feed sort options (amount / oldest-first) — currently fixed date-desc.
- Receipt **thumbnails** in the Edit list (vs the generic icon).
- Preview a receipt **from a transaction row** (in-app preview is Edit-only, #289).
- Deep-link **merchant detail → pre-filtered feed** ("see in feed"; pairs with #306/#308).

**Medium**
- **Kind reclassification** in Edit (change a transaction's type; needs leg rebuild).
- **Receipt scanning** (VisionKit document scanner) — a camera capture path beyond the photo picker.
- **Insights/analytics expansion** — spend-by-merchant report, net-worth-over-time. *(Overlaps the Tier-1 "Insights advice engine" above.)*
- **Notifications end-to-end check** — verify the budget/scheduled-alert scaffold actually fires.

**Large**
- **CloudKit sync maturity** — harden the inert sync scaffold into verified cross-device sync (needs container provisioning + multi-device testing). *(Not a parity gap — iOS-ahead scaffold; see "iOS is ahead".)*

**Corrections vs. an earlier informal list:** "Goals" is **not** a gap (goals = income budgets by design — see "Already at parity"); "saved filter presets" is the same item as Tier-2 **Activity: saved searches** above (track it there).

## Notes

- Parity snapshot: `feat/frontend` @ `9406714` (2026-06-25). The two sections above were
  reconciled in on 2026-06-25 from the session running-list. Re-verify before acting — work lands frequently.
- Pick order suggestion: **Scheduled calendar** (largest missing experience) and **Budget rollover UI** (best effort-to-value — engine already supports it) are the strongest Tier-1 candidates; **Insights advice engine** makes Insights feel materially smarter.
