import SwiftUI
import FinchCore

/// Month-grid calendar lens for the Scheduled tab: per-day occurrence dots + a
/// selected-day detail (status + post/edit) with an "Upcoming" fallback.
/// Mutations route through the parent's closures; expansion via Selectors.
struct ScheduledCalendarView: View {
    @EnvironmentObject private var store: FinchStore
    /// Templates to plot — already narrowed by the Scheduled tab's search query.
    var templates: [ScheduledTemplate]
    var onEdit: (ScheduledTemplate) -> Void
    /// (template, occurrence date) — the tapped CELL's date, not today. Posting
    /// has to record which occurrence it fulfils or the badge never flips.
    var onPost: (ScheduledTemplate, String) -> Void
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
                VStack(spacing: 12) {
                    header
                    weekdayRow
                    #if os(iOS)
                    // Interactive month paging: prev/current/next are REAL pages in
                    // a .page TabView, so the neighboring month follows the finger
                    // (an after-the-fact .transition can't do that). On settle,
                    // commit the month and snap back to center animation-free.
                    TabView(selection: $pagerIndex) {
                        monthPage(offsetFromAnchor: -1).tag(-1)
                        monthPage(offsetFromAnchor: 0).tag(0)
                        monthPage(offsetFromAnchor: 1).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: Self.gridHeight)
                    .onChange(of: pagerIndex) { _, idx in
                        guard idx != 0 else { return }
                        monthAnchor = AppDate.civil.date(byAdding: .month, value: idx, to: monthAnchor) ?? monthAnchor
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { pagerIndex = 0 }
                    }
                    #else
                    monthPage(offsetFromAnchor: 0)
                    #endif
                }
            }
            Section {
                detail(byDay: byDay, posted: posted)
            }
        }
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

    /// Constant grid height: always 6 padded weeks (44pt cells, 4pt spacing) so
    /// the three carousel pages align and paging never jumps vertically.
    static let gridHeight: CGFloat = 6 * 44 + 5 * 4

    /// One month's grid, self-contained (computes its own occurrence map) so the
    /// carousel's prev/next pages render their own real content.
    private func monthPage(offsetFromAnchor: Int) -> some View {
        let m = AppDate.civil.date(byAdding: .month, value: offsetFromAnchor, to: monthAnchor) ?? monthAnchor
        let year = AppDate.civil.component(.year, from: m)
        let month = AppDate.civil.component(.month, from: m)
        let days = AppDate.civil.range(of: .day, in: .month, for: m)?.count ?? 30
        let firstWeekday = AppDate.civil.component(.weekday, from: m) - 1
        func iso(_ day: Int) -> String { String(format: "%04d-%02d-%02d", year, month, day) }
        let byDay = Dictionary(grouping: Selectors.occurrencesInRange(templates, from: iso(1), through: iso(days)), by: { $0.date })
        // One ordered cell list (leading nils pad to the 1st's weekday, then the
        // days, then trailing nils to a constant 42 cells) rendered by a single
        // ForEach — keeps blanks and days in lockstep so the columns stay aligned.
        var cells: [Int?] = Array(repeating: nil, count: firstWeekday) + (1...days).map(Optional.init)
        cells += Array(repeating: nil, count: 42 - cells.count)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, iso: iso(day), occ: byDay[iso(day)] ?? [])
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }

    private func dayCell(_ day: Int, iso d: String, occ: [(date: String, template: ScheduledTemplate)]) -> some View {
        let isSel = d == selectedDay, isToday = d == store.wallToday
        return VStack(spacing: 3) {
            // Today gets a filled accent circle (white number); other days plain.
            Text("\(day)")
                .font(.callout).fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            HStack(spacing: 2) {
                ForEach(Array(occ.prefix(3).enumerated()), id: \.offset) { _, o in
                    Circle().fill(Color(hex: o.template.color ?? "") ?? .accentColor).frame(width: 6, height: 6)
                }
                if occ.count > 3 { Text("+\(occ.count - 3)").font(.system(size: 8)).foregroundStyle(.secondary) }
            }.frame(height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSel ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = (selectedDay == d ? nil : d) }
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
            Text("Upcoming").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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
                if let amt = t.amount { Text(store.displayMoney(amt, from: acct?.currency ?? store.displayCurrency)).font(.callout) }
                statusBadge(st)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onEdit(t) } label: { Label("Edit", systemImage: "pencil") }
            // Unposted either way — a missed occurrence needs this more than an upcoming one.
            if st == .upcoming || st == .missed { Button { onPost(t, date) } label: { Label("Post now", systemImage: "checkmark.circle") } }
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
        // and recenters. (Chevrons get the same slide as a swipe.)
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
