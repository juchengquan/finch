import SwiftUI
import Charts

/// Categorical bar chart (one colored bar per labeled value).
struct BarChart: View {
    let data: [DataPoint]
    let xLabel: String
    let yLabel: String

    struct DataPoint: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    var body: some View {
        Chart(data) { point in
            BarMark(x: .value(xLabel, point.label), y: .value(yLabel, point.value))
                .foregroundStyle(point.color)
                .accessibilityLabel(Text(point.label))
                .accessibilityValue(Text(String(format: "%.0f", point.value)))
        }
    }
}
