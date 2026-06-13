import Foundation

// Phase 1.5 batch 2 — aggregate / digest selectors (mirror of lib/select.ts).
// Return-type field names match the web JSON verbatim (the parity fixtures
// decode straight into these).

public struct RecentExpense: Equatable, Sendable, Codable {
    public let merchant: String
    public let amount: Double        // positive magnitude, native (account) currency
    public let currency: String
    public let accountId: String
    public let categoryId: String?
}

public struct DuplicateMatch: Equatable, Sendable, Codable {
    public let id: String
    public let merchant: String
    public let date: String
}
/// The Add-form draft `findDuplicate` checks against.
public struct DuplicateDraft: Equatable, Sendable, Codable {
    public let merchant: String
    public let amount: Double
    public let accountId: String
    public let date: String
    public let excludeId: String?
}

public struct CategorySuggestion: Equatable, Sendable, Codable {
    public let categoryId: String
    public let count: Int
    public let confidence: Double    // 0…1, NOT rounded (raw topCount/total)
}

public struct IncomeFlowCategory: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let spent: Double
    public let color: String
}
public struct IncomeFlow: Equatable, Sendable, Codable {
    public let income: Double
    public let categories: [IncomeFlowCategory]
    public let saved: Double
}
/// `{ id, name, color? }` — the category input incomeCategoryFlow takes.
public struct ColoredCategory: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let color: String?
    public init(id: String, name: String, color: String?) { self.id = id; self.name = name; self.color = color }
}

public struct WeeklyTopCategory: Equatable, Sendable, Codable {
    public let categoryId: String
    public let amount: Double
}
public struct WeeklyBiggest: Equatable, Sendable, Codable {
    public let txId: String
    public let merchant: String
    public let amount: Double
    public let date: String
}
public struct WeeklyDigest: Equatable, Sendable, Codable {
    public let weekStart: String
    public let weekEnd: String
    public let spent: Double
    public let income: Double
    public let net: Double
    public let prevSpent: Double?
    public let vsPrevPct: Double?
    public let avgSpent: Double
    public let avgWeeks: Int
    public let vsAvgPct: Double?
    public let topCategories: [WeeklyTopCategory]
    public let biggestExpense: WeeklyBiggest?
    public let txCount: Int
}

extension Selectors {

    static let fallbackCatColor = "#9ca3af"
    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    /// Whole-day difference a−b between two YYYY-MM-DD dates (UTC).
    private static func dayDiff(_ a: String, _ b: String) -> Int {
        Int((date(a).timeIntervalSince(date(b)) / 86_400).rounded())
    }
    private static func addDaysIso(_ iso: String, _ n: Int) -> String { ymd(addDays(date(iso), n)) }
    /// YYYY-MM-DD for the Monday of the ISO week containing `d` (UTC).
    private static func isoWeekMonday(_ d: String) -> String {
        let dt = date(d)
        let jsDay = cal.component(.weekday, from: dt) - 1   // Sun=0…Sat=6
        return ymd(addDays(dt, -((jsDay + 6) % 7)))         // shift back to Monday
    }

    // MARK: incomeCategoryFlow

