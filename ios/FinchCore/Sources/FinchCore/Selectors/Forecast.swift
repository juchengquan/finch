import Foundation

// Phase 1.5 batch 3b — forecast selectors (mirror of lib/select.ts +
// lib/recurrence.ts::occurrencesUpTo). These walk scheduled templates forward.

/// A scheduled template (mirror of lib/store/scheduled/state.ts). Only the
/// fields the forecast selectors read; extra JSON keys are ignored on decode.
public struct ScheduledTemplate: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let type: String
    public let amount: Double?
    public let frequency: String
    public let dayOfMonth: Int
    public let weekDay: Int?
    public let accountId: String
    public let fromAccountId: String?
    public let categoryId: String?
    public let startDate: String?
    /// Intended time-of-day for postings, "HH:mm". NULL = unspecified; posting then
    /// stamps the firing moment.
    public let startTime: String?
    public let endDate: String?
    public let nextRun: String
    public let maxExecutions: Int?
    public let installmentTotal: Int?
    public let installmentPaid: Int?
    public let color: String?
    /// `auto_post`, 0/1 — an `Int`, as the web's `autoPost: number` is, so the web's
    /// fixtures (which carry `"autoPost": 0`) still decode; optional because most of
    /// them never carry it. nil and 0 both mean "posted by hand". Read it through
    /// `postsAutomatically`.
    public let autoPost: Int?

    /// Occurrences (`yyyy-MM-dd`) the user chose to skip — native-first, stored in
    /// `app_state.scheduledSkips` (see `ScheduledSkips`). Optional so the web's
    /// fixtures, which never carry the key, still decode; nil and empty mean the same.
    public let skippedDates: [String]?

    public init(id: String, name: String, description: String? = nil, type: String,
                amount: Double? = nil, frequency: String, dayOfMonth: Int, weekDay: Int? = nil,
                accountId: String, fromAccountId: String? = nil, categoryId: String? = nil,
                startDate: String? = nil, startTime: String? = nil, endDate: String? = nil, nextRun: String, maxExecutions: Int? = nil,
                installmentTotal: Int? = nil, installmentPaid: Int? = nil, color: String? = nil,
                autoPost: Int? = nil, skippedDates: [String]? = nil) {
        self.id = id; self.name = name; self.description = description; self.type = type
        self.amount = amount; self.frequency = frequency; self.dayOfMonth = dayOfMonth
        self.weekDay = weekDay; self.accountId = accountId; self.fromAccountId = fromAccountId
        self.categoryId = categoryId
        self.startDate = startDate; self.startTime = startTime; self.endDate = endDate; self.nextRun = nextRun
        self.maxExecutions = maxExecutions; self.installmentTotal = installmentTotal
        self.installmentPaid = installmentPaid
        self.color = color
        self.autoPost = autoPost
        self.skippedDates = skippedDates
    }

    /// Whether due occurrences are added for the user (`autoPostDueScheduled`)
    /// rather than waiting to be posted by hand.
    public var postsAutomatically: Bool { (autoPost ?? 0) != 0 }

    /// Whether the user skipped the occurrence on `date` (`yyyy-MM-dd`).
    public func isSkipped(_ date: String) -> Bool { skippedDates?.contains(date) ?? false }
}

public struct MonthForecast: Equatable, Sendable, Codable {
    public let mtdSpent: Double
    public let unscheduledRest: Double
    public let scheduledRest: Double
    public let projected: Double
    public let daysElapsed: Int
    public let daysRemaining: Int
    public let daysInMonth: Int
    public let dailyRunRate: Double
}

public struct ForecastEvent: Equatable, Sendable, Codable {
    public let date: String
    public let amount: Double
    public let description: String
    public let templateId: String
}
public struct ForecastSeriesPoint: Equatable, Sendable, Codable {
    public let date: String
    public let balance: Double
}
public struct ForecastTrough: Equatable, Sendable, Codable {
    public let date: String
    public let balance: Double
}
public struct AccountForecast: Equatable, Sendable, Codable {
    public let today: String
    public let horizonDays: Int
    public let currency: String
    public let startingBalance: Double
    public let endingBalance: Double
    public let trough: ForecastTrough
    public let events: [ForecastEvent]
    public let series: [ForecastSeriesPoint]
}

