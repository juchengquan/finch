import XCTest
@testable import FinchCore

/// Task 8 of the "Post now" entry-points follow-up: the selector that picks
/// which occurrence a bare "Post now" (no occurrence already in hand) should
/// act on. Contract: catch up oldest-first (same order `generateDue` uses),
/// then fall forward to the next occurrence at or after `today` once nothing
/// is missed.
final class ResumeOccurrenceTests: XCTestCase {
    /// Anchored so the only occurrence before "2026-07-21" is 2026-07-08 —
    /// isolates the "oldest missed" case from the "nothing missed" case
    /// across the three tests below. Same initialiser convention as
    /// `ScheduledCalendarTests`'s `tmpl` helper.
    private let monthly8th = ScheduledTemplate(id: "gym", name: "Gym", type: "expense", amount: 40,
                                               frequency: "monthly", dayOfMonth: 8, accountId: "a1",
                                               startDate: "2026-07-08", nextRun: "2026-07-08")

    func test_picksOldestUnresolvedFirst() {
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly8th, posted: [:], today: "2026-07-21"),
                       "2026-07-08")
    }

    func test_skipsResolvedOccurrences() {
        let posted = ["gym|2026-07-08": false]
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly8th, posted: posted, today: "2026-07-21"),
                       "2026-08-08")
    }

    func test_fallsForwardWhenNothingIsMissed() {
        let posted = ["gym|2026-07-08": false, "gym|2026-06-08": false]
        let r = Selectors.resumeOccurrence(template: monthly8th, posted: posted, today: "2026-07-21")
        XCTAssertEqual(r, "2026-08-08")
        XCTAssertTrue(r! >= "2026-07-21")
    }
}
