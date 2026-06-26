# Widgets CP1 — lock-screen / accessory families (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** `ios/FinchWidget/FinchWidget.swift` only — add the three accessory (lock-screen) widget families to the existing **FinchOverview** widget. **No engine/snapshot/plumbing change.** First CP of the "deepen widgets" sub-project (native-surfaces enhancement; all web↔iOS parity is already closed).

## Problem

The widget supports only `.systemSmall`/`.systemMedium` (Home Screen). There's no **lock-screen** presence — the accessory families (`accessoryCircular`, `accessoryRectangular`, `accessoryInline`) aren't offered, even though the shared `WidgetSnapshot` already carries everything they'd need.

## Key findings (verified — purely additive)

- App Group `group.com.juchengquan.finch` + the shared `WidgetSnapshot` (FinchCore: `netWorth`, `currency`, `budgetUsedPct` 0–100, `weeklySpent`, `generatedAt`) are already wired; the widget reads it via `AppGroup.readWidgetSnapshot()`. The app rewrites it on every mutation + `WidgetCenter.reloadAllTimelines()`.
- Current `FinchWidget`: `StaticConfiguration(kind: "FinchOverview")`, `supportedFamilies([.systemSmall, .systemMedium])`, `FinchWidgetView` (net worth + budget gauge + week spend), `money(_:_:)` formatter, `.containerBackground(.fill.tertiary, for: .widget)`.
- Accessory families need iOS 16+ (app targets iOS 17). No new data, no App-Group/intent work (those are CP2/CP3).

## CP1 decisions (locked)

1. Extend the **existing** FinchOverview widget (not a new widget kind) — add the 3 accessory families + branch the view on `@Environment(\.widgetFamily)`.
2. Reuse `WidgetSnapshot` as-is. Nil snapshot → graceful "—" placeholder (the existing `money(nil,…)` already returns "—").

## Detailed design (`FinchWidget.swift`)

### `supportedFamilies`

```swift
.supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
```

### Family-branched `FinchWidgetView`

Add `@Environment(\.widgetFamily) private var family` and `switch` to per-family subviews; keep the current layout as the `default` (system) case:

- **`.accessoryCircular`** — a budget-usage ring:
  ```swift
  Gauge(value: Double(pct), in: 0...100) { Text("Budget") } currentValueLabel: { Text("\(pct)") }
      .gaugeStyle(.accessoryCircular)
  ```
  (`pct = entry.snapshot?.budgetUsedPct ?? 0`.)
- **`.accessoryRectangular`** — three compact lines (leading-aligned):
  - `Text("Net worth").font(.caption2)` + `Text(money(netWorth, currency)).font(.headline)`
  - `Text("Budget \(pct)% · Wk \(money(weeklySpent, currency))").font(.caption2)`
  - Wrap in `.widgetAccentable()` on the net-worth line.
- **`.accessoryInline`** — single element (inline accepts one Text/Label):
  ```swift
  Text("finch · \(money(netWorth, currency))")
  ```

### Container background

- System families keep `.containerBackground(.fill.tertiary, for: .widget)`.
- Accessory families render on the lock screen (vibrant/transparent) — give them `.containerBackground(.clear, for: .widget)` (still required on iOS 17, but transparent). Apply per-branch so system stays opaque and accessory stays clear.

### Reuse

The existing `money(_:_:)` formatter and `WidgetSnapshot`/`AppGroup` reader; no new types.

## Facts (verified)

- `FinchWidget.swift` structure as quoted above (StaticConfiguration, 2 families, FinchWidgetView, money formatter).
- `WidgetSnapshot` fields: `netWorth: Double`, `currency: String`, `budgetUsedPct: Int`, `weeklySpent: Double` (FinchCore). `AppGroup.readWidgetSnapshot() -> WidgetSnapshot?`.
- `FinchWidget` target depends on FinchCore + has the App Group entitlement; it's embedded by the FinchApp build.
- 0 open PRs touch the widget; other session is in Insights/charts + i18n.

## Testing

- **Build gate:** iOS (`FinchApp`, which embeds + compiles `FinchWidget`) + macOS (`FinchMac`). Existing `WidgetSnapshot` round-trip test stays green. No new unit test (view-only change).
- **Manual (sim):** add finch as a **lock-screen** widget (Customize Lock Screen → add widgets) in all three sizes — the circular ring shows budget %, the rectangular shows net worth + budget/week, the inline shows "finch · {net worth}". Home-screen small/medium unchanged. (Lock-screen accessory rendering is best confirmed in the lock-screen editor; controller will install + show.)

## Out of scope (later CPs / sub-projects)

A dedicated Budget/account widget + configurable `AppIntentConfiguration` + richer per-account snapshot (CP2); interactive quick-add `Button(intent:)` (CP3); the Watch complication (separate sub-project). No engine/snapshot/App-Group changes here.
