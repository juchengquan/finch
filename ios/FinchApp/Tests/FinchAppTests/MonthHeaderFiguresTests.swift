import XCTest
@testable import FinchApp

/// The month header's three figures — net, in, out — and the signs that carry their
/// meaning when colour cannot.
///
/// Colour is the whole point of the redesign and also its weak spot: `MonthGrouping`
/// returns income AND expense as positive magnitudes, so with the old "Income · Spent"
/// words gone the two are the same number in different ink. A greyscale screenshot, a
/// red/green-blind reader and VoiceOver all see through that, so the sign does the
/// work and the colour reinforces it. These tests pin the signs.
final class MonthHeaderFiguresTests: XCTestCase {

    /// Stands in for `FinchStore.displayMoneyBase`: signed, no currency noise.
    private func money(_ v: Double) -> String {
        (v < 0 ? "\u{2212}" : "+") + String(format: "%.2f", abs(v))
    }

    private func texts(net: Double, income: Double, expense: Double) -> [String] {
        MonthHeaderFigures.make(net: net, income: income, expense: expense, money: money).map(\.text)
    }

    func test_incomeReadsAsAnInflowAndSpendingAsAnOutflow() {
        // The case the words used to carry: both arrive positive, and only the sign
        // now says which is which.
        XCTAssertEqual(texts(net: -1234.56, income: 8964.99, expense: 3999.12),
                       ["\u{2212}1234.56", "+8964.99", "\u{2212}3999.12"])
    }

    func test_rolesComeBackInAFixedOrder() {
        let roles = MonthHeaderFigures.make(net: 0, income: 0, expense: 0, money: money).map(\.role)
        XCTAssertEqual(roles, [.net, .income, .expense])
    }

    func test_aMonthUpOverallShowsAPlusOnTheNet() {
        XCTAssertEqual(texts(net: 4965.87, income: 8964.99, expense: 3999.12).first, "+4965.87")
    }

    // Negating a plain 0 gives -0.0, which would print as "−0.00" — a month with no
    // spending reading as though money left.
    func test_aMonthWithNoSpendingDoesNotShowNegativeZero() {
        XCTAssertEqual(texts(net: 500, income: 500, expense: 0).last, "+0.00")
    }

    func test_aMonthWithNoIncomeStillReadsAsAnInflowSlot() {
        XCTAssertEqual(texts(net: -300, income: 0, expense: 300)[1], "+0.00")
    }

    // Privacy masks every amount to the same dots. The formatter is what masks, so the
    // figures must not staple a sign on afterwards — that would newly reveal whether
    // the month was up or down, which the header has never shown.
    func test_underPrivacyNoSignLeaksThroughTheMask() {
        let masked = MonthHeaderFigures.make(net: -1234.56, income: 8964.99, expense: 3999.12,
                                             money: { _ in "\u{2022}\u{2022}\u{2022}\u{2022}" })
        XCTAssertEqual(masked.map(\.text), ["••••", "••••", "••••"])
    }
}
