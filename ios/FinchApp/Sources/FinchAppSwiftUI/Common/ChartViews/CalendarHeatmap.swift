import SwiftUI

/// A GitHub-style daily-spend intensity grid (7 rows = weekdays, N week columns).
/// Cell opacity scales with the day's spend relative to the max. Port of the
/// web Insights calendar heatmap.
struct CalendarHeatmap: View {
    /// Daily values in date order (oldest → newest).
    let values: [(date: String, value: Double)]
    /// Formats a day's value for VoiceOver. The caller owns it because this view
    /// has no store — and it must go through the privacy-aware display helpers:
    /// interpolating the raw `Double` spoke the exact unconverted figure
    /// ("2026-07-15: 1850.000000") to a screen reader even with amounts masked.
    let format: (Double) -> String

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
                            .accessibilityLabel(Text(verbatim: Self.cellLabel(date: day.date, value: day.value, format: format)))
                    }
                }
            }
        }
    }

    /// One cell's VoiceOver text. Pure so it can be tested — this defect is
    /// invisible on screen (only a screen reader ever spoke the figure), so no
    /// screenshot can catch a regression here.
    static func cellLabel(date: String, value: Double, format: (Double) -> String) -> String {
        "\(date): \(format(value))"
    }

    private func intensity(_ v: Double) -> Double {
        guard maxValue > 0, v > 0 else { return v > 0 ? 0.15 : 0.06 }
        return 0.15 + 0.85 * (v / maxValue)
    }
}
