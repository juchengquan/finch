import Foundation
@testable import FinchApp

/// For tests where the store reads the wall clock on its own (`wallToday`, the
/// auto-post run, Confirm now) and the test reads it again to check the result. Two
/// reads either side of local midnight are a day apart, and the test then fails for
/// a reason that has nothing to do with what it checks. The store has no clock to
/// inject, so a test that starts in the last `margin` seconds of the day waits for
/// the next one instead: at most once a day, and never more than `margin`.
enum MidnightGuard {
    static func waitIfClose(margin: TimeInterval = 60) async throws {
        let cal = AppDate.civil
        let now = Date()
        guard let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return }
        let left = midnight.timeIntervalSince(now)
        if left < margin { try await Task.sleep(for: .seconds(left + 1)) }
    }
}
