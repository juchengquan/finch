import XCTest
@testable import FinchApp

/// The Insights spending heatmap's per-cell VoiceOver text.
///
/// The cells are bare coloured squares, so this label is the only thing a screen
/// reader has to go on — and it used to interpolate the raw `Double` straight
/// into a `LocalizedStringKey`, which renders through the `%lf` specifier. With
/// amounts masked on screen, VoiceOver still spoke "2026-07-15: 1850.000000":
/// unconverted, unformatted, unmasked. Nothing on screen shows it, so only a
/// test can hold this shut.
final class CalendarHeatmapLabelTests: XCTestCase {
    private let mask: (Double) -> String = { _ in FinchStore.moneyMask }

    func test_masked_speaksTheMaskNotTheFigure() {
        XCTAssertEqual(CalendarHeatmap.cellLabel(date: "2026-07-15", value: 1850, format: mask),
                       "2026-07-15: \(FinchStore.moneyMask)")
    }

    func test_masked_neverLeaksTheDigitsOrTheOldFloatFormat() {
        let s = CalendarHeatmap.cellLabel(date: "2026-07-15", value: 1850, format: mask)
        XCTAssertFalse(s.contains("1850"))
        XCTAssertFalse(s.contains(".000000"))   // the old "%lf" rendering
    }

    // Whatever the caller's formatter returns is what gets spoken — the view
    // holds no formatting policy of its own.
    func test_unmasked_usesTheCallersFormatting() {
        XCTAssertEqual(CalendarHeatmap.cellLabel(date: "2026-07-15", value: 1850) { "$\(Int($0))" },
                       "2026-07-15: $1850")
    }

    func test_zeroDayStillCarriesItsDate() {
        let s = CalendarHeatmap.cellLabel(date: "2026-07-16", value: 0, format: mask)
        XCTAssertTrue(s.hasPrefix("2026-07-16: "))
    }
}