extension Selectors {

    // MARK: UTC component helpers (for occurrencesUpTo)
    private static func isISO(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
    private static func utcDay(_ d: Date) -> Int { cal.component(.weekday, from: d) - 1 }   // Sun=0…Sat=6
    private static func daysInMonth(_ y: Int, _ m0: Int) -> Int {
        cal.range(of: .day, in: .month, for: makeUTC(y, m0, 1))!.count
    }
    private static func makeUTC(_ y: Int, _ m0: Int, _ day: Int) -> Date {
        var dc = DateComponents(); dc.year = y; dc.month = m0 + 1; dc.day = day
        return cal.date(from: dc)!
    }

    /// Every occurrence that will actually happen: the recurrence below, minus the
    /// ones the user skipped. This is what posting, generation, forecasts and
    /// reminders all read, so a skip is honoured everywhere by default — only a
    /// screen that SHOWS a skipped occurrence (to offer un-skipping it) passes
    /// `includeSkipped`.
    ///
    /// A skip is not an execution. It removes one date and nothing else, so the
    /// `installment_total` / `max_executions` caps, which count what was posted,
    /// carry on to the next date: a 12-payment plan with one month skipped still
    /// makes 12 payments, one period later. The end date stays a hard stop.
    static func occurrencesUpTo(_ t: ScheduledTemplate, _ throughInclusive: String,
                                includeSkipped: Bool = false) -> [String] {
        let all = recurrenceUpTo(t, throughInclusive)
        guard !includeSkipped, let skipped = t.skippedDates, !skipped.isEmpty else { return all }
        let set = Set(skipped)
        return all.filter { !set.contains($0) }
    }

    /// Mirror of lib/recurrence.ts::occurrencesUpTo — all occurrence dates from
    /// the template's anchor through `throughInclusive`, bounded by endDate.
    /// Skips are NOT applied here; `occurrencesUpTo` above applies them.
    static func recurrenceUpTo(_ t: ScheduledTemplate, _ throughInclusive: String) -> [String] {
        let anchorIso = String((t.startDate ?? t.nextRun).prefix(10))
        guard isISO(anchorIso), isISO(throughInclusive) else { return [] }
        let start = date(anchorIso)
        let endIso = t.endDate.map { String($0.prefix(10)) }
        let throughIso = (endIso != nil && isISO(endIso!) && endIso! < throughInclusive) ? endIso! : throughInclusive
        let limit = date(throughIso)
        if start > limit { return [] }
        let freq = t.frequency
        if freq == "once" { return [ymd(start)] }

        var out: [String] = []
        if freq == "daily" || freq == "weekly" || freq == "biweekly" {
            let step = freq == "daily" ? 1 : (freq == "weekly" ? 7 : 14)
            var cur = start
            if (freq == "weekly" || freq == "biweekly"), let wd = t.weekDay {
                var guardI = 0
                while utcDay(cur) != wd && guardI < 7 { cur = addDays(cur, 1); guardI += 1 }
            }
            var guardI = 0
            while cur <= limit && guardI < 4000 { out.append(ymd(cur)); cur = addDays(cur, step); guardI += 1 }
            return out
        }

        // monthly / quarterly / yearly: step whole months, landing on dayOfMonth.
        let stepMonths = freq == "quarterly" ? 3 : (freq == "yearly" ? 12 : 1)
        let day = t.dayOfMonth != 0 ? t.dayOfMonth : cal.component(.day, from: start)
        var y = cal.component(.year, from: start)
        var m = cal.component(.month, from: start) - 1   // 0-based
        var guardI = 0
        while guardI < 1200 {
            guardI += 1
            let ms = makeUTC(y, m, Swift.min(day, daysInMonth(y, m)))
            if ms > limit { break }
            if ms >= start { out.append(ymd(ms)) }
            m += stepMonths
            while m > 11 { m -= 12; y += 1 }
        }
        return out
    }

    // MARK: monthForecast

    public static func monthForecast(_ txns: [Tx], _ scheduled: [ScheduledTemplate],
                                     _ ledgerId: String, _ month: String, _ today: String) -> MonthForecast? {
        if month.isEmpty { return nil }
        let p = month.split(separator: "-").map { Int($0) ?? 0 }
        let y = p.count > 0 ? p[0] : 0, m = p.count > 1 ? p[1] : 1
        let daysInMo = daysInMonth(y, m - 1)
        let inMonth = String(today.prefix(7)) == month
        let dayOfMonth = inMonth ? Swift.min(Int(today.dropFirst(8).prefix(2)) ?? 0, daysInMo) : daysInMo
        let daysElapsed = dayOfMonth
        let daysRemaining = Swift.max(0, daysInMo - dayOfMonth)

        var mtdSpent = 0.0
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) || !isSpend(t) { continue }
            if String(t.date.prefix(7)) != month { continue }
            if inMonth && t.date > today { continue }
            mtdSpent += -t.amount
        }

