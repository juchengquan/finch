import SwiftUI
import Charts

/// Gradient-filled area chart over string-x / double-y points.
struct AreaChart: View {
    let data: [DataPoint]
    let xLabel: String
    let yLabel: String

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
        }
    }
}
