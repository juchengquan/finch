# Feed rows: relative / short dates

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** Lighten the per-row date in the (now flat) transaction feed — show **Today / Yesterday / "Jun 25"** instead of the raw `2026-06-25`. One computed in `TxRow`. UI-only, no engine change.

## Problem

Since the feed went flat (#368), every row shows the raw ISO date `2026-06-25` (heavy,
techy, locale-neutral). A friendlier relative/short format reads better and **localizes**
(the raw ISO doesn't).

## Design

Rewrite `TxRow.dateTimeText` (`ActivityTab.swift`):

```swift
    private var dateTimeText: String {
        let base = relativeOrShort(txn.date)
        if let t = txn.time, !t.isEmpty { return "\(base) · \(t)" }
        return base
    }

    private func relativeOrShort(_ ymd: String) -> String {
        guard let d = AppDate.isoDay.date(from: ymd) else { return ymd }
        let today = AppDate.isoDay.date(from: store.today) ?? Date()
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: today)).day ?? 0
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "Yesterday") }
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: today)
        return d.formatted(sameYear ? .dateTime.month(.abbreviated).day()
                                    : .dateTime.month(.abbreviated).day().year())
    }
```

Behavior:
- **days == 0** → `Today` (catalog key already exists → 今天).
- **days == 1** → `Yesterday`.
- **otherwise** → short date: `Jun 25` (same year) / `Jun 25, 2025` (other year), via
  `Date.FormatStyle` which **auto-localizes** to the active language (→ `6月25日` under zh).
- **Future-dated** rows (days < 0, e.g. scheduled posts) fall through to the short date —
  no "Tomorrow" (kept simple).
- The **`· HH:MM` time** is appended unchanged when `txn.time` is set.

Surgical: one computed + one helper in `TxRow`. `store.today` (yyyy-MM-dd) and
`AppDate.isoDay` already exist; `TxRow` already has `@EnvironmentObject store`. No
cross-row logic, no `recompute()`/feed change, no engine change.

## Out of scope / logged follow-up
- **"Yesterday" zh-Hans:** not yet a catalog key, so under zh-Hans it renders English
  "Yesterday" until the next localization-refresh extracts + translates it (今天/Today
  already localizes; the short dates localize via `Date.FormatStyle`). Logged for the next
  loc pass — not run here (a full export+rebuild for one word is disproportionate).
- Showing the date only when it changes between rows; a weekday prefix.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** with `store.today` ≈ 2026-06-26, rows dated 2026-06-25 show **Yesterday**,
  2026-06-23 show **Jun 23**, and a row dated today shows **Today** — instead of raw ISO.

## Notes
- Collision: `ActivityTab.swift` is the other stream's active file — keep the diff to the
  one computed and re-check `gh pr list` before pushing. PR targets `feat/frontend`.