        var scheduledRest = 0.0
        if inMonth {
            for rt in scheduled {
                if rt.type != "expense" { continue }
                if rt.frequency != "monthly" { continue }
                guard let amt = rt.amount else { continue }
                if rt.dayOfMonth <= dayOfMonth { continue }
                if rt.dayOfMonth > daysInMo { continue }
                // This month's occurrence. A skipped one, or one after the end
                // date, will not happen, so it is not part of the rest of the month.
                let occurrence = month + "-" + String(format: "%02d", rt.dayOfMonth)
                if rt.isSkipped(occurrence) { continue }
                if let end = rt.endDate, String(end.prefix(10)) < occurrence { continue }
                scheduledRest += abs(amt)
            }
        }

        let dailyRunRate = daysElapsed > 0 ? mtdSpent / Double(daysElapsed) : 0
        let unscheduledRest = inMonth ? r2(dailyRunRate * Double(daysRemaining)) : 0
        let projected = r2(mtdSpent + unscheduledRest + scheduledRest)
        return MonthForecast(
            mtdSpent: r2(mtdSpent), unscheduledRest: unscheduledRest, scheduledRest: r2(scheduledRest),
            projected: projected, daysElapsed: daysElapsed, daysRemaining: daysRemaining,
            daysInMonth: daysInMo, dailyRunRate: r2(dailyRunRate))
    }

    // MARK: accountForecast

    public static func accountForecast(_ account: AccountRow, _ scheduled: [ScheduledTemplate],
                                       _ today: String, _ horizonDays: Int) -> AccountForecast {
        let start = account.balance
        let end = addDaysIso(today, horizonDays)

        var events: [ForecastEvent] = []
        for t in scheduled {
            guard let amt = t.amount else { continue }                  // variable — manual only
            let isToHere = t.accountId == account.id
            let isFromHere = t.type == "transfer" && t.fromAccountId == account.id
            if !isToHere && !isFromHere { continue }
            var sign = 0
            if t.type == "income" && isToHere { sign = 1 }
            else if t.type == "expense" && isToHere { sign = -1 }
            else if t.type == "transfer" && isToHere { sign = 1 }
            else if t.type == "transfer" && isFromHere { sign = -1 }
            if sign == 0 { continue }
            let future = occurrencesUpTo(t, end).filter { $0 > today }
            if future.isEmpty { continue }
            var cap = future.count
            if let total = t.installmentTotal {
                cap = Swift.min(cap, Swift.max(0, total - (t.installmentPaid ?? 0)))
            }
            if let maxEx = t.maxExecutions { cap = Swift.min(cap, maxEx) }
            for i in 0..<cap {
                events.append(ForecastEvent(date: future[i], amount: Double(sign) * abs(amt),
                                            description: t.description ?? t.name, templateId: t.id))
            }
        }
        events.sort { $0.date != $1.date ? $0.date < $1.date : $0.templateId < $1.templateId }   // tie-break: deterministic across templates

        var eventsByDate: [String: Double] = [:]
        for e in events { eventsByDate[e.date, default: 0] += e.amount }
        var series: [ForecastSeriesPoint] = []
        var balance = start
        var troughDate = today
        var troughBalance = start
        for i in 0...horizonDays {
            let d = addDaysIso(today, i)
            balance = r2(balance + (eventsByDate[d] ?? 0))
            series.append(ForecastSeriesPoint(date: d, balance: balance))
            if balance < troughBalance { troughBalance = balance; troughDate = d }
        }

        return AccountForecast(
            today: today, horizonDays: horizonDays, currency: account.currency ?? "",
            startingBalance: r2(start), endingBalance: r2(balance),
            trough: ForecastTrough(date: troughDate, balance: r2(troughBalance)),
            events: events, series: series)
    }

    /// All occurrences of `templates` within [from, through] inclusive, each paired
    /// with its template, sorted by date. Reuses `occurrencesUpTo`, so skipped
    /// occurrences are left out unless `includeSkipped` — the calendar passes it,
    /// to draw a skipped day and offer un-skipping it.
    public static func occurrencesInRange(_ templates: [ScheduledTemplate], from: String, through: String,
                                          includeSkipped: Bool = false)
        -> [(date: String, template: ScheduledTemplate)] {
        var out: [(date: String, template: ScheduledTemplate)] = []
        for t in templates {
            for d in occurrencesUpTo(t, through, includeSkipped: includeSkipped) where d >= from { out.append((d, t)) }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// The first occurrence on or after `today` that will happen — skipped ones
    /// excluded, the end date honoured — within the ~400-day horizon; nil when there
    /// is none (the template has ended). What the list prints as "next".
    public static func nextOccurrence(_ t: ScheduledTemplate, onOrAfter today: String) -> String? {
        occurrencesInRange([t], from: today, through: horizonDay(from: today, addingDays: 400)).first?.date
    }

    /// Whether `date` is an occurrence of `t` at all, skipped or not — the guard on
    /// skipping, so a stray date can't be written into the skip list.
    public static func isOccurrence(_ t: ScheduledTemplate, _ date: String) -> Bool {
        recurrenceUpTo(t, date).last == date
    }

    /// The occurrence a bare "Skip" (no occurrence already in hand) acts on: the
    /// first still-open one from the CURRENT occurrence on (`currentOccurrence`).
    /// So it is this cycle's while that is open, and repeated skips walk forward —
    /// never back to an older missed one.
    ///
    /// Deliberately not `resumeOccurrence` (oldest unresolved first). That is right
    /// for posting, which catches up a backlog in order, but "no gym fee this month"
    /// means this month's: with two old missed occurrences, a Skip that took the
    /// oldest changed nothing the user could see. Older missed occurrences are still
    /// skippable one by one from their day on the calendar.
    public static func skipTarget(template: ScheduledTemplate, posted: [String: Bool], today: String) -> String? {
        guard let current = currentOccurrence(template, today: today) else { return nil }
        let horizon = horizonDay(from: today, addingDays: 400)
        return occurrencesUpTo(template, horizon).first { $0 >= current && posted["\(template.id)|\($0)"] == nil }
    }

    /// The occurrence the present belongs to: of the latest one before today and the
    /// first on or after it — skipped or posted ones included — whichever is nearer
    /// to today, the upcoming one on a tie. Nil when the template has no occurrence
    /// on either side within the horizon.
    public static func currentOccurrence(_ t: ScheduledTemplate, today: String) -> String? {
        let previous = previousOccurrence(t, before: today)
        let next = occurrencesUpTo(t, horizonDay(from: today, addingDays: 400), includeSkipped: true)
            .first { $0 >= today }
        guard let previous else { return next }
        guard let next else { return previous }
        return daysBetween(previous, today) < daysBetween(today, next) ? previous : next
    }

    /// The latest occurrence strictly before `today`, skipped or not — where the
    /// current cycle starts.
    public static func previousOccurrence(_ t: ScheduledTemplate, before today: String) -> String? {
        recurrenceUpTo(t, horizonDay(from: today, addingDays: -1)).last
    }

    private static func daysBetween(_ a: String, _ b: String) -> Int {
        Int((date(b).timeIntervalSince(date(a)) / 86_400).rounded())
    }

    /// Skipped occurrences still in effect, oldest first: those nobody posted since.
    /// A posted occurrence wins over its skip — the money moved, so it is not
    /// "skipped" any more, whatever the list says.
    public static func activeSkips(template: ScheduledTemplate, posted: [String: Bool]) -> [String] {
        (template.skippedDates ?? []).filter { posted["\(template.id)|\($0)"] == nil }.sorted()
    }

    /// The skip a bare "Unskip" undoes: the LATEST active one. Skipping always takes
    /// the oldest unresolved occurrence, so repeated skips walk forward and repeated
    /// unskips walk back — the last skip is the first undone.
    public static func unskipTarget(template: ScheduledTemplate, posted: [String: Bool]) -> String? {
        activeSkips(template: template, posted: posted).last
    }

    /// `today` (`yyyy-MM-dd`) advanced by `days` calendar days, computed inside
    /// ONE calendar (UTC) — parsed and formatted within that same calendar, so
    /// the timezone is unobservable; do not "fix" it to local (ios/CLAUDE.md,
    /// civil-date convention). Single source of truth for the ~400-day
    /// lookahead horizon shared by `resumeOccurrence` below and
    /// `scheduledNextRun` (FinchApp/Tabs/ScheduledTab.swift) — both need a
    /// horizon long enough that a yearly template still resolves.
    public static func horizonDay(from today: String, addingDays days: Int) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = utc.date(from: DateComponents(
            year: Int(today.prefix(4)), month: Int(today.dropFirst(5).prefix(2)),
            day: Int(today.dropFirst(8).prefix(2)))) ?? Date()
        let h = utc.dateComponents([.year, .month, .day],
                                   from: utc.date(byAdding: .day, value: days, to: base) ?? base)
        return String(format: "%04d-%02d-%02d", h.year ?? 0, h.month ?? 1, h.day ?? 1)
    }

    /// The occurrence a bare "Post now" (no occurrence already in hand) should
    /// act on: catch up oldest-first — the same order `generateDue` uses — then
    /// fall forward to the next due occurrence once nothing is missed. Scans from
    /// the template's anchor (so an old unposted occurrence is still caught) up to a
    /// ~400-day forward horizon, enough that a yearly template still resolves.
    public static func resumeOccurrence(template: ScheduledTemplate, posted: [String: Bool],
                                        today: String) -> String? {
        let horizon = horizonDay(from: today, addingDays: 400)
        let all = occurrencesUpTo(template, horizon)
        if let missed = all.first(where: { $0 < today && posted["\(template.id)|\($0)"] == nil }) {
            return missed
        }
        return all.first { $0 >= today && posted["\(template.id)|\($0)"] == nil }
    }

    /// "templateId|occurrenceDate" → isPending, for every posted occurrence (txns
    /// whose sourceTemplateId is set). true ⇒ pending; false ⇒ done. An absent key
    /// means only **not posted** — callers must compare the date against today to
    /// tell `upcoming` (still ahead) from `missed` (past, and nobody posted it).
    public static func scheduledPostedMap(_ txns: [Tx]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        // Key on the occurrence the entry FULFILS, not the day it was recorded —
        // they differ when the user posts a missed item on a later date. NULL
        // falls back to `date`, which is the pre-2026-07-22 behaviour, so
        // historical generateDue postings still resolve with no backfill.
        for t in txns { if let s = t.sourceTemplateId { out["\(s)|\(t.occurrenceDate ?? t.date)"] = (t.pending ?? false) } }
        return out
    }
}
