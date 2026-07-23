import SwiftUI
import FinchCore

/// Month-grid calendar lens for the Scheduled tab — PLAN-only semantics: every
/// day cell (past and future alike) shows the day's SCHEDULED income/expense
/// totals, never actual transactions (those belong to Activity's calendar
/// lens). Below the grid: a selected-day detail (status + post/edit) that
/// falls back to the untitled upcoming list. Mutations route through the
/// parent's closures; expansion via Selectors; the grid itself is the shared
/// `MonthCashCalendar`.
struct ScheduledCalendarView: View {
    @EnvironmentObject private var store: FinchStore
    /// Templates to plot — already narrowed by the Scheduled tab's search query.
    var templates: [ScheduledTemplate]
    var onEdit: (ScheduledTemplate) -> Void
    /// (template, occurrence date) — the tapped CELL's date, not today. Posting
    /// has to record which occurrence it fulfils or the badge never flips.
    var onPost: (ScheduledTemplate, String) -> Void
    var onDelete: (ScheduledTemplate) -> Void
    var onAdd: (Date) -> Void
    /// Non-nil → a row TAP selects the template (iPad three-column mode) while
    /// the context menu's "Edit" still edits; nil → taps edit (compact behavior).
    var onSelect: ((ScheduledTemplate) -> Void)? = nil
    /// Optional row rendered above the month card (the Scheduled tab passes its
    /// Calendar/List mode picker) so the toggle lives inside THIS List — keeping
    /// the List the nav stack's primary scroll view for large-title collapse.
    var topRow: AnyView? = nil

    @State private var monthAnchor: Date = MonthCashCalendar.firstOfMonth(forISO: nil)
    @State private var selectedDay: String?

    /// The anchored month's inclusive ISO range (for the detail's occurrence map).
    private var monthRange: (start: String, end: String) {
        let y = AppDate.civil.component(.year, from: monthAnchor)
        let m = AppDate.civil.component(.month, from: monthAnchor)
        let days = AppDate.civil.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        return (String(format: "%04d-%02d-01", y, m), String(format: "%04d-%02d-%02d", y, m, days))
    }

