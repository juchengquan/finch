import Foundation

/// Reconcile freshness for an account's last checkpoint.
public enum ReconcileStatus: Equatable, Sendable {
    case never
    case fresh(days: Int)
    case stale(days: Int)
}

extension Selectors {
    private static let utcDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `.never` when never reconciled; else whole-days `today − lastReconciledAt`
    /// (clamped ≥ 0): `> staleDays` ⇒ `.stale`, else `.fresh`. Dates are YYYY-MM-DD.
    public static func reconcileStatus(_ lastReconciledAt: String?, _ today: String, staleDays: Int = 35) -> ReconcileStatus {
        guard let iso = lastReconciledAt, !iso.isEmpty,
              let last = utcDayFmt.date(from: String(iso.prefix(10))),
              let now = utcDayFmt.date(from: String(today.prefix(10))) else {
            return .never
        }
        let days = max(0, Int((now.timeIntervalSince(last) / 86_400).rounded()))
        return days > staleDays ? .stale(days: days) : .fresh(days: days)
    }
}
