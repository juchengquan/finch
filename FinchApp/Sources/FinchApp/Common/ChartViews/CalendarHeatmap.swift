import SwiftUI

/// A GitHub-style daily-spend intensity grid (7 rows = weekdays, N week columns).
/// Cell opacity scales with the day's spend relative to the max. Port of the
/// web Insights calendar heatmap.
struct CalendarHeatmap: View {
    /// Daily values in date order (oldest → newest).
    let values: [(date: String, value: Double)]

    private var maxValue: Double { values.map(\.value).max() ?? 0 }

    var body: some View {
        // Chunk into week columns of 7 (the input is already day-ordered).
        let weeks = stride(from: 0, to: values.count, by: 7).map { start in
            Array(values[start..<min(start + 7, values.count)])
        }
        HStack(alignment: .top, spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(intensity(day.value)))
                            .frame(width: 12, height: 12)
                            .accessibilityLabel("\(day.date): \(day.value)")
                    }
                }
            }
        }
    }

    private func intensity(_ v: Double) -> Double {
        guard maxValue > 0, v > 0 else { return v > 0 ? 0.15 : 0.06 }
        return 0.15 + 0.85 * (v / maxValue)
    }
}