    public static func incomeCategoryFlow(_ txns: [Tx], _ categories: [ColoredCategory],
                                          _ ledgerId: String, _ month: String, _ topN: Int = 6) -> IncomeFlow {
        var income = 0.0
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) || kindOf(t) != "income" { continue }
            if !month.isEmpty && String(t.date.prefix(7)) != month { continue }
            income += t.amount
        }
        let byCat = categorySpend(txns, ledgerId, month)
        let lookup = Dictionary(uniqueKeysWithValues:
            categories.map { ($0.id, (name: $0.name, color: $0.color ?? fallbackCatColor)) })
        let ranked = byCat.map { id, spent in
            IncomeFlowCategory(id: id, name: lookup[id]?.name ?? id, spent: spent,
                               color: lookup[id]?.color ?? fallbackCatColor)
        }.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }
        var top = Array(ranked.prefix(topN))
        let restSpent = ranked.dropFirst(topN).reduce(0.0) { $0 + $1.spent }
        if restSpent > 0 {
            top.append(IncomeFlowCategory(id: "__other__", name: "Other", spent: restSpent, color: fallbackCatColor))
        }
        let spentTotal = ranked.reduce(0.0) { $0 + $1.spent }
        let saved = Swift.max(0, r2(income - spentTotal))
        return IncomeFlow(
            income: r2(income),
            categories: top.map { IncomeFlowCategory(id: $0.id, name: $0.name, spent: r2($0.spent), color: $0.color) },
            saved: saved)
    }

    // MARK: recentExpenses

    public static func recentExpenses(_ txns: [Tx], _ ledgerId: String, _ limit: Int = 5) -> [RecentExpense] {
        var seen = Set<String>()
        var out: [(date: String, time: String, row: RecentExpense)] = []
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            if kindOf(t) != "expense" { continue }
            let native = t.nativeAmount ?? t.amount
            if native >= 0 { continue }
            let currency = t.currency ?? "USD"
            let amountMag = abs(native)
            let key = "\(t.merchant)|\(String(format: "%.2f", amountMag))|\(t.account)|\(t.category ?? "")|\(currency)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append((t.date, t.time ?? "",
                        RecentExpense(merchant: t.merchant, amount: amountMag, currency: currency,
                                      accountId: t.account, categoryId: t.category)))
        }
        out.sort { a, b in
            if a.date != b.date { return a.date > b.date }   // date DESC
            return a.time > b.time                           // time DESC
        }
        return Array(out.prefix(limit).map { $0.row })
    }

    // MARK: findDuplicate

    public static func findDuplicate(_ txns: [Tx], _ ledgerId: String, _ draft: DuplicateDraft) -> DuplicateMatch? {
        let merchant = normalize(draft.merchant)
        if merchant.isEmpty { return nil }
        let mag = abs(draft.amount)
        if !(mag > 0) { return nil }
        let day = String(draft.date.prefix(10))
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            if let ex = draft.excludeId, t.id == ex { continue }
            if t.account != draft.accountId { continue }
            let k = kindOf(t)
            if k != "expense" && k != "income" { continue }
            if normalize(t.merchant) != merchant { continue }
            let native = abs(t.nativeAmount ?? t.amount)
            if abs(native - mag) > 0.005 { continue }
            if abs(dayDiff(String(t.date.prefix(10)), day)) > 3 { continue }   // DUPLICATE_WINDOW_DAYS
            return DuplicateMatch(id: t.id, merchant: t.merchant, date: t.date)
        }
        return nil
    }

    // MARK: suggestCategory

    public static func suggestCategory(_ txns: [Tx], _ ledgerId: String, _ description: String,
                                       _ counterpartyId: String? = nil,
                                       minCount: Int = 1, minConfidence: Double = 0.5) -> CategorySuggestion? {
        let term = normalize(description)
        if term.isEmpty && counterpartyId == nil { return nil }
        var counts: [String: Int] = [:]
        var total = 0
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            if kindOf(t) != "expense" { continue }
            let matches = counterpartyId != nil ? (t.counterpartyId == counterpartyId) : (normalize(t.merchant) == term)
            if !matches { continue }
            if let splits = t.splits, !splits.isEmpty {
                for s in splits where s.categoryId != nil { counts[s.categoryId!, default: 0] += 1; total += 1 }
            } else if let cat = t.category {
                counts[cat, default: 0] += 1; total += 1
            }
        }
        if total == 0 { return nil }
        var topId = ""; var topCount = 0
        for (id, n) in counts where n > topCount { topId = id; topCount = n }
        if topId.isEmpty { return nil }
        let confidence = Double(topCount) / Double(total)
        if confidence < minConfidence && topCount < minCount { return nil }
        return CategorySuggestion(categoryId: topId, count: topCount, confidence: confidence)
    }

    // MARK: weeklyDigest

    public static func weeklyDigest(_ txns: [Tx], _ ledgerId: String, _ anchor: String) -> WeeklyDigest? {
        if anchor.isEmpty { return nil }
        let thisMon = isoWeekMonday(anchor)
        let weekStart = addDaysIso(thisMon, -7)
        let weekEnd = addDaysIso(thisMon, -1)
        let prevStart = addDaysIso(weekStart, -7)
        let prevEnd = addDaysIso(weekStart, -1)
        let avgStart = addDaysIso(weekStart, -7 * 12)
        let avgEnd = addDaysIso(weekStart, -1)

        var spent = 0.0, income = 0.0, prevSpent = 0.0, avgSum = 0.0
        var txCount = 0
        var prevHasAny = false, everHadConfirmed = false
        var byCat: [String: Double] = [:]
        var weeksWithData = Set<String>()
        var biggest: WeeklyBiggest?

        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            everHadConfirmed = true
            let k = kindOf(t)
            let d = t.date
            let inWeek = d >= weekStart && d <= weekEnd
            let inPrev = d >= prevStart && d <= prevEnd
            let inAvg = d >= avgStart && d <= avgEnd
            if inPrev { prevHasAny = true }

            if isSpend(t) {
                let mag = -t.amount
                if inWeek {
                    spent += mag
                    txCount += 1
                    if let splits = t.splits, !splits.isEmpty {
                        for s in splits where s.categoryId != nil { byCat[s.categoryId!, default: 0] += -s.amountBase }
                    } else if let cat = t.category {
                        byCat[cat, default: 0] += mag
                    }
                    if k == "expense" && (biggest == nil || mag > biggest!.amount) {
                        biggest = WeeklyBiggest(txId: t.id, merchant: t.merchant, amount: mag, date: d)
                    }
                }
                if inPrev { prevSpent += mag }
                if inAvg { avgSum += mag; weeksWithData.insert(isoWeekMonday(d)) }
            } else if k == "income" && inWeek {
                income += t.amount
            }
        }

        if !everHadConfirmed { return nil }

        let prev: Double? = prevHasAny ? r2(prevSpent) : nil
        let avgWeeks = weeksWithData.count
        let avg = avgWeeks > 0 ? r2(avgSum / Double(avgWeeks)) : 0
        let topCategories = Array(byCat
            .map { WeeklyTopCategory(categoryId: $0.key, amount: r2($0.value)) }
            .sorted { $0.amount > $1.amount }
            .prefix(5))

        return WeeklyDigest(
            weekStart: weekStart, weekEnd: weekEnd,
            spent: r2(spent), income: r2(income), net: r2(income - spent),
            prevSpent: prev,
            vsPrevPct: (prev != nil && prev! > 0) ? r2((spent - prev!) / prev!) : nil,
            avgSpent: avg, avgWeeks: avgWeeks,
            vsAvgPct: (avgWeeks >= 4 && avg > 0) ? r2((spent - avg) / avg) : nil,
            topCategories: topCategories,
            biggestExpense: biggest,
            txCount: txCount)
    }
}
