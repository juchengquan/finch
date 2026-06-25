import XCTest
@testable import FinchCore

final class ScheduledCalendarTests: XCTestCase {
    private func tmpl(_ id: String, freq: String, start: String, end: String? = nil, dom: Int = 1) -> ScheduledTemplate {
        ScheduledTemplate(id: id, name: id, type: "expense", amount: 10, frequency: freq, dayOfMonth: dom,
                          accountId: "a1", startDate: start, endDate: end, nextRun: start)
    }

    func test_occurrencesInRange_monthly() {
        let t = tmpl("m", freq: "monthly", start: "2026-01-15", dom: 15)
        let occ = Selectors.occurrencesInRange([t], from: "2026-03-01", through: "2026-05-31").map(\.date)
        XCTAssertEqual(occ, ["2026-03-15", "2026-04-15", "2026-05-15"])
    }

    func test_occurrencesInRange_weekly_count_in_month() {
        let t = tmpl("w", freq: "weekly", start: "2026-06-01")   // Mondays-ish weekly from Jun 1
        let occ = Selectors.occurrencesInRange([t], from: "2026-06-01", through: "2026-06-30").map(\.date)
        XCTAssertEqual(occ, ["2026-06-01", "2026-06-08", "2026-06-15", "2026-06-22", "2026-06-29"])
    }

    func test_occurrencesInRange_once_and_bounds() {
        let once = tmpl("o", freq: "once", start: "2026-06-10")
        XCTAssertEqual(Selectors.occurrencesInRange([once], from: "2026-06-01", through: "2026-06-30").map(\.date), ["2026-06-10"])
        XCTAssertTrue(Selectors.occurrencesInRange([once], from: "2026-07-01", through: "2026-07-31").isEmpty)   // out of range
        let ended = tmpl("e", freq: "monthly", start: "2026-01-10", end: "2026-02-28", dom: 10)
        XCTAssertEqual(Selectors.occurrencesInRange([ended], from: "2026-01-01", through: "2026-06-30").map(\.date), ["2026-01-10", "2026-02-10"])   // respects endDate
    }

    func test_occurrencesInRange_sorted_across_templates() {
        let a = tmpl("a", freq: "monthly", start: "2026-06-20", dom: 20)
        let b = tmpl("b", freq: "monthly", start: "2026-06-05", dom: 5)
        XCTAssertEqual(Selectors.occurrencesInRange([a, b], from: "2026-06-01", through: "2026-06-30").map(\.date), ["2026-06-05", "2026-06-20"])
    }

    func test_scheduledPostedMap() {
        let txns = [
            Tx(id: "t1", merchant: "x", amount: -10, account: "a1", date: "2026-06-05", pending: false, sourceTemplateId: "b"), // done
            Tx(id: "t2", merchant: "x", amount: -10, account: "a1", date: "2026-06-20", pending: true,  sourceTemplateId: "a"), // pending
            Tx(id: "t3", merchant: "x", amount: -10, account: "a1", date: "2026-06-01"),                                        // no template
        ]
        let m = Selectors.scheduledPostedMap(txns)
        XCTAssertEqual(m["b|2026-06-05"], false)
        XCTAssertEqual(m["a|2026-06-20"], true)
        XCTAssertNil(m["x|2026-06-01"])
    }
}
