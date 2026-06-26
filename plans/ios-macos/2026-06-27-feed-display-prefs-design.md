# Activity feed display preferences: Group by month + Relative dates

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** Two Settings toggles — **Group by month** (month-header dividers) and **Relative dates** (Today/Yesterday vs absolute) — that the transaction feed honors. UI-only, no engine change.

## Problem

The feed went fully flat (#368) with relative dates (#371). Users want (a) light
structure back via **month** dividers (not the old per-day headers), and (b) **control**
over both behaviors in Settings.

## Design

### 1. Preferences (`@AppStorage`, both default ON)

- `finch.feed.groupByMonth` — `Bool`, default **true** (month dividers on).
- `finch.feed.relativeDates` — `Bool`, default **true** (the #371 Today/Yesterday behavior).

No shared model: each consuming view declares its own `@AppStorage` with the same key.

### 2. Settings UI (`SettingsAppearanceView`)

Add a section (before `.navigationTitle`) and the two prefs:

```swift
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    @AppStorage("finch.feed.relativeDates") private var relativeDates = true
```
```swift
            Section("Activity feed") {
                Toggle("Group by month", isOn: $groupByMonth)
                Toggle("Relative dates", isOn: $relativeDates)
            }
```
(Lives in the existing Appearance & Language page — it's already the display-prefs page.)

### 3. Feed — group by month (`ActivityFeedView`)

- Add `@AppStorage("finch.feed.groupByMonth") private var groupByMonth = true`.
- **`recompute()`** buckets by **month** (`yyyy-MM`) instead of day — the only change is
  the bucket key:
  ```swift
        var order: [String] = []
        var byMonth: [String: [Tx]] = [:]
        for txn in f.prefix(visibleCount) {
            let key = String(txn.date.prefix(7))           // "yyyy-MM"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(txn)
        }
        sections = order.map { DaySection(id: $0, txns: byMonth[$0] ?? []) }
  ```
  (`DaySection` is the existing `(id, txns)` pair — now keyed by month; kept as-is to
  minimise churn in this hot file.)
- **Render** — conditional on the pref:
  ```swift
                    if groupByMonth {
                        ForEach(sections) { section in
                            Section(monthLabel(section.id)) {
                                ForEach(section.txns) { txn in row(txn) }
                            }
                        }
                    } else {
                        ForEach(sections.flatMap { $0.txns }) { txn in row(txn) }
                    }
  ```
- **`monthLabel`** helper (localized via `Date.FormatStyle` → "June 2026" / "2026年6月"):
  ```swift
      private func monthLabel(_ key: String) -> String {
          guard let d = AppDate.isoDay.date(from: "\(key)-01") else { return key }
          return d.formatted(.dateTime.month(.wide).year())
      }
  ```
- Re-render on toggle: `.onChange(of: groupByMonth) { _, _ in recompute() }`.

### 4. Feed — relative dates (`TxRow`)

- Add `@AppStorage("finch.feed.relativeDates") private var relativeDates = true`.
- Guard at the top of `relativeOrShort`: when OFF, return the **raw absolute date**:
  ```swift
      private func relativeOrShort(_ ymd: String) -> String {
          guard relativeDates else { return ymd }   // OFF → 2026-06-25
          ... existing Today/Yesterday/short-date logic ...
      }
  ```

## Out of scope
- A separate Settings page; "show date only when it changes"; per-row time changes; "Yesterday" zh-Hans (existing logged follow-up). Any engine change.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** default → feed shows **"June 2026"** month headers with Today/Yesterday rows.
  Settings → **Group by month OFF** → flat list (no headers). **Relative dates OFF** → rows
  show raw `2026-06-25`. Toggles apply live.

## Notes
- Collision: `ActivityTab.swift` is the other stream's active file — keep diffs tight,
  re-check `gh pr list` before pushing. PR targets `feat/frontend`.
