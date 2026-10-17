import SwiftUI
import Charts
import FinchCore

/// The account screen's forecast: where the balance ends the window, its low point,
/// and the day-by-day line between — with a warning when the low point is below zero.
///
/// One view for both account screens, so they read alike: `AccountDetailVC` hosts it
/// as a LEAF cell (no scroll view of its own, so the collection view stays the scroll
/// view — see the hosting note atop that file), and `AccountDetailView` puts it in a
/// `Section`. Every figure comes from `AccountForecastPanel`, the same model the
/// low-balance alert reads.
///
/// Amounts go through `displayMoney(_:from:)`, so they are converted exactly as the
/// balance in the bar is and masked in privacy mode. The chart has no axis labels, so
/// it shows the shape of the month, never a figure — the rule `MaskedYAxis` states.
struct AccountForecastCard: View {
    @EnvironmentObject private var store: FinchStore
    let panel: AccountForecastPanel
    /// The account's currency — the forecast is in it.
    let currency: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                figure(label: String(localized: "In \(AccountForecastPanel.horizonDays) days"),
                       value: store.displayMoney(panel.endingBalance, from: currency),
                       caption: nil, tint: nil, alignment: .leading)
                Spacer(minLength: 0)
                figure(label: String(localized: "Low point"),
                       value: store.displayMoney(panel.low.balance, from: currency),
                       caption: lowCaption, tint: panel.warns ? .red : nil, alignment: .trailing)
            }
            chart
                .frame(height: 64)
                // Every figure the line encodes is stated in text above it.
                .accessibilityHidden(true)
            if let warning {
                // An HStack, not a `Label`: inside a list row `Label` takes the row's
                // icon column, which left a wide hole between the glyph and the words.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
            }
            Text("Scheduled items only — anything unplanned isn't counted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// "Today" when the balance never dips — the low point is where it starts.
    private var lowCaption: String {
        panel.dips ? AccountForecastPanel.dayLabel(panel.low.date) : String(localized: "Today")
    }

    private var warning: String? {
        guard panel.warns else { return nil }
        if let day = panel.crossesBelowZeroOn {
            return String(localized: "Drops below zero on \(AccountForecastPanel.dayLabel(day))")
        }
        return String(localized: "Already below zero")
    }

    private func figure(label: String, value: String, caption: String?, tint: Color?,
                        alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(tint ?? .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    /// A STEP line: the balance only moves on the days something is scheduled, and a
    /// smoothed curve would draw it drifting down between bills that have not happened.
    private var chart: some View {
        let points = Array(panel.balances.enumerated())
        let domain = yDomain
        let lowIndex = panel.forecast.series.firstIndex { $0.date == panel.low.date } ?? 0
        return Chart {
            ForEach(points, id: \.offset) { i, balance in
                AreaMark(x: .value("Day", i),
                         yStart: .value("Balance", domain.lowerBound),
                         yEnd: .value("Balance", balance))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.accentColor.opacity(0.12))
                LineMark(x: .value("Day", i), y: .value("Balance", balance))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.accentColor)
            }
            if panel.warns {
                RuleMark(y: .value("Balance", 0))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if panel.dips {
                PointMark(x: .value("Day", lowIndex), y: .value("Balance", panel.low.balance))
                    .foregroundStyle(panel.warns ? Color.red : Color.accentColor)
                    .symbolSize(36)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(1, points.count - 1))
        .chartYScale(domain: domain)
    }

    /// The balances' range, widened to include zero when the warning's zero line is
    /// drawn, and padded so the line never sits on the card's edge.
    private var yDomain: ClosedRange<Double> {
        var lo = panel.balances.min() ?? 0
        var hi = panel.balances.max() ?? 0
        if panel.warns { lo = min(lo, 0); hi = max(hi, 0) }
        let pad = max((hi - lo) * 0.1, 1)
        return (lo - pad)...(hi + pad)
    }
}
