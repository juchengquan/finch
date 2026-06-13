import Foundation

// Phase 1.5 batch 3b — forecast selectors (mirror of lib/select.ts +
// lib/recurrence.ts::occurrencesUpTo). These walk scheduled templates forward.

/// A scheduled template (mirror of lib/store/scheduled/state.ts). Only the
/// fields the forecast selectors read; extra JSON keys are ignored on decode.
public struct ScheduledTemplate: Equatable, Sendable, Codable {
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
    public let startDate: String?
    public let endDate: String?
    public let nextRun: String
    public let maxExecutions: Int?
    public let installmentTotal: Int?
    public let installmentPaid: Int?

    public init(id: String, name: String, description: String? = nil, type: String,
                amount: Double? = nil, frequency: String, dayOfMonth: Int, weekDay: Int? = nil,
                accountId: String, fromAccountId: String? = nil, startDate: String? = nil,
                endDate: String? = nil, nextRun: String, maxExecutions: Int? = nil,
                installmentTotal: Int? = nil, installmentPaid: Int? = nil) {
        self.id = id; self.name = name; self.description = description; self.type = type
        self.amount = amount; self.frequency = frequency; self.dayOfMonth = dayOfMonth
        self.weekDay = weekDay; self.accountId = accountId; self.fromAccountId = fromAccountId
        self.startDate = startDate; self.endDate = endDate; self.nextRun = nextRun
        self.maxExecutions = maxExecutions; self.installmentTotal = installmentTotal
        self.installmentPaid = installmentPaid
    }
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

    /// Mirror of lib/recurrence.ts::occurrencesUpTo — all occurrence dates from
    /// the template's anchor through `throughInclusive`, bounded by endDate.
    static func occurrencesUpTo(_ t: ScheduledTemplate, _ throughInclusive: String) -> [String] {
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
        events.sort { $0.date < $1.date }

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
}
