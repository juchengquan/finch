import XCTest
@testable import FinchApp
import FinchCore

final class MonthGroupingTests: XCTestCase {
    private func tx(_ id: String, _ date: String, amount: Double = -10) -> Tx {
        Tx(id: id, merchant: "m", amount: amount, account: "a", date: date)
    }

    func test_sections_groupByMonth_preservingOrder() {
        // date-descending input across two months
        let input = [tx("1", "2026-09-20"), tx("2", "2026-09-05"), tx("3", "2026-08-31")]
        let s = MonthGrouping.sections(input)
        XCTAssertEqual(s.map(\.id), ["2026-09", "2026-08"])        // newest month first, order preserved
        XCTAssertEqual(s[0].txns.map(\.id), ["1", "2"])
        XCTAssertEqual(s[1].txns.map(\.id), ["3"])
    }

    func test_sections_interleavedMonths_firstOccurrenceOrder_andAppends() {
        // interleaved input: a wrong "sort section keys descending" impl would still
        // pass the date-monotonic test above, but would fail this one.
        let input = [tx("1", "2026-09-20"), tx("2", "2026-08-15"),
                     tx("3", "2026-09-05"), tx("4", "2026-07-30")]
        let s = MonthGrouping.sections(input)
        XCTAssertEqual(s.map(\.id), ["2026-09", "2026-08", "2026-07"])   // first-occurrence order, not sorted
        XCTAssertEqual(s[0].txns.map(\.id), ["1", "3"])                  // both Sep txns, appended in order
    }

    func test_sections_singleMonth_oneSection() {
        let s = MonthGrouping.sections([tx("1", "2026-09-20"), tx("2", "2026-09-01")])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].id, "2026-09")
    }

    func test_sections_empty_isEmpty() {
        XCTAssertTrue(MonthGrouping.sections([]).isEmpty)
    }

    func test_dailyIncomeExpense_splitsBySign_perDay() {
        let d = MonthGrouping.dailyIncomeExpense([
            tx("1", "2026-09-20", amount: -42.18),
            tx("2", "2026-09-20", amount: 4_200),
            tx("3", "2026-09-20", amount: -10),
            tx("4", "2026-09-05", amount: -53.20),
        ])
        XCTAssertEqual(d["2026-09-20"]?.income, 4_200)
        XCTAssertEqual(d["2026-09-20"]?.expense ?? 0, 52.18, accuracy: 0.001)
        XCTAssertEqual(d["2026-09-05"]?.income, 0)
        XCTAssertEqual(d["2026-09-05"]?.expense ?? 0, 53.20, accuracy: 0.001)
        XCTAssertNil(d["2026-09-01"])           // no txns → absent, not zero
    }

    func test_label_wideMonthAndYear() {
        // en locale renders the wide month + year; assert the year is present and it isn't the raw key
        let out = MonthGrouping.label("2026-09")
        XCTAssertTrue(out.contains("2026"))
        XCTAssertNotEqual(out, "2026-09")
    }

    func test_label_malformedKey_returnsKey() {
        XCTAssertEqual(MonthGrouping.label("not-a-date"), "not-a-date")
    }

    func test_net_sumsSignedBaseAmounts() {
        let s = MonthGrouping.net([tx("1", "2026-09-01", amount: -54.20),
                                   tx("2", "2026-09-02", amount: 3200)])
        XCTAssertEqual(s, 3145.80, accuracy: 0.001)
    }

    func test_net_empty_isZero() {
        XCTAssertEqual(MonthGrouping.net([]), 0)
    }

    func test_incomeAndExpense_splitBySign_identityWithNet() {
        let txns = [tx("1", "2026-09-01", amount: -54.20),
                    tx("2", "2026-09-02", amount: 3200),
                    tx("3", "2026-09-03", amount: -145.80),
                    tx("4", "2026-09-04", amount: 500)]
        XCTAssertEqual(MonthGrouping.income(txns), 3700, accuracy: 0.001)
        XCTAssertEqual(MonthGrouping.expense(txns), 200, accuracy: 0.001)   // positive magnitude
        XCTAssertEqual(MonthGrouping.income(txns) - MonthGrouping.expense(txns),
                       MonthGrouping.net(txns), accuracy: 0.001)            // in − out == net
    }

    func test_incomeAndExpense_empty_areZero() {
        XCTAssertEqual(MonthGrouping.income([]), 0)
        XCTAssertEqual(MonthGrouping.expense([]), 0)
    }
}
