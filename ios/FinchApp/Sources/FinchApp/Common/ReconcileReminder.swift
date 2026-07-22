import Foundation

/// The user-tunable reconcile-reminder cutoff (Settings › Appearance › Accounts).
/// Stored per-device in UserDefaults like the other view prefs; consumed by the
/// account-detail badge and the Accounts-page seal, which both pass it into
/// `Selectors.reconcileStatus(_:_:staleDays:)`.
enum ReconcileReminder {
    static let key = "finch.reconcile.staleDays"
    static let defaultDays = 30
    /// Wheel options: 0 = Off (reconciled accounts never turn stale/orange).
    static let options: [Int] = [0, 7, 14, 30, 60, 90]

    /// The `staleDays` to hand the selector — Off maps to "never stale".
    static func staleDays(_ raw: Int) -> Int { raw <= 0 ? Int.max : raw }
}
