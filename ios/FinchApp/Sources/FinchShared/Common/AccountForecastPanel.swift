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
/// expenses, both legs of a transfer) to the end of the window, less what they already
/// posted — plus what they owe NOW: their pending rows, and occurrences due today or
/// missed, all on today (see `Selectors.accountForecast`). A transfer from another
/// currency arrives converted. Variable items have no amount to project, and nothing
/// unplanned is guessed at — the screen says so under the chart.
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
    ///
    /// `activity` is what was posted and is pending (`activity(txns:accounts:convert:)`).
    /// It is not optional on purpose: without it the forecast counts a bill paid early
    /// twice and loses one due today.
    static func make(account: AccountRow, scheduled: [ScheduledTemplate],
                     today: String, activity: ForecastActivity) -> AccountForecastPanel? {
        let f = Selectors.accountForecast(account, scheduled, today, horizonDays, activity: activity)
        guard !f.events.isEmpty else { return nil }
        return AccountForecastPanel(forecast: f,
                                    watchesOverdraft: watchesOverdraft(accountType: account.type))
    }

    /// The forecast's view of the ledger: its rows, each account's currency for the far
    /// side of a transfer, and `convert` — `FxConvert` in the app — to value it.
    static func activity(txns: [Tx], accounts: [AccountRow],
                         convert: ((Double, String, String, String) -> Double?)?) -> ForecastActivity {
        var currencies: [String: String] = [:]
        for a in accounts { if let c = a.currency { currencies[a.id] = c } }
        return ForecastActivity(txns: txns, accountCurrencies: currencies,
                                convert: convert ?? { _, _, _, _ in nil })
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

    /// The day the alert is keyed on — `crossesBelowZeroOn`, except when what is owed
    /// NOW crosses it (a pending bill, one due today or missed). That crossing is
    /// "today" on every day the bill stays unpaid, so an id on it would be a new alert
    /// each morning; keyed instead on the owed item's own date, where the running
    /// balance first goes below zero, it holds while the same items are owed.
    var crossingKey: String? {
        guard let day = crossesBelowZeroOn else { return nil }
        guard day == forecast.today else { return day }
        var balance = forecast.startingBalance
        for e in forecast.events where e.date <= forecast.today {
            balance = ((balance + e.amount) * 100).rounded() / 100
            if balance < 0 { return e.date }
        }
        return day
    }

    // MARK: Dates

    /// "Oct 23" in the user's locale ("10月23日" in Chinese). The ISO day is parsed in
    /// the device zone (`AppDate.isoDay`), so the label names the same civil day.
    static func dayLabel(_ iso: String) -> String {
        guard let d = AppDate.isoDay.date(from: iso) else { return iso }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
