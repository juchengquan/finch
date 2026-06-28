# Feed dates: show only when they change

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** In the Activity feed, show a row's date only when it differs from the row above — within a run of same-date rows, only the first shows the date. Always-on; UI-only; no engine change.
**Context:** The variant scoped out of #371/#375 (relative dates + group/relative toggles). Complements those; no new toggle.

## Design (all in `Tabs/ActivityTab.swift`)

### 1. `TxRow` — optional date

`TxRow` is shared by the feed, `AccountDetailView`, and `CounterpartyDetailView`. Add a
defaulted flag so only the feed opts into suppression:

```swift
    var showDate: Bool = true
```
Wrap the date text (line ~505) — leaving the tag chips on the same line untouched:

```swift
                    if showDate { Text(dateTimeText).font(.caption2).foregroundStyle(.secondary) }
```
So a same-date row with no tags collapses to a single line; a same-date row with tags shows
just its tags. The two detail screens pass nothing → `showDate == true` (unchanged).

### 2. Feed — compute first-of-run

The feed is one ordered sequence (`sections.flatMap { $0.txns }`, date-desc, month-bucketed).
Add state:

```swift
    @State private var dateShownIds: Set<String> = []
```
In `recompute()`, after `sections = order.map { … }`, mark the first txn of each consecutive
same-date run:

```swift
        var shown = Set<String>(); var last: String?
        for txn in sections.flatMap({ $0.txns }) {
            if txn.date != last { shown.insert(txn.id); last = txn.date }
        }
        dateShownIds = shown
```
(Comparison is on the raw `txn.date`, so it's correct regardless of the relative-dates /
group-by-month toggles. Month boundaries are date changes, so grouped + flat both work.)

### 3. `row(_:)` — pass the flag

```swift
                TxRow(txn: txn, onPreviewReceipt: isSelecting ? nil : { previewReceipt($0) },
                      showDate: dateShownIds.contains(txn.id))
```

## Out of scope
- A toggle (always-on by design); suppressing the *time* separately; the detail/counterparty
  screens (always show the date). Engine changes.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** seed several same-day transactions → in the feed, the date appears on the
  **first** of each day-run only; later same-day rows omit it (tags, if any, remain). Toggling
  Group-by-month / Relative-dates still behaves; AccountDetail/Counterparty rows still show the
  date on every row.

## Notes
- Collision: `ActivityTab.swift` is actively edited — re-check `gh pr list` + rebase before
  pushing. PR → `feat/frontend`.
