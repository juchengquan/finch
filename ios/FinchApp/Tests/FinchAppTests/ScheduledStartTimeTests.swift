import XCTest
@testable import FinchApp

/// A template with no start time posts each occurrence at the moment it fires.
/// Editing it stamped 00:00, after which every occurrence posted at midnight.
final class ScheduledStartTimeTests: XCTestCase {

    private func at(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: h, minute: m))!
    }

    func test_anEditKeepsAnUntimedTemplateUntimed() {
        XCTAssertNil(ScheduledSheet.editedStartTime(stored: nil, picked: at(0, 0)), "untouched: leave it unset")
        XCTAssertNil(ScheduledSheet.editedStartTime(stored: "", picked: at(0, 0)))
        XCTAssertEqual(ScheduledSheet.editedStartTime(stored: nil, picked: at(9, 30)), "09:30", "a time the user picked")
        XCTAssertEqual(ScheduledSheet.editedStartTime(stored: "08:00", picked: at(0, 0)), "00:00", "a time moved to midnight")
        XCTAssertEqual(ScheduledSheet.editedStartTime(stored: "08:00", picked: at(8, 0)), "08:00")
    }
}
