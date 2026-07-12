# Spec: what-if sliders — interactive category-cut hypotheticals (web #411 → iOS)

**Date:** 2026-07-12
**Status:** design approved, ready for implementation plan
**Scope:** native app (`ios/`) — a `FinchCore` selector + one new Insights card. Port of the web feature shipped in #411 (`frontend/lib/select.ts` `whatIfBaseline` + `frontend/components/what-if-card.tsx`, FEATURE_IDEAS §3.3); closes the **last** web→iOS parity gap recorded in the handoff (#424).

## Goal

An Insights card that answers *"if I cut category X by N%, what would I save?"* — per-category sliders over a real-history baseline, showing monthly/annual savings and the effect on average monthly net. Pure client math over projected data; **nothing persists**.

## Web reference (the port contract)

- `whatIfBaseline(txns, ledgerId, anchorMonth, {windowMonths=3, topN=5})` → `{ months, categories: [{categoryId, avgMonthly}], avgIncome, avgSpend } | null`:
  - Averages `categorySpend` over up to `windowMonths` trailing **complete** months before the (likely partial) anchor month; months with **no confirmed spend are dropped** from the average (a fresh ledger isn't diluted toward zero).
  - When **no** complete month has spend, the anchor month itself is the (1-month) window.
  - Returns `null` when there's no spend anywhere (income-only history is also `null`).
  - `categories` = top-`topN` by `avgMonthly` (positive only), descending, values `r2`-rounded.
  - `avgIncome` / `avgSpend` = confirmed income and total spend (all categories, refunds netted via the spend helpers, pending/transfers/other ledgers excluded) summed over the same window months ÷ window length.
- The card: one slider per baseline category; slider math (`save = avgMonthly × pct/100`) lives in the view; totals = `monthlySave` (sum), `annual = monthlySave × 12`, `netBefore = avgIncome − avgSpend`, `netAfter = netBefore + monthlySave`; Reset clears; state is component-local.

## Design

### 1. `FinchCore` selector — exact port

- New file `ios/FinchCore/Sources/FinchCore/Selectors/WhatIf.swift`:
  - `public struct WhatIfBaseline: Equatable { public let months: [String]; public let categories: [Category]; public let avgIncome: Double; public let avgSpend: Double; public struct Category: Equatable { public let categoryId: String; public let avgMonthly: Double } }`
  - `public static func whatIfBaseline(_ txns: [Tx], _ ledgerId: String, _ anchorMonth: String, windowMonths: Int = 3, topN: Int = 5) -> WhatIfBaseline?` in `extension Selectors`.
  - Implementation mirrors the web line-for-line using the existing helpers (all verified present): `categorySpend(_:_:month:)`, `monthsBack(_:_:)`, `prevMonth(_:)`, `ledgerOf/kindOf/isSpend`, `r2(_:)`. Same guards: empty `anchorMonth` → `nil`; window months filtered to those with spend > 0; anchor fallback; `nil` when categories end up empty.
- **Tests** (`ios/FinchCore/Tests/FinchCoreTests/WhatIfTests.swift`): port the web's four cases verbatim —
  1. averages over trailing complete months (partial anchor excluded; `(110+90)/2 = 100`, `avgIncome 250`, `avgSpend 115`),
  2. anchor-month fallback when no complete month has spend,
  3. `nil` for empty / pending-only / other-ledger-only / income-only histories,
  4. `topN` cap sorted descending + refunds netting against spend.

### 2. `WhatIfCard` — new Insights card

- Private struct in `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`, placed **after `SavingsRateCard`** in the card stack (both are "reflect on your spending" cards; approved placement).
- Data: `Selectors.whatIfBaseline(store.txns, store.activeLedgerId, String(store.today.prefix(7)))`. Card renders nothing-to-show state (`Card` with a muted "Not enough spending history yet" line) when the baseline is `nil`.
- Per category row: name via `store.categoryName(id) ?? id`, caption "avg ⟨`displayMoneyBase(avgMonthly)`⟩/mo", a **`Slider(value:in: 0...100, step: 5)`** (approved: 5% steps), and — when pct > 0 — "cut ⟨N⟩% → saves ~⟨`displayMoneyBase(save)`⟩/mo".
- Summary block (only when total `monthlySave > 0`): **annual figure** (`displayMoneyBase(monthlySave * 12)` + "per year"), a monthly chip, and "net ⟨before⟩ → ⟨after⟩" from `avgIncome − avgSpend` (+ savings). Idle prompt text when no cuts (mirrors web's `prompt`).
- **Reset** button in the card header row, visible when any cut is active; clears all sliders.
- Slider state: `@State private var cuts: [String: Double]` — component-local, **nothing persists** (web parity).
- A caption noting the window, e.g. "based on your last ⟨n⟩ month⟨s⟩" (web's `subtitle`).
- All money via `store.displayMoneyBase` → privacy mode masks the amounts for free; sliders/percentages stay live (masked-mode behavior matches the web, where the mask applies to `useMoney` strings only).

## Non-goals

- No persistence of cuts; no DB/engine mutation.
- No "years to $50k" savings-goal projection (web didn't ship it; FEATURE_IDEAS wording only).
- No new chart primitives; no changes to other cards or selectors beyond the new file.
- No zh-Hans catalog work in this feature (strings land in English; the localization workstream sweeps periodically).

## Testing / verification

- **Unit:** the four ported `WhatIfTests` via `swift test` (FinchCore, Bun-free pure Swift) — plus they run in CI's FinchCore job.
- **Builds:** `FinchApp` (iOS) + `FinchMac` (macOS) — the card is plain SwiftUI (`Slider` is cross-platform).
- **Simulator visual check:** card renders under Insights after the savings-rate ring; dragging a slider updates the row save-line and summary live; Reset clears; privacy mode masks the amounts while sliders keep working; empty-ledger state shows the muted line.

## Risks

- `InsightsTab.swift` keeps growing (15th card) — acceptable per existing pattern; if the macOS type-checker balks at the enlarged body (the known "reasonable time" trap), extract the card's rows into a small private subview rather than trimming behavior.
- `Slider` step/labels differ subtly on macOS — cosmetic; verify the FinchMac build and accept platform-default rendering.
