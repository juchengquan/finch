import SwiftUI
import FinchCore

/// Month-grid calendar lens for the Scheduled tab: per-day daily cash lines
/// (past/today = actual income/expense, future = scheduled totals), + a
/// selected-day detail (status + post/edit) that falls back to the untitled
/// upcoming list. Mutations route through the parent's closures; expansion
/// via Selectors.
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

    @State private var monthAnchor: Date = ScheduledCalendarView.firstOfMonth(forISO: nil)
    /// 3-page carousel position (-1/0/+1 around monthAnchor). A settled swipe
    /// commits the month and snaps back to 0 without animation (a TabView over
    /// ALL months would build every page eagerly — the carousel keeps it at 3).
    @State private var pagerIndex = 0
    @State private var selectedDay: String?
    @State private var showingMonthYearPicker = false

    private static let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    static func firstOfMonth(forISO iso: String?) -> Date {
        let base = iso.flatMap { AppDate.isoDay.date(from: $0) } ?? Date()
        let c = AppDate.civil.dateComponents([.year, .month], from: base)
        return AppDate.civil.date(from: c) ?? base
    }

    private var year: Int { AppDate.civil.component(.year, from: monthAnchor) }
    private var month: Int { AppDate.civil.component(.month, from: monthAnchor) }
    private var daysInMonth: Int { AppDate.civil.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30 }
    private var firstWeekday: Int { AppDate.civil.component(.weekday, from: monthAnchor) - 1 }  // 0=Sun
    private func iso(_ day: Int) -> String { String(format: "%04d-%02d-%02d", year, month, day) }
    private var monthLabel: String { let f = DateFormatter(); f.calendar = AppDate.civil; f.timeZone = AppDate.civil.timeZone; f.dateFormat = "LLLL yyyy"; return f.string(from: monthAnchor) }

    var body: some View {
        let monthStart = iso(1), monthEnd = iso(daysInMonth)
        let byDay = Dictionary(grouping: Selectors.occurrencesInRange(templates, from: monthStart, through: monthEnd), by: { $0.date })
        let posted = Selectors.scheduledPostedMap(store.txns)
        return List {
            if let topRow { topRow }
            // The month grid sits in its own section card (one row, so no internal
            // separators); the day-detail / upcoming list follows as a second section.
            Section {
                VStack(spacing: 16) {
                    header
                    weekdayRow
                    #if os(iOS)
                    // Interactive month paging: prev/current/next are REAL pages in
                    // a .page TabView, so the neighboring month follows the finger
                    // (an after-the-fact .transition can't do that). On settle,
                    // commit the month and snap back to center animation-free.
                    TabView(selection: $pagerIndex) {
                        monthPage(for: month(-1)).tag(-1)
                        monthPage(for: monthAnchor).tag(0)
                        monthPage(for: month(1)).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: Self.gridHeight)
                    // Recreate the pager after every commit: the settle's snap-back
                    // left the old pager's in-flight completion alive, and it would
                    // re-emit the selection write on top of the recentered state —
                    // advancing TWO months per swipe/chevron. A fresh pager (new
                    // identity per anchored month) has nothing in flight.
                    .id(Self.monthIndex(monthAnchor))
                    .onChange(of: pagerIndex) { _, idx in
                        guard idx != 0 else { return }
                        monthAnchor = month(idx)
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { pagerIndex = 0 }
                    }
                    #else
                    monthPage(for: monthAnchor)
                    #endif
                }
            }
            Section {
                detail(byDay: byDay, posted: posted)
            }
        }
        .resetsSwipeOnNavigation()
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Tappable month-year → wheel pickers (jump months/years quickly).
            Button { showingMonthYearPicker = true } label: {
                HStack(spacing: 4) {
                    Text(monthLabel).font(.headline)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Month and year")
            .popover(isPresented: $showingMonthYearPicker) { monthYearPicker }
            Spacer()
            // .borderless so each button is its own tap target inside the List
            // row (default-styled buttons in a List row fire together / not at all).
            Button("Today") { monthAnchor = Self.firstOfMonth(forISO: store.wallToday); selectedDay = store.wallToday }
                .font(.caption)
                .buttonStyle(.borderless)
            // Prev/next grouped together, to the right of the year-month.
            HStack(spacing: 16) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month").buttonStyle(.borderless)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month").buttonStyle(.borderless)
            }
        }
    }

    /// Side-by-side month + year wheels, shown as a popover from the header.
    /// Both write straight back to `monthAnchor` so the grid updates live.
    private var monthYearPicker: some View {
        HStack(spacing: 0) {
            Picker("Month", selection: monthBinding) {
                ForEach(1...12, id: \.self) { m in Text(monthName(m)).tag(m) }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            #endif
            .frame(maxWidth: .infinity)
            Picker("Year", selection: yearBinding) {
                ForEach(yearRange, id: \.self) { y in Text(verbatim: String(y)).tag(y) }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            #endif
            .frame(maxWidth: .infinity)
        }
        .labelsHidden()
        .frame(width: 300, height: 200)
        .presentationCompactAdaptation(.popover)
    }

    private var monthBinding: Binding<Int> {
        Binding(get: { month }, set: { setMonthYear(month: $0, year: year) })
    }
    private var yearBinding: Binding<Int> {
        Binding(get: { year }, set: { setMonthYear(month: month, year: $0) })
    }
    /// Year wheel range: ±10 around today, always widened to include the
    /// currently-anchored year (in case the user paged far via the chevrons).
    private var yearRange: [Int] {
        let base = Int(store.wallToday.prefix(4)) ?? year
        return Array(min(base - 10, year)...max(base + 10, year))
    }
    private func monthName(_ m: Int) -> String {
        let f = DateFormatter(); f.calendar = AppDate.civil
        return f.standaloneMonthSymbols[m - 1]
    }
    private func setMonthYear(month m: Int, year y: Int) {
        var c = DateComponents(); c.year = y; c.month = m; c.day = 1
        if let d = AppDate.civil.date(from: c) { monthAnchor = d }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    /// Week rows a month actually needs (5 for most, 4 or 6 at the extremes).
    static func weekRows(firstWeekday: Int, days: Int) -> Int { (firstWeekday + days + 6) / 7 }
    /// CONSTANT grid height (a 6-week month at 62pt cells + 4pt spacing) so every
    /// month — and all three carousel pages — render the same height: no layout
    /// jump when paging. Months with fewer weeks stretch their rows to fill
    /// (`cellHeight(rows:)`) instead of carrying an empty padded week.
    static let gridHeight: CGFloat = 6 * 62 + 5 * 4
    static func cellHeight(rows: Int) -> CGFloat { (gridHeight - 4 * CGFloat(rows - 1)) / CGFloat(rows) }

    /// Absolute month index (year*12+month, civil calendar) — the pager's
    /// per-month identity for the `.id` recreation above.
    static func monthIndex(_ d: Date) -> Int {
        let c = AppDate.civil.dateComponents([.year, .month], from: d)
        return (c.year ?? 2000) * 12 + (c.month ?? 1) - 1
    }
    /// The anchor month shifted by `off` months.
    private func month(_ off: Int) -> Date {
        AppDate.civil.date(byAdding: .month, value: off, to: monthAnchor) ?? monthAnchor
    }

    /// One month's grid, self-contained (computes its own occurrence map) so the
    /// carousel's prev/next pages render their own real content.
    private func monthPage(for m: Date) -> some View {
        let year = AppDate.civil.component(.year, from: m)
        let month = AppDate.civil.component(.month, from: m)
        let days = AppDate.civil.range(of: .day, in: .month, for: m)?.count ?? 30
        let firstWeekday = AppDate.civil.component(.weekday, from: m) - 1
        func iso(_ day: Int) -> String { String(format: "%04d-%02d-%02d", year, month, day) }
        let byDay = Dictionary(grouping: Selectors.occurrencesInRange(templates, from: iso(1), through: iso(days)), by: { $0.date })
        // Daily cash lines: past/today cells show the day's ACTUAL inflow/outflow
        // (same sign-split as the Activity month headers); future cells show the
        // day's SCHEDULED totals — facts behind, plan ahead.
        let actualByDay = MonthGrouping.dailyIncomeExpense(store.txns.filter { $0.date >= iso(1) && $0.date <= iso(days) })
        var schedByDay: [String: (income: Double, expense: Double)] = [:]
        for (d, occs) in byDay where d > store.wallToday {
            var inc = 0.0, exp = 0.0
            for o in occs {
                // Template amounts are unsigned magnitudes; `type` carries the
                // direction (unlike Tx.amount, which is signed). Transfers move
                // between the user's own accounts — neither income nor expense.
                guard let amt = o.template.amount else { continue }
                let base = abs(store.toBase(amt, from: store.accounts.first { $0.id == o.template.accountId }?.currency))
                switch o.template.type {
                case "income":  inc += base
                case "expense": exp += base
                default: break
                }
            }
            if inc > 0 || exp > 0 { schedByDay[d] = (inc, exp) }
        }
        // One ordered cell list (leading nils pad to the 1st's weekday, then the
        // days, then trailing nils to fill the month's own last week) rendered by
        // a single ForEach — keeps blanks and days in lockstep, columns aligned.
        let rows = Self.weekRows(firstWeekday: firstWeekday, days: days)
        let cellH = Self.cellHeight(rows: rows)
        var cells: [Int?] = Array(repeating: nil, count: firstWeekday) + (1...days).map(Optional.init)
        cells += Array(repeating: nil, count: rows * 7 - cells.count)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let d = iso(day)
                    let future = d > store.wallToday
                    dayCell(day, iso: d,
                            amounts: future ? schedByDay[d] : actualByDay[d],
                            height: cellH)
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: cellH)
                }
            }
        }
    }

    private func dayCell(_ day: Int, iso d: String,
                         amounts: (income: Double, expense: Double)?, height: CGFloat) -> some View {
        let isSel = d == selectedDay, isToday = d == store.wallToday
        return VStack(spacing: 2) {
            // Today gets a filled accent circle (white number); other days plain.
            Text("\(day)")
                .font(.callout).fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            // Fixed-height two-line slot (rows align whether or not a day has
            // amounts). Exact figures (cents only when non-zero), sign-prefixed;
            // nil from displayExactBase (privacy mode) drops the lines. Future days use
            // the SAME standard green/red as actuals — the dimmed variant read
            // as extra colors, and the today circle already splits fact from plan.
            VStack(spacing: 0) {
                if let a = amounts {
                    if a.income > 0, let s = store.displayExactBase(a.income) { amountLine("+" + s, .green) }
                    if a.expense > 0, let s = store.displayExactBase(a.expense) { amountLine("−" + s, .red) }
                }
            }
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(isSel ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = (selectedDay == d ? nil : d) }
    }

    /// One amount line, in a uniform full-cell-width box: every cell's amount
    /// gets the same maximum width, and a number that exceeds it shrinks its
    /// font to fit instead of spilling into the neighboring column.
    private func amountLine(_ s: String, _ color: Color) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func detail(byDay: [String: [(date: String, template: ScheduledTemplate)]], posted: [String: Bool]) -> some View {
        if let day = selectedDay {
            HStack {
                Text(pretty(day)).font(.headline)
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

    private func step(_ n: Int) {
        #if os(iOS)
        // Animate the carousel to the neighbor; its onChange commits the month
        // and recreates the pager. (Chevrons get the same slide as a swipe.)
        withAnimation(.easeInOut(duration: 0.25)) { pagerIndex = n }
        #else
        guard let d = AppDate.civil.date(byAdding: .month, value: n, to: monthAnchor) else { return }
        monthAnchor = d
        #endif
    }
    private func pretty(_ iso: String) -> String {
        guard let d = AppDate.isoDay.date(from: iso) else { return iso }
        let f = DateFormatter(); f.calendar = AppDate.civil; f.timeZone = AppDate.civil.timeZone; f.dateFormat = "EEE, MMM d"; return f.string(from: d)
    }
}
