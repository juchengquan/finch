import SwiftUI
import Charts

/// Gradient-filled area chart over string-x / double-y points.
struct AreaChart: View {
    let data: [DataPoint]
    let xLabel: String
    let yLabel: String
    /// Formats a value for VoiceOver — see `BarChart.format`. This view has no
    /// call sites today; the parameter is required so the first one to adopt it
    /// inherits the safe behaviour rather than copying the old raw formatting.
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
            AreaMark(x: .value(xLabel, point.x), y: .value(yLabel, point.y))
                .foregroundStyle(.linearGradient(
                    colors: [.blue.opacity(0.4), .blue.opacity(0.1)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
                .accessibilityLabel(Text(point.x))
                .accessibilityValue(Text(format(point.y)))
        }
        .maskedYAxis(masked)
    }
}
