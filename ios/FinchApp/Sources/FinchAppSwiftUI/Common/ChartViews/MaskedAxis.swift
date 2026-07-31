import SwiftUI
import Charts

/// Masks a chart's y-axis tick labels while privacy mode is on.
///
/// Swift Charts draws a numeric y-axis by default, and that axis prints the
/// exact scale — 0 / 1,000 / … / 4,000 — with the marks drawn to it. So a card
/// whose header already reads "•••• this month vs •••• last month" still handed
/// the figures to anyone looking at the screen: the tallest bar against a
/// labelled axis is a readable amount. Hiding the numbers everywhere else and
/// leaving them on the axis is the leak.
///
/// Masked charts keep their gridlines and ticks — the *shape* of the trend is
/// not the secret — and swap each label for the app's mask.
struct MaskedYAxis: ViewModifier {
    let masked: Bool

    func body(content: Content) -> some View {
        if masked {
            content.chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel { Text(verbatim: FinchStore.moneyMask) }
                }
            }
        } else {
            // Untouched: privacy off must render exactly as it always has.
            content
        }
    }
}

extension View {
    /// See `MaskedYAxis`.
    func maskedYAxis(_ masked: Bool) -> some View { modifier(MaskedYAxis(masked: masked)) }
}
