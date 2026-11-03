import XCTest
@testable import FinchApp

/// `AppDate.shortDay` — the one style the scheduled captions, skip titles, rate
/// dates and the forecast print a day in. They used to mix "2026-10-18", "Nov 25"
/// and "18 Oct 2026" on neighbouring screens.
///
/// Locales are pinned here, so these hold on any simulator language or region.
final class ShortDayTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private let zh = Locale(identifier: "zh-Hans_CN")

    func test_monthAndDay_withTheYearOnlyOutsideTodaysYear() {
        XCTAssertEqual(AppDate.shortDay("2026-04-15", today: "2026-04-01", locale: en), "Apr 15")
        XCTAssertEqual(AppDate.shortDay("2025-12-15", today: "2026-04-01", locale: en), "Dec 15, 2025")
        XCTAssertEqual(AppDate.shortDay("2027-01-05", today: "2026-12-20", locale: en), "Jan 5, 2027")
    }

    func test_followsTheLanguage() {
        XCTAssertEqual(AppDate.shortDay("2026-04-15", today: "2026-04-01", locale: zh), "4月15日")
        XCTAssertEqual(AppDate.shortDay("2025-12-15", today: "2026-04-01", locale: zh), "2025年12月15日")
    }

    /// The stored days are Gregorian, and the year shown must be the one compared
    /// with `today`: 2025, not 2568 or Reiwa 7. What a Buddhist or Japanese region
    /// really changes is the DEVICE calendar (`Calendar.current`, the format style's
    /// default), which a test process can't switch — `shortDay` passes
    /// `AppDate.civil` instead of relying on that default. This pins the locale half.
    func test_aNonGregorianLocale_stillReadsTheGregorianYear() {
        for id in ["en_US@calendar=buddhist", "th_TH", "ja_JP@calendar=japanese"] {
            let s = AppDate.shortDay("2025-12-15", today: "2026-04-01", locale: Locale(identifier: id))
            XCTAssertTrue(s.contains("2025"), "\(id): \(s)")
            XCTAssertFalse(s.contains("2568") || s.contains("令和"), "\(id): \(s)")
        }
    }

    func test_notADay_isShownAsIs() {
        XCTAssertEqual(AppDate.shortDay("—", today: "2026-04-01", locale: en), "—")
        XCTAssertEqual(AppDate.shortDay("garbage", withYear: true, locale: en), "garbage")
    }
}
