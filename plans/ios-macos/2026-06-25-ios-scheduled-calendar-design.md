# Scheduled calendar view (iOS)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** iOS `ScheduledTab` — add a month-grid **calendar** lens alongside the existing template list + small FinchCore additions. **No engine change** beyond projecting an existing column. iPad/Mac share the view.

## Problem

The iOS Scheduled screen is a plain template list. The web has a **month calendar**: a grid with per-day colored dots (one per occurrence), a selected-day detail pane showing each occurrence's status (upcoming/pending/done) + actions, and an "Upcoming" fallback. This is the largest missing iOS↔web experience. The engine already supports it — `Selectors.occurrencesUpTo` expands a template into its occurrence dates, and `Tx.sourceTemplateId`/`pending` already exist for status — so this is mostly UI.

## Goal

- A **List | Calendar** segmented toggle at the top of `ScheduledTab`. **List** = the current template view, unchanged.
- **Calendar:** month nav (`‹ Month YYYY ›` + **Today**); a 7-column (Sun–Sat) grid where each day shows its number + up to **3 colored dots** (one per occurrence, by template color) + a **"+N"** overflow; today ring; selected highlight.
- **Selected-day detail:** that day's occurrence rows — template name, amount, account/category, a **status badge** (upcoming/pending/done), **Edit** (→ `ScheduledSheet`), and **Post now** (for unposted). No day selected → an **"Upcoming"** list of the next occurrences.
- **Quick-add:** a `+` in the day-detail header opens `ScheduledSheet` prefilled with the selected date as `startDate`.

## Non-goals

- No new recurrence/occurrence engine logic (reuse `occurrencesUpTo`).
- No drag/reschedule on the grid; no week/agenda views; no editing an occurrence's date (Post now posts at "today", matching the web).
- No change to the existing List view's behavior; no schema/engine change (only project an existing column).

## Key decisions (locked)

1. **Toggle, not replace** — keep the template-management list; add the calendar as a second lens (mirrors Insights' Trends/Breakdown).
2. **Reuse `Selectors.occurrencesUpTo`** for expansion; derive status in a pure selector from `store.txns`.
3. **Month nav = chevrons + Today** (not dropdowns); **max 3 dots + "+N"**; **day-detail quick-add prefills `startDate`**.
4. **No engine change** beyond projecting `scheduled_templates.color`.

## Detailed design

### Projection (FinchCore)

`ScheduledTemplate` (`Selectors/Forecast.swift`) gains `public let color: String?` (init param defaulted `nil`). The scheduled projection (`Projections+State.swift`, the `SELECT t.id … FROM scheduled_templates`) adds `t.color` and passes `color: r["color"]`. (Column already exists in the DB.)

### Selectors (FinchCore, pure, testable)

Both added to the `Selectors` type (wrapping the existing internal `occurrencesUpTo`):

```swift
/// All occurrences of the given templates within [from, through] (inclusive),
/// each paired with its template. Sorted by date.
public static func occurrencesInRange(_ templates: [ScheduledTemplate], from: String, through: String)
    -> [(date: String, template: ScheduledTemplate)]
// impl: for t in templates { for d in occurrencesUpTo(t, through) where d >= from { … } }, sorted by date

/// Maps "templateId|date" → isPending for every posted occurrence (txns whose
/// sourceTemplateId is set). Absent key ⇒ upcoming; present ⇒ pending(true)/done(false).
public static func scheduledPostedMap(_ txns: [Tx]) -> [String: Bool]
// impl: for t in txns, if let s = t.sourceTemplateId { out["\(s)|\(t.date)"] = (t.pending ?? false) }
```

A small status helper (view-side or selector): `status(templateId, date) = postedMap["\(id)|\(date)"]` → `nil` = `.upcoming`, `true` = `.pending`, `false` = `.done`.

### `ScheduledTab` (FinchApp)

- A `@State mode: .list | .calendar`, a `Picker(.segmented)` at the top.
- **List** branch: the existing list (`ScheduledRow`, swipe/post/edit/delete) verbatim.
- **Calendar** branch: a new `ScheduledCalendarView`.

### `ScheduledCalendarView` (new, FinchApp)

State: `visibleMonth` (anchored on `store.today` initially), `selectedDay: String?` (iso).
- **Header:** `‹` / `›` step the month; centered "Month YYYY"; a **Today** button (→ current month + select today).
- **Weekday row:** S M T W T F S.
- **Grid:** compute the visible month's day cells with leading blanks (first weekday) + trailing fill to complete weeks. Per real day cell:
  - day number; **today** = ring/accent; **selected** = filled highlight; tappable → set `selectedDay`.
  - up to 3 dots (`Color(hex: template.color) ?? .accentColor`) from that day's occurrences; `+N` text if more.
  - occurrences for the month come from `Selectors.occurrencesInRange(store.scheduled, from: monthStart, through: monthEnd)`, bucketed by date (computed once per render).
- **Detail pane** (below the grid):
  - selected day → "EEE MMM d" header + a `+` (quick-add → `ScheduledSheet` prefilled `startDate = selectedDay`) + the day's occurrence rows.
  - no selection → "Upcoming" header + the next N occurrences (`occurrencesInRange(from: today, through: today+~90d)` capped).
  - **Occurrence row:** template color dot, name, amount (`store.displayMoney` / native), account or category, a **status badge**, context actions: **Edit** (`ScheduledSheet(template)`), **Post now** (`postScheduled` by templateId) when status == upcoming.
- **Status badge:** capsule — done → green, pending → orange, upcoming → muted/secondary.

### Reuse / helpers

`Color(hex:)` (failable, `Common/Color+Hex.swift`); `store.today`, `store.scheduled`, `store.txns`, `store.displayMoney`; `AppDate` formatters; `ScheduledSheet` (existing add/edit; extend its init to accept an optional prefilled `startDate`).

## Facts (already present — verified)

- `Selectors.occurrencesUpTo(_ t:, _ throughInclusive:) -> [String]` expands a template across all frequencies (once/daily/weekly/biweekly/monthly/quarterly/yearly), bounded by endDate (`Forecast.swift:98`). Internal to FinchCore — the new public selectors wrap it.
- `Tx.sourceTemplateId: String?` + `Tx.pending: Bool?` exist (`Project/Models.swift`); `postScheduled` sets `sourceTemplateId` on the created entry.
- `scheduled_templates.color` exists in the DB; the iOS projection currently omits it.
- `ScheduledTemplate` fields: id/name/description/type/amount/frequency/dayOfMonth/weekDay/accountId/fromAccountId/categoryId/startDate/endDate/nextRun/maxExecutions/installmentTotal/installmentPaid (`Forecast.swift`).

## Testing

- **FinchCore:**
  - `occurrencesInRange`: a monthly template → lands on its day each month within the window; a weekly template → the right count of dates in a month; respects `startDate`/`endDate`; `once` → its single date if in range, else none; sorted.
  - `scheduledPostedMap`: a posted confirmed tx → `false` (done); a posted pending tx → `true` (pending); a tx with no `sourceTemplateId` → absent; status helper maps absent→upcoming.
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** Calendar tab shows the month grid with dots; tap a day → its occurrences with status badges; Post now on an upcoming one → it flips to done (a tx now links it); ‹/›/Today navigate; quick-add prefills the day; List toggle still works.

## Out of scope

Drag-reschedule; week/agenda views; editing an occurrence's individual date; schema/engine changes; web changes.
