# iOS ↔ web parity gap inventory

**Date:** 2026-06-25 (status refreshed 2026-06-26 @ `db6ab1c`)
**Status:** Reference inventory (not a plan). A survey snapshot to pick future work from. **Most tiers are now closed** — each item below is annotated ✅ (with PR) or **open**; see "Closed since snapshot" for the roll-up.
**Method:** Three domain surveys (money-management; analytics/viz; entry/admin/data/settings) cross-read web `frontend/` ↔ native `ios/FinchApp/`, then a 20-item confirm/refute verification pass against the iOS source. Only **verified** gaps are listed — several survey-claimed gaps were false (see "Already at parity").

Direction is **web → iOS** (features the web has that iOS lacks) unless noted. Severity is user-facing impact; effort is a rough guess.

## Tier 1 — biggest user-facing gaps — ✅ ALL CLOSED

- **Scheduled: calendar view** — ✅ **done (#307)** (month grid + day detail).
- **Scheduled: occurrence status** — ✅ effectively covered by the calendar view (#307); re-verify if a distinct upcoming/pending/done badge is still wanted.
- **Budgets: rollover UI** — ✅ **done (#311)** (form toggle + cap; carried-forward in detail).
- **Insights: advice/rules engine** — ✅ **done (#323)** (CP1 core 6 rules).

## Tier 2 — solid wins

- **Accounts: reconcile status badge** — ✅ **done (#329)**.
- **Accounts: quick-add missing tx during reconcile** — **open** *(Med; ~4–5h)* — the reconcile sheet still can't add a missing transaction inline.
- **Accounts: pending vs confirmed split** — ✅ **done (#329)**.
- **Activity: saved searches** — ✅ **done (#333)** (per-ledger filter chips).
- **Budgets: per-account filter** — ✅ **done (#337)** (account multi-select + detail scope).

## Tier 3 — polish

- **Insights primitives** (`Ring` + `StackedBar`) — ✅ **done (#342)**.
- **Accounts: opening-balance display** in detail/edit — **open** *(Low)* (shown only at account creation). *(Accounts is an active area — #329/#341 — coordinate.)*
- **Settings: theme toggle + locale/language picker** — ✅ **done (#338)**.
- **Budgets: add-form frequencies** — ✅ **done (#340)**.

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

**Done**
- Multi-tag filter Any/All (#314) · feed sort options (#321) · receipt thumbnails (#331) ·
  preview-from-row (#327) · merchant detail → pre-filtered feed (#318) ·
  kind reclassification (#319) · notifications end-to-end check + cancel-on-disable fix (#335).

**Still open**
- **Receipt scanning** (VisionKit document scanner) — *device-only* (no simulator camera).
- **Insights/analytics expansion** — spend-by-merchant report, net-worth-over-time *(core advice engine landed #323; these specific reports remain)*.
- **zh-Hans translation coverage** — the language switch works (#338) but some strings (e.g. tab labels) aren't in the catalog yet and fall back to English. *(Content pass on `Localizable.xcstrings`.)*

**Large**
- **CloudKit sync maturity** — harden the inert sync scaffold into verified cross-device sync (needs container provisioning + multi-device testing). *(Not a parity gap — iOS-ahead scaffold; see "iOS is ahead".)* *device-only.*

**Corrections vs. an earlier informal list:** "Goals" is **not** a gap (goals = income budgets by design — see "Already at parity"); "saved filter presets" is the same item as Tier-2 **Activity: saved searches** above (now done, #333).

## Closed since the `9406714` snapshot (roll-up)

Parity tiers: **Tier-1 fully closed** (#307/#311/#323); Tier-2 → only *quick-add-during-reconcile* open (#329/#333/#337 closed others); Tier-3 → only *opening-balance display* open (#338/#340/#342 closed others). Plus iOS-original UX (#283/#289/#293/#296/#298/#301/#306/#308/#312/#314/#318/#319/#321/#327/#331/#335) and accounts polish (#339 gear-to-leading, #341 tappable account transactions).

**What's genuinely left (web→iOS parity):** `Accounts: quick-add-during-reconcile` (Tier-2) and `Accounts: opening-balance display` (Tier-3) — both in the Accounts area (coordinate with the other stream). Everything else open is iOS-original (receipt scanning, insights reports, zh-Hans coverage) or device-only (CloudKit).

## Known CI flakes (non-blocking)

- **`frontend/lib/db/probe.test.ts:70`** — `probe (bun:sqlite): seedDatabase + a real
  insertTxRow round-trip works end-to-end` intermittently fails with
  `SQLiteError: UNIQUE constraint failed: categories.id`. Seen flaking the **Frontend**
  CI job on an **iOS-only** PR (#327) and clearing on re-run — i.e. not caused by the PR.
  Likely a non-idempotent seed / leaked test-DB state re-inserting a category id. **If it
  trips your PR, re-run the failed job;** a real fix is to seed idempotently or isolate
  the probe's test DB. (Frontend concern — noted here for whoever hits it on an unrelated PR.)

## Notes

- Original survey snapshot: `feat/frontend` @ `9406714` (2026-06-25). **Status refreshed 2026-06-26 @ `db6ab1c`** against merged PRs. Re-verify before acting — work lands frequently.
- Pick order suggestion (current): the parity surface is nearly exhausted — only **Accounts: quick-add-during-reconcile** (Tier-2) and **opening-balance display** (Tier-3) remain, both in the Accounts area (coordinate). The rest is iOS-original (receipt scanning, insights reports, zh-Hans coverage) or device-only (CloudKit).
