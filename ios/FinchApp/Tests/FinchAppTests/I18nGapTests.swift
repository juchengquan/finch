import XCTest
import FinchCore
@testable import FinchApp

/// Text that read in English on a Chinese phone although every catalog check was
/// green: labels returned as plain `String`s (never extracted), fixed English date
/// formats and month lists, and plurals built by appending "s".
@MainActor
final class I18nGapTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private let zh = Locale(identifier: "zh-Hans_CN")

    /// The built app's Chinese table. A key that is missing, or was never
    /// extracted, comes back as nil.
    private func chinese(_ key: String) throws -> String? {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let missing = "\u{1}missing"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : value
    }

    // MARK: Labels

    func test_everyRelabelledVocabularyHasChinese() throws {
        var labels: [String] = []
        labels += TxSort.allCases.map(\.label)
        labels += ["is", "contains", "startsWith", "gt", "lt", "eq", "between", "is_null",
                   "has", "in", "has_any", "has_all"].map(opLabel)
        labels += [LeafForm.Field.merchant, .note, .amount, .kind, .categoryId, .accountId,
                   .counterpartyId, .currency, .tagId, .dateDom, .dateDow].map(fieldLabel)
        labels += RuleSheet.ActType.allCases.map(\.label)
        labels += ["cash", "savings", "credit_card", "investment", "fx", "virtual"].map(AccountTypeLabel.label)
        for label in labels {
            XCTAssertNotNil(try chinese(label), "\"\(label)\" has no Chinese")
        }
    }

    func test_weekdayChipsFollowTheLanguage() {
        XCTAssertEqual(weekdayChipLabels(locale: en), ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(weekdayChipLabels(locale: zh), ["日", "一", "二", "三", "四", "五", "六"])
    }

    // MARK: Plurals

    func test_theBudgetCountdownSaysOneDayNotOneDays() {
        XCTAssertEqual(FinchStore.CycleRemaining.days(1).caption, " · 1 day left")
        XCTAssertEqual(FinchStore.CycleRemaining.days(3).caption, " · 3 days left")
        XCTAssertEqual(FinchStore.CycleRemaining.hours(1).caption, " · 1 hour left")
        XCTAssertEqual(FinchStore.CycleRemaining.hours(7).caption, " · 7 hours left")
        XCTAssertNil(FinchStore.CycleRemaining.ended.caption)
    }

    /// The counted phrases have Chinese, and none carries the old "s" placeholder:
    /// "基于最近 3 个月%2$@" rendered as "基于最近 3 个月s".
    func test_countedPhrasesHaveChineseWithoutAnEnglishSuffix() throws {
        for key in [" · 1 day left", " · %lld days left", " · 1 hour left", " · %lld hours left",
                    "1 day left", "%lld days left",
                    "Based on your last month", "Based on your last %lld months",
                    "Applies to 1 selected transaction.", "Applies to %lld selected transactions.",
                    "Delete 1 transaction?", "Delete %lld transactions?",
                    "Marked 1 transaction as cleared.", "Marked %lld transactions as cleared."] {
            let zh = try XCTUnwrap(try chinese(key), "\"\(key)\" has no Chinese")
            XCTAssertFalse(zh.contains("%2$@") || zh.contains("%@"), "\"\(key)\" → \(zh)")
        }
    }

    // MARK: Dates

    func test_theCalendarHeadlineFollowsTheLanguage() {
        XCTAssertEqual(AppDate.weekdayDay("2026-07-15", locale: en), "Wed, Jul 15")
        let zhDay = AppDate.weekdayDay("2026-07-15", locale: zh)
        XCTAssertTrue(zhDay.hasPrefix("7月15日"), zhDay)
        XCTAssertTrue(zhDay.contains("周三"), zhDay)
    }

    func test_monthNamesFollowTheLanguage() {
        XCTAssertEqual(AppDate.monthYear("2026-07", wide: true, locale: en), "July 2026")
        XCTAssertEqual(AppDate.monthYear("2026-07", locale: en), "Jul 2026")
        XCTAssertEqual(AppDate.monthYear("2026-07", wide: true, locale: zh), "2026年7月")
        XCTAssertEqual(AppDate.monthName(7, locale: en), "Jul")
        XCTAssertEqual(AppDate.monthName(7, locale: zh), "7月")
        XCTAssertEqual(AppDate.chartMonth("Dec", locale: zh), "12月")
        XCTAssertEqual(AppDate.monthYear("garbage", locale: en), "garbage")
    }

    /// The year is the stored Gregorian one, as `shortDay` keeps it.
    func test_aNonGregorianLocale_stillReadsTheGregorianYear() {
        let s = AppDate.monthYear("2025-12", wide: true, locale: Locale(identifier: "th_TH"))
        XCTAssertTrue(s.contains("2025"), s)
    }

    /// Unique across the chart's bars, and in the reader's language.
    func test_budgetCycleLabels() {
        XCTAssertEqual(AppDate.budgetCycleLabel("2026-07-01", frequency: "monthly", locale: en), "Jul")
        XCTAssertEqual(AppDate.budgetCycleLabel("2026-07-01", frequency: "monthly", locale: zh), "7月")
        XCTAssertEqual(AppDate.budgetCycleLabel("2026-01-01", frequency: "yearly", locale: en), "Jan 2026")
        XCTAssertNotEqual(AppDate.budgetCycleLabel("2026-01-01", frequency: "yearly", locale: en),
                          AppDate.budgetCycleLabel("2027-01-01", frequency: "yearly", locale: en))
        XCTAssertEqual(AppDate.budgetCycleLabel("2026-07-15", frequency: "weekly", locale: en), "7/15")
    }
}
