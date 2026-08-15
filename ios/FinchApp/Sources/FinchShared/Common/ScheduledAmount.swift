import Foundation
import FinchCore

public extension ScheduledTemplate {
    /// The amount as it should be READ — negative for an expense.
    ///
    /// `ScheduledTemplate.amount` is an unsigned magnitude with `type` carrying the
    /// direction, unlike `Tx.amount`, which is already signed. Every screen that
    /// rendered a template the way it renders a transaction therefore dropped the minus:
    /// rent showed as `$1,500.00`, which reads as money arriving.
    ///
    /// One property rather than `type == "expense" ? -amt : amt` at each call site,
    /// because there are three of them across two frameworks — the shared `ScheduledRow`
    /// leaf (which both the SwiftUI list and the UIKit `ScheduledListVC` host), the
    /// calendar's occurrence rows, and the detail header. Three literals is how they
    /// drift.
    ///
    /// **Transfers stay unsigned**, deliberately: money moving between your own accounts
    /// is neither spent nor received, and the day-totals logic already excludes them from
    /// both sides for the same reason.
    var signedAmount: Double? {
        guard let amount else { return nil }
        return type == "expense" ? -abs(amount) : abs(amount)
    }
}
