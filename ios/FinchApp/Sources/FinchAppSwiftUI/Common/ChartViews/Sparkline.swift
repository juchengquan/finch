import SwiftUI
import Charts

/// A compact axis-free trend line; green when it ends up, red when it ends down.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        let up = (values.last ?? 0) >= (values.first ?? 0)
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                LineMark(x: .value("i", idx), y: .value("v", value))
                    .foregroundStyle(up ? .green : .red)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // Non-color cue: a direction glyph so up/down reads without relying on
        // green/red (colour-vision accessibility).
        .overlay(alignment: .topTrailing) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(up ? .green : .red)
                .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel("Trend")
        .accessibilityValue(up ? "trending up" : "trending down")
    }
}
