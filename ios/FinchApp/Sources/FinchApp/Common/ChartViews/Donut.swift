import SwiftUI
import Charts

/// Donut (sector) chart with a center label.
struct Donut: View {
    let data: [DataPoint]
    let centerLabel: String

    struct DataPoint: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    var body: some View {
        Chart(data) { point in
            SectorMark(angle: .value("Value", point.value), innerRadius: .ratio(0.6), angularInset: 1)
                .foregroundStyle(point.color)
                .cornerRadius(4)
                .accessibilityLabel(Text(point.label))
                .accessibilityValue(Text(String(format: "%.0f", point.value)))
        }
        .chartBackground { _ in
            Text(centerLabel).font(.caption).foregroundStyle(.secondary)
        }
    }
}
