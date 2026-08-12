import Foundation

/// The hours during which an alert must not interrupt.
///
/// `endHour` may be EARLIER than `startHour` — 22→08 is the default and crosses
/// midnight. Every rule below is written for that case first, because it is the normal
/// one and the naive implementation only handles the other.
public struct QuietHours: Equatable, Sendable {
    public let startHour: Int
    public let endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }

    public static let `default` = QuietHours(startHour: 22, endHour: 8)

    /// Does this window wrap past midnight? 22→08 does; 01→06 does not.
    public var crossesMidnight: Bool { startHour > endHour }
}

/// WHEN an alert may be delivered, and HOW MANY may arrive at once.
///
/// Separate from `NotificationPlanner`, which decides WHAT is true, and from
/// `NotificationService`, which talks to `UNUserNotificationCenter`. This type is pure:
/// **no clock reads and no notification-centre calls**, so `now` is always a parameter.
/// That is the only reason its rules can be tested at all — the interesting cases are
/// specific instants (23:30 on a Tuesday), and a type that read `Date()` could not
/// express them.
public enum NotificationPolicy {

    /// The moment this alert is allowed to reach the user.
    ///
    /// Outside quiet hours this is `now` — a budget you blow at 2pm still tells you at
    /// 2pm. Inside them it is the next end-of-window, so the alert is HELD, never
    /// dropped: nothing is lost, it just waits until a civil hour.
    ///
    /// Boundaries: `startHour` is quiet (an alert at exactly 22:00 waits), `endHour` is
    /// not (an alert at exactly 08:00 goes now). Stated explicitly because `<` vs `<=`
    /// here is the difference between "held for eight hours" and "delivered instantly",
    /// and neither is obviously wrong from the call site.
    public static func deliveryTime(raisedAt now: Date,
                                    quiet: QuietHours,
                                    calendar: Calendar = .current) -> Date {
        guard isQuiet(now, quiet, calendar) else { return now }
        return nextEnd(after: now, quiet, calendar)
    }

    /// Is this instant inside the window?
    static func isQuiet(_ now: Date, _ quiet: QuietHours, _ calendar: Calendar) -> Bool {
        let h = calendar.component(.hour, from: now)
        if quiet.crossesMidnight {
            // 22→08: quiet if at/after 22 OR before 08.
            return h >= quiet.startHour || h < quiet.endHour
        }
        // 01→06: quiet only between them.
        return h >= quiet.startHour && h < quiet.endHour
    }

    /// The next occurrence of `endHour` strictly after `now`.
    ///
    /// Raised at 02:14 with a 22→08 window, this is 08:00 the SAME day. Raised at 23:30
    /// it is 08:00 the NEXT day — the case a naive "set the hour and keep the date"
    /// implementation gets wrong, because the end hour has already passed today.
    static func nextEnd(after now: Date, _ quiet: QuietHours, _ calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = quiet.endHour
        comps.minute = 0
        comps.second = 0
        guard let sameDay = calendar.date(from: comps) else { return now }
        if sameDay > now { return sameDay }
        return calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay
    }

    /// The nearest allowed HOUR to the one asked for — the hour-only counterpart of
    /// `deliveryTime`, for a REPEATING trigger where there is no single instant to hold,
    /// only an hour that must be a permitted one. Used by the weekly digest.
    public static func allowedHour(_ hour: Int, quiet: QuietHours) -> Int {
        let isQuiet = quiet.crossesMidnight
            ? (hour >= quiet.startHour || hour < quiet.endHour)
            : (hour >= quiet.startHour && hour < quiet.endHour)
        return isQuiet ? quiet.endHour : hour
    }

    /// Send at most `cap`, and collapse the remainder into one summary.
    ///
    /// A statement import can make many alerts true at once — anomaly scoring runs over
    /// the 50 most recent purchases — and without this they all arrive seconds apart.
    /// The overflow is summarised rather than discarded, so nothing is silently lost.
    ///
    /// At or under the cap, `summary` is never called and the input is returned
    /// unchanged — a lone alert must not become "1 notification" plus a summary of none.
    public static func applyCap(_ planned: [PlannedNotification],
                                cap: Int,
                                summary: (Int) -> PlannedNotification) -> [PlannedNotification] {
        guard cap > 0, planned.count > cap else { return planned }
        return Array(planned.prefix(cap)) + [summary(planned.count - cap)]
    }
}
