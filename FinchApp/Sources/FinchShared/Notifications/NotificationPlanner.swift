import Foundation
import FinchCore

/// The local-notification categories (Phase 6.2, plus `lowBalance`). Raw values
/// double as the `UNNotificationCategory` identifiers. Declaration order is the order
/// of the Settings toggles, which iterate `allCases`.
public enum NotificationKind: String, CaseIterable, Sendable {
    case scheduledDue, budgetWarning, lowBalance, anomaly, weeklyDigest
    /// String(localized:) — NOT a bare literal. Call sites pass this straight to
    /// `Toggle(_:isOn:)`, and a plain String selects SwiftUI's StringProtocol
    /// overload, which does no lookup: the Settings toggles rendered English in
    /// every language.
    public var title: String {
        switch self {
        case .scheduledDue: return String(localized: "Scheduled reminders")
        case .budgetWarning: return String(localized: "Budget warnings")
        case .lowBalance: return String(localized: "Low balance warnings")
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
    /// When this alert should be handed to the user, if that is knowable in advance.
    ///
    /// `nil` means "as soon as policy allows" — the reactive alerts, which are only true
    /// because data just changed. A date means iOS holds it on a calendar trigger and
    /// delivers it whether or not the app is ever opened, which is how a bill due on the
    /// 1st can announce itself on the 1st with no background execution.
    ///
    /// Declared LAST with a default so every existing construction site compiles
    /// untouched — this is a public struct with a memberwise init.
    public let deliverOn: Date?
    /// The occurrence a scheduled reminder is about (`yyyy-MM-dd`), so its "Confirm
    /// now" posts that one and no other. Nil for every other kind.
    public let occurrence: String?

    public init(id: String, kind: NotificationKind, title: String, body: String,
                tab: AppTab?, focusId: String?, deliverOn: Date? = nil, occurrence: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.tab = tab
        self.focusId = focusId
        self.deliverOn = deliverOn
        self.occurrence = occurrence
    }
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
    ///
    /// `accounts` and `accountMoney` feed the low-balance alert only, and default so the
    /// call sites that predate it compile unchanged. `accountMoney` formats an amount in
    /// the account's OWN currency (the forecast is in it); nil falls back to `money`.
    public static func plan(
        budgets: [BudgetRow], txns: [Tx], scheduled: [ScheduledTemplate],
        categories: [CategoryNode], today: String, wallToday: String, ledgerId: String,
        enabled: Set<NotificationKind>, money: (Double) -> String, recentLimit: Int = 50,
        deliveryHour: Int = 9, calendar: Calendar = .current,
        accounts: [AccountRow] = [], accountMoney: ((Double, String?) -> String)? = nil
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

        if enabled.contains(.lowBalance) {
            // The account screen's own forecast (`AccountForecastPanel`), so the alert
            // and the screen it opens cannot disagree — both on the WALL-clock day.
            //
            // Only a FUTURE crossing alerts — see `crossesBelowZeroOn` for why an
            // account already below zero does not. It is announced `lowBalanceLeadDays`
            // ahead of the crossing, which is the point of a forecast: time to move
            // money before the bill lands. Inside that lead it is true now, so it carries
            // no date and policy decides when it lands, like a past-due reminder.
            //
            // The id carries the crossing DAY. `toSchedule` never re-adds an id that is
            // already pending, so on an account-only id an earlier crossing — a new bill
            // pulling it forward a week — would leave the old, too-late alert in place.
            // A new day is a new id: the stale one is cancelled, the right one scheduled.
            // While the day holds, the id is stable, so re-planning on every write
            // replaces rather than duplicates.
            func format(_ amount: Double, _ currency: String?) -> String {
                accountMoney?(amount, currency) ?? money(amount)
            }
            for a in accounts where a.isActive != false {
                guard let panel = AccountForecastPanel.make(account: a, scheduled: scheduled, today: wallToday),
                      let crossing = panel.crossesBelowZeroOn else { continue }
                let name = a.name ?? String(localized: "Account")
                let notifyDay = Selectors.horizonDay(from: crossing, addingDays: -lowBalanceLeadDays)
                let crossingLabel = AccountForecastPanel.dayLabel(crossing)
                let lowAmount = format(panel.low.balance, a.currency)
                // One date when the low point IS the crossing — "below zero on the 23rd,
                // down to −120 by the 23rd" says the day twice.
                let body = panel.low.date == crossing
                    ? String(localized: "Scheduled items take it below zero on \(crossingLabel), to \(lowAmount).")
                    : String(localized: "Scheduled items take it below zero on \(crossingLabel), down to \(lowAmount) by \(AccountForecastPanel.dayLabel(panel.low.date)).")
                out.append(PlannedNotification(
                    id: "lowBalance:\(a.id):\(crossing)", kind: .lowBalance,
                    title: String(localized: "Low balance ahead: \(name)"),
                    body: body,
                    tab: .accounts, focusId: a.id,
                    deliverOn: notifyDay > wallToday ? deliverAt(notifyDay, hour: deliveryHour, calendar) : nil))
            }
        }

        if enabled.contains(.anomaly) {
            let stats = Selectors.merchantStats(txns, ledgerId)
            // Score PURCHASES, not payment legs. `anomalyScore` takes a single Tx
            // and cannot see sibling legs, so it can only ever judge what it is
            // handed — the fix belongs here. Scored per leg, a purchase paid on two
            // cards was assessed as two smaller spends: one leg could clear the
            // threshold on its own, alerting the user about an amount they never
            // spent in one go, while the purchase itself was never assessed whole.
            //
            // The id keys on the PURCHASE too. On a posting id, one purchase could
            // raise two alerts, and an edit that re-keys a posting would strand an
            // alert `cancelIDs` can no longer match.
            for t in Selectors.byPurchase(txns).prefix(recentLimit) {
                guard let a = Selectors.anomalyScore(t, stats), a.isAnomaly else { continue }
                out.append(PlannedNotification(
                    id: "anomaly:\(t.purchaseKey)", kind: .anomaly,
                    title: String(localized: "Unusual transaction"),
                    body: String(localized: "\(t.merchant) (\(money(t.amount))) looks higher than usual."),
                    tab: .activity, focusId: t.id))
            }
        }

        if enabled.contains(.scheduledDue) {
            // EVERY template with a next run, not just the due ones.
            //
            // `cancelIDs` removes anything pending that this plan does not contain, so a
            // future alert emitted once and then omitted would be cancelled by the very
            // next write. Emitting it on every run is what keeps it alive — and because
            // the id is stable, re-planning replaces rather than duplicates.
            //
            // The id carries the OCCURRENCE, as the low-balance id carries its crossing
            // day. On a template-only id every occurrence shared one id: `toSchedule`
            // never re-adds an id already pending, and `fired` remembered it for as
            // long as the template had a next run — which a recurring one always does.
            // So the first reminder was the only one, and a reminder pending for the
            // 15th still fired after the 15th was skipped or paid early. Per
            // occurrence, a skip, an early payment or an edit that moves the day plans
            // a new id: the old request is withdrawn and the new one scheduled.
            //
            // Past-due carries no date: it is true NOW, so policy decides when it lands.
            // Future carries its run date at the delivery hour, and iOS holds it.
            //
            // The date is the occurrence the reminder's own "Confirm" would post —
            // `resumeOccurrence`, the oldest unresolved else the next due — not the
            // stored `next_run`. That column is never written (inserted NULL), so it
            // meant no reminder at all for a template made in the app, and a stale
            // one for an imported template. The recurrence is also what knows about
            // skips and the end date: a skipped occurrence is passed over, and an
            // ended template has nothing left to remind about.
            //
            // Not the "Add automatically" ones: their occurrences arrive on their own,
            // in To confirm, so "is due. Confirm now?" would nag about something the
            // app has already done. Leaving them out of the plan also cancels any
            // alert scheduled before the switch was turned on.
            let posted = Selectors.scheduledPostedMap(txns)
            for s in scheduled where !s.postsAutomatically {
                // A paid-off installment plan has no more payments to prompt for.
                if let total = s.installmentTotal, (s.installmentPaid ?? 0) >= total { continue }
                guard let due = Selectors.resumeOccurrence(template: s, posted: posted, today: wallToday) else { continue }
                let isFuture = due > wallToday
                out.append(PlannedNotification(
                    id: scheduledId(s.id, due), kind: .scheduledDue,
                    title: String(localized: "Scheduled: \(s.name)"),
                    body: String(localized: "\(s.name) is due. Confirm now?"),
                    tab: .scheduled, focusId: s.id,
                    deliverOn: isFuture ? deliverAt(due, hour: deliveryHour, calendar) : nil,
                    occurrence: due))
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

    /// How many days before a forecast dip below zero the low-balance alert arrives. A
    /// judgement: enough for a transfer between banks to clear, short enough that the
    /// forecast it rests on is still the one that comes true.
    static let lowBalanceLeadDays = 3

    /// An ISO day string plus an hour, as a `Date`. Returns nil-safe fallback `nil` when
    /// the day cannot be parsed, so a malformed `nextRun` degrades to "send now" rather
    /// than crashing or silently vanishing.
    static func deliverAt(_ day: String, hour: Int, _ calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                  hour: hour, minute: 0, second: 0))
    }

    /// Ids currently scheduled or delivered that are no longer planned — a kind was
    /// disabled, a budget fell back under threshold, or a due item was confirmed — so
    /// they should be cancelled. Never an `unplannedPrefix` alert: no plan contains
    /// one, so every re-plan would otherwise clear it.
    public static func cancelIDs(planned: [PlannedNotification], existing: Set<String>) -> [String] {
        let keep = Set(planned.map(\.id))
        return existing.subtracting(keep).filter { !$0.hasPrefix(unplannedPrefix) }.sorted()
    }

    /// Id prefix of the one-off alerts raised outside the plan
    /// (`NotificationService.notifyRefused`).
    public static let unplannedPrefix = "refused:"

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

    /// Same pruning for the plain id set, with one exception: the latest scheduled
    /// reminder already SHOWN for each template is kept after its occurrence leaves
    /// the plan.
    ///
    /// Paying an occurrence and then undoing the payment makes it due again. Pruned,
    /// its reminder would fire a second time seconds after the undo, about something
    /// the user has just been looking at. "Shown" is "its day has come": a reminder is
    /// recorded in `fired` when it is SCHEDULED, so a future one that leaves the plan
    /// — skipped, paid early, moved — is forgotten like any other id. It was never
    /// seen, and if it comes back (un-skipped) it has to be scheduled again.
    ///
    /// The latest only, and only while its template exists, so the set holds at most
    /// two ids per template — that one and the planned one — instead of a reminder a
    /// month for ever. `templateIds` is every template the plan was built from.
    public static func retainedFired(_ fired: Set<String>, planned: [PlannedNotification],
                                     templateIds: Set<String>, wallToday: String) -> Set<String> {
        let keep = Set(planned.map(\.id))
        var latestShown: [String: String] = [:]   // templateId → occurrence
        for id in fired.subtracting(keep) {
            guard let shown = scheduledOccurrence(fromId: id),
                  templateIds.contains(shown.templateId), shown.date <= wallToday else { continue }
            if shown.date > latestShown[shown.templateId] ?? "" { latestShown[shown.templateId] = shown.date }
        }
        return fired.intersection(keep).union(latestShown.map { scheduledId($0.key, $0.value) })
    }

    /// `scheduled:<templateId>:<occurrence>` — one reminder per occurrence.
    static func scheduledId(_ templateId: String, _ occurrence: String) -> String {
        "scheduled:\(templateId):\(occurrence)"
    }

    /// The template and occurrence a scheduled reminder's id names; nil for any
    /// other id, including the undated `scheduled:<templateId>` of earlier builds.
    /// Nothing plans that one any more, so the first refresh after the update
    /// withdraws it, pending or delivered, through `cancelIDs` — and this returning
    /// nil is what lets `retainedFired` forget it too.
    public static func scheduledOccurrence(fromId id: String) -> (templateId: String, date: String)? {
        let prefix = "scheduled:"
        guard id.hasPrefix(prefix) else { return nil }
        let rest = id.dropFirst(prefix.count)
        guard let colon = rest.lastIndex(of: ":") else { return nil }
        let template = rest[..<colon]
        let date = rest[rest.index(after: colon)...]
        guard !template.isEmpty,
              date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return (String(template), String(date))
    }

    /// What one `NotificationService.refresh` does before it schedules anything:
    /// which requests to withdraw, what the durable records become, and what is
    /// left to schedule. Pure, so a sequence of refreshes can be tested against a
    /// fake notification centre.
    public struct Reconciliation: Equatable {
        public let cancelPending: [String]
        public let cancelDelivered: [String]
        public let fired: Set<String>
        public let snoozedUntil: [String: Date]
        public let schedule: [PlannedNotification]
    }

    public static func reconcile(planned: [PlannedNotification], pending: Set<String>, delivered: Set<String>,
                                 fired: Set<String>, snoozedUntil: [String: Date], now: Date,
                                 templateIds: Set<String>, wallToday: String) -> Reconciliation {
        // Forget ids whose condition has resolved, so the same budget can alert
        // again next time it crosses. Pruning BEFORE the schedule decision keeps
        // "already shown" scoped to the current episode.
        let keptFired = retainedFired(fired, planned: planned, templateIds: templateIds, wallToday: wallToday)
        let keptSnoozes = retained(snoozedUntil, planned: planned)
        return Reconciliation(
            cancelPending: cancelIDs(planned: planned, existing: pending),
            cancelDelivered: cancelIDs(planned: planned, existing: delivered),
            fired: keptFired, snoozedUntil: keptSnoozes,
            schedule: toSchedule(planned: planned, existing: pending.union(delivered),
                                 fired: keptFired, snoozedUntil: keptSnoozes, now: now))
    }
}
