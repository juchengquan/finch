import SwiftUI
import Charts

/// Categorical bar chart (one colored bar per labeled value).
struct BarChart: View {
    let data: [DataPoint]
    let xLabel: String
    let yLabel: String
    /// Optional dashed horizontal rule (e.g. a budget cap) drawn across the bars.
    var referenceLine: Double? = nil

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
                    .accessibilityValue(Text(String(format: "%.0f", point.value)))
            }
            if let referenceLine {
                RuleMark(y: .value(yLabel, referenceLine))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }
}
