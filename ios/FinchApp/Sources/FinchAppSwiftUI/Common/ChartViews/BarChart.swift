import SwiftUI
import Charts

/// Categorical bar chart (one colored bar per labeled value).
struct BarChart: View {
    let data: [DataPoint]
    let xLabel: String
    let yLabel: String
    /// Formats a value for VoiceOver. Required, not defaulted, so every call site
    /// has to decide — these are money in the ledger's base currency, and the old
    /// `String(format: "%.0f", …)` spoke them unconverted and unmasked.
    let format: (Double) -> String
    /// Optional dashed horizontal rule (e.g. a budget cap) drawn across the bars.
    var referenceLine: Double? = nil
    /// Tap a bar (its x-band) → the bar's index in `data`. Requires unique
    /// labels — equal labels share one band and resolve to the first. nil = inert.
    var onBarTap: ((Int) -> Void)? = nil

    struct DataPoint: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    var body: some View {
        Chart {
            ForEach(data) { point in
                BarMark(x: .value(xLabel, point.label), y: .value(yLabel, point.value))
                    .foregroundStyle(point.color)
                    .accessibilityLabel(Text(point.label))
                    .accessibilityValue(Text(format(point.value)))
            }
            if let referenceLine {
                RuleMark(y: .value(yLabel, referenceLine))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartOverlay { proxy in
            if let onBarTap {
                GeometryReader { geo in
                    Rectangle().fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geo[plotFrame].origin.x
                            guard let label = proxy.value(atX: x, as: String.self),
                                  let i = data.firstIndex(where: { $0.label == label }) else { return }
                            onBarTap(i)
                        }
                }
            }
        }
    }
}
