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
    /// Privacy mode: every day with spending gets the SAME shade. Opacity that
    /// scales with the amount *is* the amount — the grid ranked your days, so a
    /// glance picked out payday and rent day while every figure on screen read
    /// "••••". Masked, it answers only "did I spend that day?", the same thing
    /// the month calendar's presence dots answer.
    let masked: Bool

    private var maxValue: Double { values.map(\.value).max() ?? 0 }

    /// Empty day. Barely-there, so the grid still reads as a grid.
    private static let emptyOpacity = 0.06
    /// The floor for a day with spending, and the whole range's base.
    private static let minOpacity = 0.15
    /// The single shade every spending day gets while masked — deliberately one
    /// value, well clear of `emptyOpacity`, carrying no ranking at all.
    private static let maskedOpacity = 0.55

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
                            .fill(Color.accentColor.opacity(
                                Self.intensity(day.value, maxValue: maxValue, masked: masked)))
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

    /// Cell opacity. Pure and static so the privacy property is testable: while
    /// masked, every day with spending must return the SAME value, whatever the
    /// amount. Unmasked behaviour is unchanged.
    static func intensity(_ v: Double, maxValue: Double, masked: Bool) -> Double {
        if v <= 0 { return emptyOpacity }
        if masked { return maskedOpacity }
        guard maxValue > 0 else { return minOpacity }
        return minOpacity + 0.85 * (v / maxValue)
    }
}
