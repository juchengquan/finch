import Foundation
import FinchCore

/// The 4 local-notification categories (Phase 6.2). Raw values double as the
/// `UNNotificationCategory` identifiers.
public enum NotificationKind: String, CaseIterable, Sendable {
    case scheduledDue, budgetWarning, anomaly, weeklyDigest
    public var title: String {
        switch self {
        case .scheduledDue: return "Scheduled reminders"
        case .budgetWarning: return "Budget warnings"
        case .anomaly: return "Unusual transactions"
        case .weeklyDigest: return "Weekly digest"
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
    public static func plan(
        budgets: [BudgetRow], txns: [Tx], scheduled: [ScheduledTemplate],
        categories: [CategoryNode], today: String, ledgerId: String,
        enabled: Set<NotificationKind>, money: (Double) -> String, recentLimit: Int = 50
    ) -> [PlannedNotification] {
        var out: [PlannedNotification] = []

        if enabled.contains(.budgetWarning) {
            for b in budgets {
                let p = Selectors.budgetProgress(b, txns, today, categories)
                if Double(p.pct) >= b.warningPct {
                    out.append(PlannedNotification(
                        id: "budget:\(b.id)", kind: .budgetWarning,
                        title: "Budget alert: \(b.name)",
                        body: "\(p.pct)% used — \(money(p.used)) of \(money(p.base)).",
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
                    title: "Unusual transaction",
                    body: "\(t.merchant) (\(money(t.amount))) looks higher than usual.",
                    tab: .activity, focusId: t.id))
            }
        }

        if enabled.contains(.scheduledDue) {
            for s in scheduled where !s.nextRun.isEmpty && s.nextRun <= today {
                out.append(PlannedNotification(
                    id: "scheduled:\(s.id)", kind: .scheduledDue,
                    title: "Scheduled: \(s.name)",
                    body: "\(s.name) is due. Confirm now?",
                    tab: .scheduled, focusId: s.id))
            }
        }

        if enabled.contains(.weeklyDigest), let d = Selectors.weeklyDigest(txns, ledgerId, today) {
            out.append(PlannedNotification(
                id: "digest:\(d.weekStart)", kind: .weeklyDigest,
                title: "Your weekly digest",
                body: "You spent \(money(d.spent)) across \(d.txCount) transactions this week.",
                tab: .insights, focusId: nil))
        }

        return out
    }
}
