import XCTest
@testable import FinchCore

/// Task 8 of the "Post now" entry-points follow-up: the selector that picks
/// which occurrence a bare "Post now" (no occurrence already in hand) should
/// act on. Contract: catch up oldest-first (same order `generateDue` uses),
/// then fall forward to the next occurrence at or after `today` once nothing
/// is missed.
final class ResumeOccurrenceTests: XCTestCase {
    /// Anchored two months before the tests' "today" (2026-07-21) so THREE
    /// occurrences — 2026-05-08, 2026-06-08, 2026-07-08 — all precede it.
    /// Oldest and newest no longer coincide: a bug that returns the *newest*
    /// unresolved occurrence instead of the oldest is caught by
    /// `test_picksOldestUnresolvedFirst` below. Same initialiser convention as
    /// `ScheduledCalendarTests`'s `tmpl` helper.
    private let monthly8th = ScheduledTemplate(id: "gym", name: "Gym", type: "expense", amount: 40,
                                               frequency: "monthly", dayOfMonth: 8, accountId: "a1",
                                               startDate: "2026-05-08", nextRun: "2026-05-08")

    func test_picksOldestUnresolvedFirst() {
        // None posted: 2026-05-08, 2026-06-08, 2026-07-08 are all missed. Must
        // return the OLDEST (2026-05-08), not the newest (2026-07-08).
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly8th, posted: [:], today: "2026-07-21"),
                       "2026-05-08")
    }

    func test_skipsResolvedOccurrences() {
        // The two oldest are resolved; the earliest still-*unresolved* missed
        // occurrence (2026-07-08) must be picked, not skipped over.
        let posted = ["gym|2026-05-08": false, "gym|2026-06-08": false]
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly8th, posted: posted, today: "2026-07-21"),
                       "2026-07-08")
    }

    func test_fallsForwardWhenNothingIsMissed() {
        // Every past occurrence is resolved, AND "today" itself lands exactly
        // on an occurrence (2026-08-08) that is unposted. The boundary must be
        // `>= today` — a bug using `> today` would skip today's own occurrence
        // and return 2026-09-08 instead.
        let posted = ["gym|2026-05-08": false, "gym|2026-06-08": false, "gym|2026-07-08": false]
        let r = Selectors.resumeOccurrence(template: monthly8th, posted: posted, today: "2026-08-08")
        XCTAssertEqual(r, "2026-08-08")
    }
}
