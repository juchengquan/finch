import XCTest
@testable import FinchApp

/// The Insights heatmap's cell shading.
///
/// Unmasked, opacity scales with the day's spend relative to the biggest day —
/// which means the opacity *is* the amount, normalized. That ranked the whole
/// 12 weeks on screen while every figure read "••••", so a glance picked out
/// payday and rent day. Masked, every spending day must look identical.
final class CalendarHeatmapIntensityTests: XCTestCase {

    // The load-bearing one: magnitude must not survive the mask.
    func test_masked_everySpendingDayLooksIdentical() {
        let small = CalendarHeatmap.intensity(0.01, maxValue: 10_000, masked: true)
        let mid = CalendarHeatmap.intensity(500, maxValue: 10_000, masked: true)
        let biggest = CalendarHeatmap.intensity(10_000, maxValue: 10_000, masked: true)
        XCTAssertEqual(small, mid)
        XCTAssertEqual(mid, biggest)
    }

    // …but "did I spend that day?" still reads, like the calendar's presence dots.
    func test_masked_spendingIsStillDistinguishableFromAQuietDay() {
        let spent = CalendarHeatmap.intensity(42, maxValue: 10_000, masked: true)
        let quiet = CalendarHeatmap.intensity(0, maxValue: 10_000, masked: true)
        XCTAssertGreaterThan(spent - quiet, 0.3,
                             "a masked spending day must be plainly visible against an empty one")
    }

    func test_unmasked_scalesWithTheAmount() {
        let small = CalendarHeatmap.intensity(1_000, maxValue: 10_000, masked: false)
        let big = CalendarHeatmap.intensity(9_000, maxValue: 10_000, masked: false)
        XCTAssertLessThan(small, big)
        XCTAssertEqual(CalendarHeatmap.intensity(10_000, maxValue: 10_000, masked: false), 1.0,
                       accuracy: 0.0001)   // 0.15 + 0.85 × 1
    }

    // Unmasked behaviour is unchanged from before the privacy work: the two
    // degenerate branches of the original `guard maxValue > 0, v > 0`.
    func test_unmasked_degenerateCases() {
        XCTAssertEqual(CalendarHeatmap.intensity(0, maxValue: 10_000, masked: false), 0.06)
        XCTAssertEqual(CalendarHeatmap.intensity(500, maxValue: 0, masked: false), 0.15)
        XCTAssertEqual(CalendarHeatmap.intensity(0, maxValue: 0, masked: false), 0.06)
    }

    func test_quietDayIsTheSameWhetherMaskedOrNot() {
        XCTAssertEqual(CalendarHeatmap.intensity(0, maxValue: 10_000, masked: true),
                       CalendarHeatmap.intensity(0, maxValue: 10_000, masked: false))
    }
}
