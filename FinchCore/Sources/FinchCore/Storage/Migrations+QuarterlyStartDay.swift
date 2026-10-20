import Foundation
import GRDB

extension Migrations {
    /// Carry quarterly and yearly schedules on from the day they actually ran.
    ///
    /// Until #817 a quarterly or yearly item recurred on its stored `day_of_month`,
    /// and the iOS sheet never sent one for those frequencies, so they all stored 1:
    /// an item starting 15 Mar came due on 1 Jun, 1 Sep… and users posted against
    /// those dates. #817 moved the recurrence onto the start date's day (15 Mar,
    /// 15 Jun, 15 Sep), which is right for a new item but leaves an old one's history
    /// on dates the schedule no longer has: the row reads overdue from 15 Mar, Post
    /// opens 15 Mar, and a generator books 15 Mar, 15 Jun and 15 Sep again.
    ///
    /// So, for such an item, the start moves to the first occurrence the OLD rule
    /// produced (1 Jun) and `day_of_month` to its day. The new rule then yields
    /// exactly the dates already posted, and the rest of the series continues from
    /// them. Nothing else changes:
    ///   - the end date stays — every old occurrence on or before it still is;
    ///   - the caps count posted entries, not dates, so an installment plan or a
    ///     `max_executions` limit has the same number left;
    ///   - skips are keyed by occurrence date, and the old dates are occurrences
    ///     again, so they keep applying.
    ///
    /// Touched only when the history says so: a stored day that differs from the
    /// start's, and more posted or skipped dates on the old series than on the new
    /// one. An item that starts on the 1st, one with no history (#817 is right for
    /// it), and one already used under the new rule are left alone. Running it again
    /// finds the day and the start agreeing, so it is a no-op.
    ///
    /// A stored day of 29–31 makes the old rule clamp in short months, which a start
    /// date cannot say (a start on 30 Jun recurs on the 30th). There the start goes
    /// to the first old occurrence on the stored day itself, provided every one
    /// before it was posted or skipped — so nothing still owed drops out of the
    /// series — and otherwise to the first one, accepting the shorter day.
    ///
    /// Mirrors the web's `repairQuarterlyStartDays` (`lib/db/core/repair-quarterly-start-day.ts`),
    /// which runs as its `2026-10-19` migration. Exposed so it can be tested directly:
    /// on a fresh database the migration is recorded as applied before a test could
    /// insert a template for it to find.
    static func repairQuarterlyStartDays(_ db: Database) throws {
        let skips = try ScheduledSkips.load(db)
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, frequency, day_of_month, start_date, end_date FROM scheduled_templates
             WHERE frequency IN ('quarterly','yearly')
            """)
        for r in rows {
            let id: String = r["id"]
            let rawStart = (r["start_date"] as String?) ?? ""
            let start = String(rawStart.prefix(10))
            guard isYMD(start), let startDay = Int(start.suffix(2)) else { continue }
            // The old rule read NULL as 1 and 0 as "the start's day".
            let stored = (r["day_of_month"] as Int?) ?? 1
            let oldDay = stored == 0 ? startDay : stored
            if oldDay == startDay || oldDay < 1 { continue }

            let posted = try String.fetchAll(db, sql: """
                SELECT COALESCE(occurrence_date, date) FROM entries WHERE source_template_id = ?
                """, arguments: [id])
            let history = Set(posted).union(skips[id] ?? [])
            guard let through = history.max() else { continue }

            let frequency: String = r["frequency"]
            let endDate: String? = r["end_date"]
            let old = legacyMonthStepOccurrences(start: start, day: oldDay,
                                                 stepMonths: frequency == "quarterly" ? 3 : 12,
                                                 endDate: endDate, through: through)
            let current = Set(Selectors.recurrenceUpTo(ScheduledTemplate(
                id: id, name: "", type: "expense", frequency: frequency, dayOfMonth: stored,
                accountId: "", startDate: start, endDate: endDate, nextRun: ""), through))
            let oldSet = Set(old)
            let onOld = history.filter { oldSet.contains($0) && !current.contains($0) }.count
            let onNew = history.filter { current.contains($0) && !oldSet.contains($0) }.count
            guard onOld > onNew, let first = old.first else { continue }

            var anchor = first
            if let i = old.firstIndex(where: { Int($0.suffix(2)) == oldDay }),
               old[..<i].allSatisfy(history.contains) {
                anchor = old[i]
            }
            // Keep anything after the day (a web row may store "yyyy-MM-ddTHH:mm").
            try db.execute(sql: """
                UPDATE scheduled_templates SET start_date = ?, day_of_month = ?, updated_at = datetime('now')
                 WHERE id = ?
                """, arguments: [anchor + rawStart.dropFirst(10), Int(anchor.suffix(2)), id])
        }
    }

    /// The pre-#817 recurrence for quarterly and yearly items: whole steps of months
    /// from the start's month, each on `day` (clamped to the month's length), from
    /// the start through `through`, bounded by the end date.
    static func legacyMonthStepOccurrences(start: String, day: Int, stepMonths: Int,
                                           endDate: String?, through: String) -> [String] {
        let end = endDate.map { String($0.prefix(10)) }
        let limit = end.map { isYMD($0) && $0 < through ? $0 : through } ?? through
        guard var y = Int(start.prefix(4)), var m = Int(start.dropFirst(5).prefix(2)) else { return [] }
        func daysIn(_ y: Int, _ m: Int) -> Int {
            switch m {
            case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
            case 4, 6, 9, 11: return 30
            default: return 31
            }
        }
        var out: [String] = []
        for _ in 0..<1200 {
            let d = String(format: "%04d-%02d-%02d", y, m, Swift.min(day, daysIn(y, m)))
            if d > limit { break }
            if d >= start { out.append(d) }
            m += stepMonths
            while m > 12 { m -= 12; y += 1 }
        }
        return out
    }
}
