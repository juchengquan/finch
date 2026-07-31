import SwiftUI
import Charts

/// A simple monotone line chart over string-x / double-y points.
struct LineChart: View {
    let data: [DataPoint]
    let xLabel: String
    let yLabel: String
    /// Formats a value for VoiceOver — see `BarChart.format`.
    let format: (Double) -> String
    /// Privacy mode — see `BarChart.masked`.
    let masked: Bool

    struct DataPoint: Identifiable, Equatable {
        let id = UUID()
        let x: String
        let y: Double
    }

    var body: some View {
        Chart(data) { point in
            LineMark(x: .value(xLabel, point.x), y: .value(yLabel, point.y))
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)
                .accessibilityLabel(Text(point.x))
                .accessibilityValue(Text(format(point.y)))
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel() } }
        .maskedYAxis(masked)
    }
}
