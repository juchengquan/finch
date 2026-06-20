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
        // Non-color cue: a text legend (label + value) beside the donut so slices
        // are identifiable without relying on colour alone.
        HStack(spacing: 12) {
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
            if !data.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(data) { point in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(point.color).frame(width: 8, height: 8)
                            Text(point.label).font(.caption2).lineLimit(1)
                        }
                    }
                }
                .accessibilityHidden(true)   // the sectors already carry labels for VoiceOver
            }
        }
    }
}
