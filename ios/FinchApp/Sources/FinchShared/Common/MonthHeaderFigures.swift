import Foundation

/// The three figures a month section header shows: the month's net, what came in, and
/// what went out.
///
/// **Why the signs matter.** The header used to spell the last two out — "Income $X ·
/// Spent $Y" — and now distinguishes them by colour. But `MonthGrouping` returns income
/// and expense as positive MAGNITUDES, so with the words gone the two are the same
/// number in different ink, and colour is exactly the channel that disappears in a
/// greyscale screenshot, for a red/green-blind reader, and for VoiceOver. The sign
/// carries the meaning; the colour reinforces it.
///
/// Foundation-only and formatter-injected on purpose: the rules are testable without a
/// store, and the colour mapping stays in the view where it belongs.
public enum MonthHeaderFigures {

    /// What a figure means. The view maps this to a colour — grey, green, red.
    public enum Role: Equatable { case net, income, expense }

    public struct Figure: Equatable {
        public let text: String
        public let role: Role
    }

    /// `money` formats a ledger-base amount and is expected to sign it (see
    /// `FinchStore.displaySignedBase`).
    ///
    /// Privacy needs no branch here, and deliberately so: the formatter is what masks,
    /// returning the same dots for every amount. Were a sign stapled on afterwards it
    /// would newly reveal whether the month was up or down — something the header has
    /// never shown. Colour still says which column is which, and that is positional
    /// rather than data.
    public static func make(net: Double, income: Double, expense: Double,
                     money: (Double) -> String) -> [Figure] {
        [
            Figure(text: money(net), role: .net),
            Figure(text: money(income), role: .income),
            // Expense arrives as a positive magnitude, so it is negated to read as an
            // outflow. The zero guard is not pedantry: `-0.0` is not `< 0`, so a month
            // with no spending would otherwise format as an outflow of nothing.
            Figure(text: money(expense == 0 ? 0 : -expense), role: .expense),
        ]
    }
}