    var body: some View {
        let range = monthRange
        let byDay = Dictionary(grouping: Selectors.occurrencesInRange(templates, from: range.start, through: range.end), by: { $0.date })
        let posted = Selectors.scheduledPostedMap(store.txns)
        return List {
            if let topRow { topRow }
            // The month grid sits in its own section card (one row, so no internal
            // separators); the day-detail / upcoming list follows as a second section.
            Section {
                MonthCashCalendar(
                    monthAnchor: $monthAnchor, selectedDay: $selectedDay,
                    wallToday: store.wallToday,
                    amountsForRange: scheduledAmounts,
                    format: { store.displayExactBase($0) })
            }
            Section {
                detail(byDay: byDay, posted: posted)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    /// Per-day SCHEDULED totals for the range — the calendar's plan-only cash
    /// lines. Template amounts are unsigned magnitudes; `type` carries the
    /// direction (unlike Tx.amount, which is signed). Transfers move between
    /// the user's own accounts — neither income nor expense.
    private func scheduledAmounts(from: String, through: String) -> [String: (income: Double, expense: Double)] {
        var out: [String: (income: Double, expense: Double)] = [:]
        let byDay = Dictionary(grouping: Selectors.occurrencesInRange(templates, from: from, through: through), by: { $0.date })
        for (d, occs) in byDay {
            var inc = 0.0, exp = 0.0
            for o in occs {
                guard let amt = o.template.amount else { continue }
                let base = abs(store.toBase(amt, from: store.accounts.first { $0.id == o.template.accountId }?.currency))
                switch o.template.type {
                case "income":  inc += base
                case "expense": exp += base
                default: break
                }
            }
            if inc > 0 || exp > 0 { out[d] = (inc, exp) }
        }
        return out
    }

    @ViewBuilder private func detail(byDay: [String: [(date: String, template: ScheduledTemplate)]], posted: [String: Bool]) -> some View {
        if let day = selectedDay {
            HStack {
                Text(MonthCashCalendar.pretty(day)).font(.headline)
                Spacer()
                Button { onAdd(AppDate.isoDay.date(from: day) ?? Date()) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add scheduled on this day")
            }
            let occ = byDay[day] ?? []
            if occ.isEmpty { Text("Nothing scheduled.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            else { ForEach(occ, id: \.template.id) { o in occurrenceRow(o.template, date: day, posted: posted) } }
        } else {
            let end = AppDate.civil.date(byAdding: .day, value: 90, to: AppDate.isoDay.date(from: store.wallToday) ?? Date()).map { AppDate.isoDay.string(from: $0) } ?? store.wallToday
            let up = Array(Selectors.occurrencesInRange(templates, from: store.wallToday, through: end).prefix(20))
            if up.isEmpty { Text("No upcoming items.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            else { ForEach(Array(up.enumerated()), id: \.offset) { _, o in occurrenceRow(o.template, date: o.date, posted: posted) } }
        }
    }

    private func occurrenceRow(_ t: ScheduledTemplate, date: String, posted: [String: Bool]) -> some View {
        let st = status(t.id, date, posted)
        let acct = store.accounts.first { $0.id == t.accountId }
        // Tap the row to edit the template (or select it, in three-column mode);
        // long-press still offers Edit / Post now — Edit always opens the editor.
        // .plain so it reads as a row, not a button.
        return Button { (onSelect ?? onEdit)(t) } label: {
            HStack {
                Circle().fill(Color(hex: t.color ?? "") ?? .accentColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name)
                    Text("\(date) · \(acct?.name ?? "—")").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                // Badge BEFORE the amount: the amount owns the trailing edge, so
                // rows align with each other and with the List view — a trailing
                // badge's variable width ("upcoming" vs "missed") shifted every
                // amount a different distance from the edge.
                statusBadge(st)
                if let amt = t.amount { Text(store.displayMoney(amt, from: acct?.currency ?? store.displayCurrency)).font(.callout) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // TxRow density: default insets made this two-line row 65pt, over the 60pt
        // point where iOS renders swipe actions as circles with the label outside.
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        // Swipe actions mirror the List view: trailing Delete + Edit (Edit at the
        // trailing edge), leading Post (only while the occurrence is still upcoming).
        .swipeActions(edge: .trailing) {
            Button { onEdit(t) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
            Button { onDelete(t) } label: { Label("Delete", systemImage: "trash") }.tint(.red)
        }
        .swipeActions(edge: .leading) {
            // Unposted either way — a missed occurrence needs Post more than an upcoming one.
            // Same occurrence-aware call as the context menu: this row IS a cell, so
            // `date` is the occurrence being posted — passing the template alone would
            // stamp today and leave the badge unchanged (the bug this branch fixes).
            if st == .upcoming || st == .missed { Button { onPost(t, date) } label: { Label("Post", systemImage: "checkmark.circle") }.tint(.green) }
        }
        .contextMenu {
            Button { onEdit(t) } label: { Label("Edit", systemImage: "pencil") }
            // Unposted either way — a missed occurrence needs this more than an upcoming one.
            if st == .upcoming || st == .missed { Button { onPost(t, date) } label: { Label("Post now", systemImage: "checkmark.circle") } }
            Button(role: .destructive) { onDelete(t) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private enum OccStatus { case upcoming, missed, pending, done }
    /// No posting record means "nobody posted this yet" — which is only `upcoming`
    /// while the date is still ahead. A past occurrence nobody posted is `missed`,
    /// and it's the state that most needs action. Both are ISO `yyyy-MM-dd`, so a
    /// string compare is a date compare. `wallToday`, not `today`: this is a literal
    /// "has it happened yet" question, not a data-anchored one.
    private func status(_ id: String, _ date: String, _ posted: [String: Bool]) -> OccStatus {
        switch posted["\(id)|\(date)"] {
        case .some(true): return .pending
        case .some(false): return .done
        case .none: return date < store.wallToday ? .missed : .upcoming
        }
    }
    @ViewBuilder private func statusBadge(_ s: OccStatus) -> some View {
        // LocalizedStringKey, not String — a String binds Text's non-localizing init.
        let (label, color): (LocalizedStringKey, Color) = {
            switch s {
            case .upcoming: return ("upcoming", .secondary)
            case .missed:   return ("missed", .red)
            case .pending:  return ("pending", .orange)
            case .done:     return ("done", .green)
            }
        }()
        Text(label).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundStyle(color).clipShape(Capsule())
    }
}
