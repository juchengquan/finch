import XCTest
@testable import FinchCore

final class DetectRecurringTests: XCTestCase {
    private func exp(_ id: String, _ merchant: String, _ amount: Double, _ date: String,
                    tmpl: String? = nil, acct: String = "a1", cat: String? = "food") -> Tx {
        Tx(id: id, merchant: merchant, category: cat, amount: amount, account: acct, date: date,
           pending: false, ledgerId: "l1", kind: "expense", sourceTemplateId: tmpl)
    }

    func test_detectsMonthlySubscription() {
        let txns = [
            exp("1", "Netflix", -15.99, "2026-03-03"),
            exp("2", "Netflix", -15.99, "2026-04-03"),
            exp("3", "Netflix", -15.99, "2026-05-03"),
            exp("4", "Netflix", -15.99, "2026-06-03"),
            // one-off noise — must NOT be detected
            exp("5", "Random Shop", -42.10, "2026-05-10"),
        ]
        let out = Selectors.detectRecurring(txns, "l1", "2026-06-20")
        XCTAssertEqual(out.count, 1)
        let r = out[0]
        XCTAssertEqual(r.merchantName, "Netflix")
        XCTAssertEqual(r.cadence, "monthly")
        XCTAssertEqual(r.occurrences, 4)
        XCTAssertEqual(r.averageAmount, 15.99, accuracy: 0.01)
        XCTAssertEqual(r.monthlyEstimate, 15.99, accuracy: 0.01)
        XCTAssertFalse(r.isScheduled)
    }

    func test_irregularGaps_notDetected() {
        let txns = [
            exp("1", "Cafe", -5, "2026-06-01"),
            exp("2", "Cafe", -5, "2026-06-02"),
            exp("3", "Cafe", -5, "2026-06-19"),
        ]
        XCTAssertTrue(Selectors.detectRecurring(txns, "l1", "2026-06-20").isEmpty)
    }

    func test_stale_droppedByActiveFilter() {
        let txns = [
            exp("1", "OldGym", -20, "2025-01-05"),
            exp("2", "OldGym", -20, "2025-02-05"),
            exp("3", "OldGym", -20, "2025-03-05"),
        ]
        XCTAssertTrue(Selectors.detectRecurring(txns, "l1", "2026-06-20").isEmpty)
    }

    func test_isScheduled_whenSourcedFromTemplate() {
        let txns = [
            exp("1", "Rent", -1000, "2026-04-01", tmpl: "tmpl-rent"),
            exp("2", "Rent", -1000, "2026-05-01", tmpl: "tmpl-rent"),
            exp("3", "Rent", -1000, "2026-06-01", tmpl: "tmpl-rent"),
        ]
        let out = Selectors.detectRecurring(txns, "l1", "2026-06-20")
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].isScheduled)
    }

    func test_carriesModalAccountAndCategory() {
        let txns = [
            exp("1", "Netflix", -15.99, "2026-03-03", acct: "a1", cat: "ent"),
            exp("2", "Netflix", -15.99, "2026-04-03", acct: "a1", cat: "ent"),
            exp("3", "Netflix", -15.99, "2026-05-03", acct: "a2", cat: "ent"),
            exp("4", "Netflix", -15.99, "2026-06-03", acct: "a1", cat: "ent"),
        ]
        let r = Selectors.detectRecurring(txns, "l1", "2026-06-20")[0]
        XCTAssertEqual(r.accountId, "a1")   // modal
        XCTAssertEqual(r.categoryId, "ent")
    }

    func test_isScheduled_whenTemplateNameMatchesMerchant() {
        let txns = [
            exp("1", "Spotify", -11.99, "2026-03-03"),
            exp("2", "Spotify", -11.99, "2026-04-03"),
            exp("3", "Spotify", -11.99, "2026-05-03"),
            exp("4", "Spotify", -11.99, "2026-06-03"),
        ]
        let tmpl = ScheduledTemplate(id: "t1", name: "Spotify", description: nil, type: "expense",
            amount: 11.99, frequency: "monthly", dayOfMonth: 3, weekDay: nil, accountId: "a1",
            fromAccountId: nil, categoryId: nil, startDate: "2026-03-03", endDate: nil,
            nextRun: "2026-07-03", maxExecutions: nil, installmentTotal: nil, installmentPaid: nil, color: nil)
        let out = Selectors.detectRecurring(txns, "l1", "2026-06-20", [tmpl])
        XCTAssertTrue(out[0].isScheduled)
    }
}
