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
        .accessibilityElement()
        .accessibilityLabel("Trend")
        .accessibilityValue(up ? "trending up" : "trending down")
    }
}
