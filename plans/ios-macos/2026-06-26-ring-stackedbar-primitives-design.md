# Insights primitives: Ring + StackedBar (port from web)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** Port the web `Ring` and `StackedBar` chart primitives to iOS as reusable SwiftUI views in `Common/ChartViews/`, each with a `#Preview`. No screen wiring, no engine change.

## Problem

`frontend/components/primitives.tsx` has `Ring` (circular progress) and `StackedBar`
(proportional segmented bar), used for budget/forecast viz. iOS `Common/ChartViews/`
has Sparkline / BarChart / AreaChart / Donut / Sankey / CalendarHeatmap but **not these
two** (parity inventory, Tier 3). Porting them completes the primitive set so future
budget/forecast viz on iOS has the same building blocks (this task does not wire them
into a screen).

## Design

### 1. `Ring.swift`

A circular progress ring: a track circle + a colored arc = `value/max`, round cap,
starting at top (web's `rotate(-90deg)`), optionally wrapping centered content.

```swift
import SwiftUI

/// Circular progress ring — track circle + a colored arc (value/max), round cap,
/// starting at the top, optionally wrapping a centered label. Port of the web `Ring`.
struct Ring<Label: View>: View {
    let value: Double
    var max: Double = 100
    var size: CGFloat = 48
    var stroke: CGFloat = 5
    var color: Color = .accentColor
    var track: Color = Color.secondary.opacity(0.25)
    @ViewBuilder var label: () -> Label

    private var pct: Double { Swift.max(0, Swift.min(1, max == 0 ? 0 : value / max)) }

    var body: some View {
        ZStack {
            Circle().inset(by: stroke / 2).stroke(track, lineWidth: stroke)
            Circle().inset(by: stroke / 2)
                .trim(from: 0, to: pct)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((pct * 100).rounded())) percent"))
    }
}

extension Ring where Label == EmptyView {
    init(value: Double, max: Double = 100, size: CGFloat = 48, stroke: CGFloat = 5,
         color: Color = .accentColor, track: Color = Color.secondary.opacity(0.25)) {
        self.init(value: value, max: max, size: size, stroke: stroke,
                  color: color, track: track) { EmptyView() }
    }
}

#Preview("Ring") {
    HStack(spacing: 16) {
        Ring(value: 30) { Text("30%").font(.caption2) }
        Ring(value: 75, color: .orange)
        Ring(value: 100, color: .green, track: .green.opacity(0.2))
    }
    .padding()
}
```
`Circle().inset(by: stroke/2)` keeps the stroke inside `size` (matches the web's
`r = (size - stroke) / 2`). `.trim` is applied to the inset `Circle` (a `Shape`), then
stroked — so the arc length tracks `pct`.

### 2. `StackedBar.swift`

A horizontal bar of proportional colored segments, 2pt gaps, rounded; **width adapts to
the container** (vs the web's fixed `280`).

```swift
import SwiftUI

/// Horizontal stacked bar of proportional colored segments (2pt gaps, rounded). Port of
/// the web `StackedBar`; width fills the container.
struct StackedBar: View {
    struct Slice: Identifiable { let id = UUID(); let value: Double; let color: Color }
    let slices: [Slice]
    var height: CGFloat = 8
    var cornerRadius: CGFloat = 4
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let total = Swift.max(slices.reduce(0) { $0 + $1.value }, 0.0001)
            let usable = Swift.max(geo.size.width - gap * CGFloat(Swift.max(slices.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(slices) { s in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(s.color)
                        .frame(width: usable * (s.value / total))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview("StackedBar") {
    StackedBar(slices: [
        .init(value: 3, color: .blue),
        .init(value: 2, color: .green),
        .init(value: 1, color: .orange),
    ])
    .frame(width: 280)
    .padding()
}
```

## Out of scope
- Wiring either primitive into a screen (Budgets/Insights — owned by the other work
  stream); any engine change. They join the `ChartViews/` library for future use.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) — both compile the new views.
- **Visual:** the `#Preview`s render the components in Xcode's canvas (a CLI screenshot of
  a SwiftUI `#Preview` isn't available; the build is the automated check).

No engine test — pure presentation primitives.

## Notes
- Mirrors the existing `ChartViews/` style (one focused view per file, SwiftUI shapes).
- Unused internal types don't warn in Swift; `#Preview` references keep them exercised in DEBUG.
- PR targets `feat/frontend`.
