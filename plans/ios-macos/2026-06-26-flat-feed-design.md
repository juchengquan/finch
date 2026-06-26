# Activity feed: flat dated list (drop day-section headers)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** Remove the per-day section headers in the transaction feed so it reads as one continuous list; each row already carries its own date. UI-only, minimal diff.

## Problem

The feed currently renders the date **twice**: as a `Section(section.id)` **day header**
*and* on **every row** (`TxRow.dateTimeText`, added in #366). A day with N transactions
shows the date N+1 times. Removing the headers (keeping the per-row date) de-duplicates
and makes the layout more compact (no header rows).

## Design

In `ActivityTab.swift`, replace the day-grouped render:

```swift
                    ForEach(sections) { section in
                        Section(section.id) {
                            ForEach(section.txns) { txn in
                                row(txn)
                            }
                        }
                    }
```
with a flat list (no Section headers):

```swift
                    ForEach(sections.flatMap { $0.txns }) { txn in
                        row(txn)
                    }
```

- `sections` is already built in date-desc order by `recompute()`; flattening its
  day-buckets preserves that order. `Tx` is `Identifiable`, so `ForEach` keys cleanly.
- **Nothing else changes:** `recompute()`/`DaySection` stay (they still compute the
  ordered, paginated set — we just don't render the headers); the result-count caption,
  sort menu, filter, pending-confirm section, multi-select, and "Load more" are untouched.
- `TxRow` is unchanged — each row keeps its `dateTimeText` (date · time) line.

This is the smallest possible change (one render block) — deliberate, because
`ActivityTab.swift` is an actively-edited file (#366).

## Out of scope
- Shortening / relativizing the per-row date (e.g. "Jun 25" / "Today") or showing it
  only when it changes between rows — a separate polish if wanted.
- Any change to `TxRow`, `recompute()`, sorting, or `DaySection`.
- A per-day total (would belong with the headers, which we're removing).

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** the feed shows **no "2026-06-25" day headers** — a single continuous
  list where each row shows its own date; sort/filter/count/Load-more still work.

## Notes
- Collision: `ActivityTab.swift` is the other stream's active file — keep the diff tiny
  and re-check `gh pr list` before pushing. PR targets `feat/frontend`.
