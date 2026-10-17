import Foundation
import FinchCore

/// Where an account's balance is heading, as the account screen and the low-balance
/// alert both read it.
///
/// One model for three readers — `AccountDetailVC` on iOS, `AccountDetailView` on
/// macOS, and `NotificationPlanner` — because an alert that says "below zero on the
/// 23rd" must be the same projection the screen it opens draws. Built over
/// `Selectors.accountForecast`, which was parity-tested against the web's
/// `accountForecast` but had no native caller.
///
/// **What it counts:** fixed-amount scheduled items that touch the account (income,
/// expenses, both legs of a transfer) from tomorrow to the end of the window. Variable
/// items have no amount to project, and nothing unplanned is guessed at — the screen
/// says so under the chart.
struct AccountForecastPanel: Equatable {

    /// The projection window, in days after today. Fixed rather than the web's 30/60/90
    /// picker: one window covers a full monthly cycle of rent and pay, and the screen
    /// and the alert must look the same distance ahead or the alert would announce a
    /// dip the screen does not show.
    static let horizonDays = 30

    let forecast: AccountForecast
    /// Whether a balance below zero means trouble for this account. False on a credit
    /// card, where a negative balance is the debt it normally carries — warning on it
    /// would flag every card, every day.
    let watchesOverdraft: Bool

    /// The panel, or nil when nothing scheduled lands on this account inside the
    /// window — a flat line and "no change" would only take up room.
    ///
    /// `today` should be the WALL-clock day (`store.wallToday`), not the data-anchored
    /// `store.today`. The alert is delivered on real dates, the screen has to agree with
    /// it, and the stored balance it starts from is the balance now — anchoring on the
    /// newest transaction would replay scheduled items that have already happened.
    static func make(account: AccountRow, scheduled: [ScheduledTemplate],
                     today: String) -> AccountForecastPanel? {
        let f = Selectors.accountForecast(account, scheduled, today, horizonDays)
        guard !f.events.isEmpty else { return nil }
        return AccountForecastPanel(forecast: f,
                                    watchesOverdraft: watchesOverdraft(accountType: account.type))
    }

    /// See `watchesOverdraft`. `credit_card` is the only liability type in the schema.
    static func watchesOverdraft(accountType: String?) -> Bool {
        accountType != "credit_card"
    }

    // MARK: Figures

    var endingBalance: Double { forecast.endingBalance }
    var low: ForecastTrough { forecast.trough }
    /// The day-by-day balances, today first — the chart's line.
    var balances: [Double] { forecast.series.map(\.balance) }

    /// Does the balance dip below where it is today at some point?
    var dips: Bool { low.balance < forecast.startingBalance }

    /// The low point is below zero on an account where that matters — the screen's
    /// warning.
    var warns: Bool { watchesOverdraft && low.balance < 0 }

    /// The first day a balance that is not negative today goes below zero — when the
    /// alert should be about, which is earlier than the low point when the balance keeps
    /// falling after it crosses.
    ///
    /// nil when the balance is ALREADY below zero: that is the present, not a forecast,
    /// and an alert keyed on "the first negative day" would be keyed on today, every
    /// day — a fresh alert each morning for as long as the account stays overdrawn.
    var crossesBelowZeroOn: String? {
        guard watchesOverdraft, forecast.startingBalance >= 0 else { return nil }
        return forecast.series.first { $0.balance < 0 }?.date
    }

    // MARK: Dates

    /// "Oct 23" in the user's locale ("10月23日" in Chinese). The ISO day is parsed in
    /// the device zone (`AppDate.isoDay`), so the label names the same civil day.
    static func dayLabel(_ iso: String) -> String {
        guard let d = AppDate.isoDay.date(from: iso) else { return iso }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
