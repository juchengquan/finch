import SwiftUI

/// The shared month-grid cash calendar: header (tappable month-year wheels +
/// Today + chevrons), weekday row, and a finger-following 3-page month carousel
/// whose day cells carry up to two exact amount lines (income green, expense
/// red; cents only when non-zero). The SEMANTICS of the amounts belong to the
/// caller — the Scheduled tab feeds scheduled totals, Activity feeds actual
/// transaction totals — via `amountsForRange`. The parent owns `monthAnchor`
/// and `selectedDay` so its detail sections can follow the grid.
struct MonthCashCalendar: View {
    @Binding var monthAnchor: Date
    @Binding var selectedDay: String?
    /// The literal current day (`store.wallToday`) — drives the filled today
    /// circle, the Today button, and the year-wheel range.
    let wallToday: String
    /// Per-day cash lines for the inclusive ISO range (called once per rendered
    /// month page — the carousel renders three).
    let amountsForRange: (_ from: String, _ through: String) -> [String: (income: Double, expense: Double)]
    /// Formats a magnitude for a cell line; nil drops the line (privacy mode).
    let format: (Double) -> String?

    /// 3-page carousel position (-1/0/+1 around monthAnchor). A settled swipe
    /// commits the month and snaps back to 0 without animation (a TabView over
    /// ALL months would build every page eagerly — the carousel keeps it at 3).
    @State private var pagerIndex = 0
    @State private var showingMonthYearPicker = false

    /// Locale-aware three-letter weekday row ("Sun Mon …"; 周日 周一 … in
    /// zh-Hans), Sunday-first to match the grid's weekday math.
    private static let weekdaySymbols: [String] = {
        let f = DateFormatter(); f.calendar = AppDate.civil
        return f.shortStandaloneWeekdaySymbols
    }()

    static func firstOfMonth(forISO iso: String?) -> Date {
        let base = iso.flatMap { AppDate.isoDay.date(from: $0) } ?? Date()
        let c = AppDate.civil.dateComponents([.year, .month], from: base)
        return AppDate.civil.date(from: c) ?? base
    }

    /// "2026-07-15" → "Wed, Jul 15" (device locale) — the selected-day headline
    /// both calling tabs use above their day-detail rows.
    static func pretty(_ iso: String) -> String {
        guard let d = AppDate.isoDay.date(from: iso) else { return iso }
        let f = DateFormatter(); f.calendar = AppDate.civil; f.timeZone = AppDate.civil.timeZone; f.dateFormat = "EEE, MMM d"; return f.string(from: d)
    }

    private var year: Int { AppDate.civil.component(.year, from: monthAnchor) }
    private var month: Int { AppDate.civil.component(.month, from: monthAnchor) }
    private var monthLabel: String { let f = DateFormatter(); f.calendar = AppDate.civil; f.timeZone = AppDate.civil.timeZone; f.dateFormat = "LLLL yyyy"; return f.string(from: monthAnchor) }

    var body: some View {
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
            Button("Today") { monthAnchor = Self.firstOfMonth(forISO: wallToday); selectedDay = wallToday }
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
        let base = Int(wallToday.prefix(4)) ?? year
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

    /// One month's grid, self-contained (fetches its own amounts map) so the
    /// carousel's prev/next pages render their own real content.
    private func monthPage(for m: Date) -> some View {
        let year = AppDate.civil.component(.year, from: m)
        let month = AppDate.civil.component(.month, from: m)
        let days = AppDate.civil.range(of: .day, in: .month, for: m)?.count ?? 30
        let firstWeekday = AppDate.civil.component(.weekday, from: m) - 1
        func iso(_ day: Int) -> String { String(format: "%04d-%02d-%02d", year, month, day) }
        let amounts = amountsForRange(iso(1), iso(days))
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
                    dayCell(day, iso: d, amounts: amounts[d], height: cellH)
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: cellH)
                }
            }
        }
    }

    private func dayCell(_ day: Int, iso d: String,
                         amounts: (income: Double, expense: Double)?, height: CGFloat) -> some View {
        let isSel = d == selectedDay, isToday = d == wallToday
        return VStack(spacing: 2) {
            // Today gets a filled accent circle (white number); other days plain.
            Text("\(day)")
                .font(.callout).fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            // Fixed-height two-line slot (rows align whether or not a day has
            // amounts). Exact figures (cents only when non-zero), sign-prefixed;
            // nil from `format` (privacy mode) drops the lines.
            VStack(spacing: 0) {
                if let a = amounts {
                    if a.income > 0, let s = format(a.income) { amountLine("+" + s, .green) }
                    if a.expense > 0, let s = format(a.expense) { amountLine("−" + s, .red) }
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
}
