# Recurring-charge (subscription) detector

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** A new `Selectors.detectRecurring` that finds repeating expense patterns in transaction history, surfaced as a **"Detected · not yet scheduled"** section on the Scheduled tab. Net-new feature; engine selector + tests + one UI section.

## Idea

Scan expense history for merchants charged at a consistent cadence + stable amount
(Netflix monthly, gym biweekly…) and surface the ones **not already covered by a
scheduled template** — so the user sees subscriptions they're paying for but haven't
tracked, plus a total monthly estimate. The advice engine (`InsightRules.swift`, 6
rules) covers nothing like this; no overlap.

## Engine

### `RecurringCharge` (new, in `Project/Models.swift`)

```swift
public struct RecurringCharge: Identifiable, Equatable, Sendable, Codable {
    public let id: String              // = merchantKey
    public let merchantName: String
    public let averageAmount: Double   // magnitude, 2dp
    public let cadence: String         // "weekly" | "biweekly" | "monthly" | "quarterly" | "yearly"
    public let monthlyEstimate: Double // averageAmount normalized to a month, 2dp
    public let occurrences: Int
    public let lastDate: String        // YYYY-MM-DD
    public let nextEstimatedDate: String
    public let isScheduled: Bool       // any matching tx has a sourceTemplateId
    public init(id: String, merchantName: String, averageAmount: Double, cadence: String,
                monthlyEstimate: Double, occurrences: Int, lastDate: String,
                nextEstimatedDate: String, isScheduled: Bool) { /* memberwise */ }
}
```

### `Selectors.detectRecurring` (new, `Selectors.swift`)

```swift
public static func detectRecurring(_ txns: [Tx], _ ledgerId: String, _ today: String,
                                   minOccurrences: Int = 3) -> [RecurringCharge]
```
Algorithm (reuses existing helpers `ledgerOf`/`kindOf`/`merchantKey`/`r2`/`cal`/`date`/`ymd`/`addDays`):
1. Keep **expenses** only (non-pending, active ledger); group by `merchantKey`.
2. Per group with **≥ `minOccurrences`** txns (sorted by date):
   - **Amount stability:** magnitudes' coefficient of variation `< 0.35` (roughly equal charges).
   - **Cadence:** day-gaps between consecutive charges → **median gap**; classify
     weekly `6–8` / biweekly `12–16` / monthly `26–35` / quarterly `80–100` /
     yearly `350–380`; reject if it fits none.
   - **Consistency:** every gap within ±40% of the median (rejects irregular spending).
   - **Active:** last charge within `1.6 × medianGap` days of `today` (drops cancelled subs).
   - `isScheduled` = any tx in the group has a non-empty `sourceTemplateId`.
   - `nextEstimatedDate = lastDate + medianGap days`; `monthlyEstimate` = mean normalized
     (weekly ×30/7, biweekly ×30/14, monthly ×1, quarterly ÷3, yearly ÷12).
3. Return sorted by `monthlyEstimate` desc.

Pure/additive — existing selectors untouched ⇒ `ParityTests` unaffected.

### Tests (`DetectRecurringTests.swift`)
- A merchant with 4 monthly ~equal charges → detected (cadence `monthly`, sensible `monthlyEstimate`).
- Irregular gaps / wildly varying amounts → **not** detected.
- A monthly series whose last charge is old → dropped (active filter).
- `isScheduled` true when the group's txns carry a `sourceTemplateId`.

## UI — Scheduled tab section

In `ScheduledTab` (list mode), add a section listing the **untracked** detected charges
(`!isScheduled`), below the scheduled templates:

```
Detected recurring · not scheduled            ~$48.97/mo · 3
  Netflix          Monthly · ~$15.99      next ~Jul 3
  Spotify          Monthly · ~$11.99      next ~Jul 8
  Gym              Biweekly · ~$21.00     next ~Jul 5
```
- A computed `detected = Selectors.detectRecurring(store.txns, store.activeLedgerId, store.today).filter { !$0.isScheduled }`.
- Section header shows the **total monthly estimate** + count; rows show merchant /
  cadence / `store.displayMoneyBase(averageAmount)` / next date. **Read-only** (v1).
- **Empty-state fix:** the tab currently shows `ContentUnavailableView` when
  `store.scheduled.isEmpty`. Change the gate to also consider `detected` — show the
  content (with just the detected section) when there are detections but no templates.
- Calendar mode unchanged.

## Out of scope (v1)
- An "Add to Scheduled" action (prefill the Scheduled sheet) — natural follow-up.
- Recurring **income** detection; per-charge dismiss/ignore; an Insights card.
- Any engine change beyond the additive selector.

## Testing
- **Engine:** `DetectRecurringTests` (above) + full `swift test` incl. ParityTests.
- **App:** build iOS + macOS.
- **Manual (sim):** seed a merchant with ~monthly equal expenses → the Scheduled tab
  shows a "Detected · not scheduled" section with it + a monthly total; a one-off
  merchant doesn't appear.

## Notes
- Date math via `Selectors.date/ymd/addDays/cal` (UTC gregorian). Display via `displayMoneyBase`.
- PR targets `feat/frontend`.
