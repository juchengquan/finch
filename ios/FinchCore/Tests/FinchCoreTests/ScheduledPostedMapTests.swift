import XCTest
@testable import FinchCore

final class ScheduledPostedMapTests: XCTestCase {
    /// `Tx` has a wide memberwise init; every parameter not named here is defaulted.
    /// Adapted to the real initializer (`merchant`/`account`, not the brief's
    /// illustrative `description`/`accountId`) — see `ScheduledCalendarTests`'s
    /// sibling helper for the same convention.
    private func tx(_ id: String, date: String, occurrence: String?, template: String?) -> Tx {
        Tx(id: id, merchant: "Gym", amount: -40, account: "a1", date: date,
           sourceTemplateId: template, occurrenceDate: occurrence)
    }

    /// The bug: a transaction dated later must resolve the occurrence it fulfils.
    func test_prefersOccurrenceDateOverTransactionDate() {
        let map = Selectors.scheduledPostedMap([tx("e1", date: "2026-07-21", occurrence: "2026-07-15", template: "gym")])
        XCTAssertNotNil(map["gym|2026-07-15"])
        XCTAssertNil(map["gym|2026-07-21"])
    }

    /// No backfill: historical rows have NULL and must behave exactly as before.
    func test_fallsBackToTransactionDateWhenNull() {
        let map = Selectors.scheduledPostedMap([tx("e1", date: "2026-07-15", occurrence: nil, template: "gym")])
        XCTAssertNotNil(map["gym|2026-07-15"])
    }

    func test_ignoresTransactionsWithNoTemplate() {
        XCTAssertTrue(Selectors.scheduledPostedMap([tx("e1", date: "2026-07-15", occurrence: nil, template: nil)]).isEmpty)
    }
}
