import XCTest
import GRDB
@testable import FinchApp
import FinchCore

/// The simulator demo is a user who keeps up with their bills.
///
/// A scheduled row reads "overdue <date>" in red while an occurrence nobody posted
/// is behind d.today (#819). The seed started every template two months back and
/// posted none of them, so every item in the demo's Scheduled tab read overdue —
/// a broken-looking tab, and a user nobody is. The seed now posts each past
/// occurrence through `postScheduled`, linked to its template, and leaves one
/// bill (the one that fell due most recently) unpaid so the overdue state is
/// still there to look at. Through the real seed and engine, against the wall
/// clock the seed itself dates from.
final class DemoSeedScheduledTests: XCTestCase {

    private struct Demo { let txns: [Tx]; let templates: [ScheduledTemplate]; let today: String }

    @MainActor
    private func seeded() throws -> Demo {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try SimulatorDemoSeed.seed(q)
        return Demo(txns: try Projection.run(dbQueue: q, ledgerId: "personal"),
                    templates: try Projection.scheduledTemplates(dbQueue: q, ledgerId: "personal"),
                    today: FinchStore.isoDay(Date()))
    }

    @MainActor
    func test_exactlyOneScheduledItemIsOverdue() throws {
        let d = try seeded()
        let posted = Selectors.scheduledPostedMap(d.txns)
        let overdue = d.templates.filter { ScheduledCaption.due($0, posted: posted, today: d.today)?.overdue == true }
        XCTAssertEqual(overdue.count, 1, "overdue: \(overdue.map(\.name))")
        XCTAssertEqual(overdue.first?.type, "expense", "the unpaid one is a bill, not the salary or the transfer")
    }

    /// The seed's own transactions already carried the rent, the salary, Netflix,
    /// PG&E, Spotify and an Everyday → Savings transfer. Posting the templates on
    /// top would have counted each of those twice, so every row that IS one of
    /// those bills must be a template's posting.
    @MainActor
    func test_noBillIsRecordedTwice() throws {
        let d = try seeded()
        let names = Set(d.templates.map(\.name))
        let unlinked = d.txns.filter { names.contains($0.merchant) && $0.sourceTemplateId == nil }
        XCTAssertEqual(unlinked.map { "\($0.merchant) \($0.date)" }, [],
                       "a seeded row duplicates a scheduled bill")
        let transfers = d.txns.filter { $0.kind == "transfer" && $0.account == "savings" }
        XCTAssertFalse(transfers.isEmpty)
        XCTAssertTrue(transfers.allSatisfy { $0.sourceTemplateId != nil },
                      "the Everyday → Savings transfer is the template's, not a second one")
    }

    /// Posted the way a real Post posts: confirmed, dated on the occurrence it
    /// fulfils, nothing in the future.
    @MainActor
    func test_postingsLookLikeAUsersPosts() throws {
        let d = try seeded()
        let linked = d.txns.filter { $0.sourceTemplateId != nil }
        XCTAssertFalse(linked.isEmpty)
        for t in linked {
            XCTAssertNotEqual(t.pending, true, "\(t.merchant) \(t.date) was left to confirm")
            XCTAssertEqual(t.occurrenceDate, t.date, "\(t.merchant) is dated off its occurrence")
            XCTAssertLessThan(t.date, d.today, "\(t.merchant) was posted ahead of its day")
        }
    }
}
