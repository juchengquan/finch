import Foundation
import FinchCore

/// The 4 local-notification categories (Phase 6.2). Raw values double as the
/// `UNNotificationCategory` identifiers.
public enum NotificationKind: String, CaseIterable, Sendable {
    case scheduledDue, budgetWarning, anomaly, weeklyDigest
    /// String(localized:) — NOT a bare literal. Call sites pass this straight to
    /// `Toggle(_:isOn:)`, and a plain String selects SwiftUI's StringProtocol
    /// overload, which does no lookup: the Settings toggles rendered English in
    /// every language.
    public var title: String {
        switch self {
        case .scheduledDue: return String(localized: "Scheduled reminders")
        case .budgetWarning: return String(localized: "Budget warnings")
        case .anomaly: return String(localized: "Unusual transactions")
        case .weeklyDigest: return String(localized: "Weekly digest")
        }
    }
}

/// A notification the app intends to surface — content built at *plan time* (not
/// fire time), so no chokepoint runs in a background context. `tab`/`focusId`
/// drive the action button + tap routing through `DeepLinkRouter`.
public struct PlannedNotification: Equatable, Identifiable, Sendable {
    public let id: String          // stable → re-planning replaces, doesn't duplicate
    public let kind: NotificationKind
    public let title: String
    public let body: String
    public let tab: AppTab?
    public let focusId: String?
}

/// Pure decision logic: given the projected state, which notifications are
/// warranted right now. Tested in isolation; the UNUserNotificationCenter glue
/// (NotificationService) is a thin shell over this.
public enum NotificationPlanner {
    /// `money` formats a base-currency amount for display (injected so the
    /// planner stays pure/testable). `recentLimit` bounds the anomaly scan to the
    /// most-recent N (txns arrive date-descending).
    ///
    /// TWO dates, deliberately, because they answer different questions:
    /// - `today` is DATA-ANCHORED (`max(tx.date)`) and drives budget windows, so
    ///   a warning matches what the Budgets screen shows.
    /// - `wallToday` is the real calendar day and drives anything asking "is it
    ///   due *now*" — scheduled next-runs and the weekly digest.
    ///
    /// Passing the data-anchored date to the due test was a real bug: `nextRun <=
    /// today` never became true until the user recorded a transaction dated on or
    /// after the due date, so the reminder meant to PROMPT that recording only
    /// arrived once it was already done.
    public static func plan(
        budgets: [BudgetRow], txns: [Tx], scheduled: [ScheduledTemplate],
        categories: [CategoryNode], today: String, wallToday: String, ledgerId: String,
        enabled: Set<NotificationKind>, money: (Double) -> String, recentLimit: Int = 50
    ) -> [PlannedNotification] {
        var out: [PlannedNotification] = []

        if enabled.contains(.budgetWarning) {
            for b in budgets {
                // Budget cycles follow the wall clock, not the data — see FinchStore.budgetToday.
                let p = Selectors.budgetProgress(b, txns, wallToday, categories)
                if Double(p.pct) >= b.warningPct {
                    // Pre-formatted so the localized string carries NO literal `%`.
                    // A bare `%` beside interpolation must round-trip as `%%` through
                    // extraction, and this body was the one notification string still
                    // rendering English on-device while its sibling title localized.
                    let pctText = "\(p.pct)%"
                    out.append(PlannedNotification(
                        id: "budget:\(b.id)", kind: .budgetWarning,
                        title: String(localized: "Budget alert: \(b.name)"),
                        body: String(localized: "\(pctText) used — \(money(p.used)) of \(money(p.base))."),
                        tab: .budgets, focusId: b.id))
                }
            }
        }

        if enabled.contains(.anomaly) {
            let stats = Selectors.merchantStats(txns, ledgerId)
            for t in txns.prefix(recentLimit) {
                guard let a = Selectors.anomalyScore(t, stats), a.isAnomaly else { continue }
                out.append(PlannedNotification(
                    id: "anomaly:\(t.id)", kind: .anomaly,
                    title: String(localized: "Unusual transaction"),
                    body: String(localized: "\(t.merchant) (\(money(t.amount))) looks higher than usual."),
                    tab: .activity, focusId: t.id))
            }
        }

        if enabled.contains(.scheduledDue) {
            for s in scheduled where !s.nextRun.isEmpty && s.nextRun <= wallToday {
                out.append(PlannedNotification(
                    id: "scheduled:\(s.id)", kind: .scheduledDue,
                    title: String(localized: "Scheduled: \(s.name)"),
                    body: String(localized: "\(s.name) is due. Confirm now?"),
                    tab: .scheduled, focusId: s.id))
            }
        }

        if enabled.contains(.weeklyDigest), let d = Selectors.weeklyDigest(txns, ledgerId, wallToday) {
            out.append(PlannedNotification(
                id: "digest:\(d.weekStart)", kind: .weeklyDigest,
                title: String(localized: "Your weekly digest"),
                body: String(localized: "You spent \(money(d.spent)) across \(d.txCount) transactions this week."),
                tab: .insights, focusId: nil))
        }

        return out
    }

    /// Ids currently scheduled or delivered that are no longer planned — a kind was
    /// disabled, a budget fell back under threshold, or a due item was confirmed — so
    /// they should be cancelled.
    public static func cancelIDs(planned: [PlannedNotification], existing: Set<String>) -> [String] {
        let keep = Set(planned.map(\.id))
        return existing.subtracting(keep).sorted()
    }

    /// Which planned notifications should actually be scheduled right now.
    ///
    /// Suppression used to rely solely on the id being in pending ∪ delivered,
    /// which meant DISMISSING an alert un-suppressed it: clearing it from
    /// Notification Center removed it from `delivered`, so the next write
    /// re-scheduled it and it fired again. The only escape was to resolve the
    /// underlying condition. `fired` is a durable record of "this episode has
    /// already been shown", so a dismissal stays dismissed.
    ///
    /// `snoozedUntil` holds real deadlines (see `snoozeDeadline`), so a snoozed
    /// item stays quiet for its window even across launches.
    public static func toSchedule(planned: [PlannedNotification],
                                  existing: Set<String>,
                                  fired: Set<String>,
                                  snoozedUntil: [String: Date],
                                  now: Date) -> [PlannedNotification] {
        planned.filter { p in
            if existing.contains(p.id) { return false }        // already pending/delivered
            if fired.contains(p.id) { return false }           // shown once; dismissal doesn't revive it
            if let until = snoozedUntil[p.id], until > now { return false }
            return true
        }
    }

    /// Drop remembered ids whose condition no longer holds, so a budget that dips
    /// under its threshold and later crosses it again alerts a SECOND time. Without
    /// this the once-only record would silence it permanently.
    public static func retained<T>(_ byId: [String: T], planned: [PlannedNotification]) -> [String: T] {
        let keep = Set(planned.map(\.id))
        return byId.filter { keep.contains($0.key) }
    }

    /// Same pruning for the plain id set.
    public static func retainedFired(_ fired: Set<String>, planned: [PlannedNotification]) -> Set<String> {
        fired.intersection(planned.map(\.id))
    }
}
