import SwiftUI

/// The shared month-grid cash calendar: header (tappable month-year wheels +
/// Today + chevrons), weekday row, and a finger-following month carousel
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
    /// month page — the carousel keeps the visible month and its neighbours).
    let amountsForRange: (_ from: String, _ through: String) -> [String: (income: Double, expense: Double)]
    /// Formats a magnitude for a cell line; nil drops the line (privacy mode).
    let format: (Double) -> String?
    /// Privacy mode: cells trade their amount lines for presence dots. The
    /// caller owns the flag for the same reason it owns `format` — this view
    /// deliberately knows nothing about the store.
    let masked: Bool

    @State private var showingMonthYearPicker = false
    /// The month the carousel is over MID-DRAG — the header's label only, so the month
    /// name follows the finger and flips as the new month takes over half the screen.
    /// nil ⇒ not dragging, so the label follows the committed anchor.
    @State private var visibleIndex: Int? = nil

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
    /// both calling tabs use above their day-detail rows. The formatter is
    /// cached (main-thread only): DateFormatter() costs real milliseconds and
    /// this runs once per day-section header — allocating per call was a
    /// measurable slice of the calendar's first-frame cost on tab entry.
    private static let prettyFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = AppDate.civil; f.timeZone = AppDate.civil.timeZone; f.dateFormat = "EEE, MMM d"; return f
    }()
    static func pretty(_ iso: String) -> String {
        guard let d = AppDate.isoDay.date(from: iso) else { return iso }
        return prettyFormatter.string(from: d)
    }

    private var year: Int { AppDate.civil.component(.year, from: monthAnchor) }
    private var month: Int { AppDate.civil.component(.month, from: monthAnchor) }
    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = AppDate.civil; f.timeZone = AppDate.civil.timeZone; f.dateFormat = "LLLL yyyy"; return f
    }()
    /// Follows the finger: while a drag is in flight this is the month the carousel is
    /// over, not the one committed. The commit still waits for the gesture to end — see
    /// MonthPager — so this label is the ONLY thing that moves early.
    private var monthLabel: String {
        let date = visibleIndex.map(Self.date(fromMonthIndex:)) ?? monthAnchor
        return Self.monthLabelFormatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            // INLINE, not a popover/sheet. Every screen that shows this calendar
            // hosts it in a UIHostingConfiguration cell (Activity, account detail,
            // Scheduled), and a SwiftUI presentation from hosted cell content has
            // no presenting view controller — the popover this used to be flipped
            // its state and silently showed nothing. Expanding in place needs no
            // presentation context, so it works in every host, macOS included.
            // Guarded by CalendarMonthYearPickerUITests, which runs the HOSTED
            // calendar — keep it green before redesigning this control.
            // The wheels REPLACE the grid rather than pushing it down, which is what
            // the system's date picker does — showing wheels and a day grid at once
            // reads as two calendars. Collapsing brings the grid straight back.
            if showingMonthYearPicker {
                monthYearPicker
            } else {
                weekdayRow
                #if os(iOS)
                // Interactive month paging: the neighboring months are REAL pages, so
                // they follow the finger (an after-the-fact .transition can't do that).
                // Each page IS its month — see MonthPager for why the earlier
                // three-page-window-plus-recentre arrangement cost the animation.
                MonthPager(anchorIndex: monthIndexBinding, range: pageRange,
                           page: { index in monthPage(for: Self.date(fromMonthIndex: index)) },
                           visible: $visibleIndex)
                .frame(height: Self.gridHeight)
                // Chevrons, Today and the month-year wheels move the anchor directly; drop
                // the drag-time label so it follows the anchor again rather than sticking
                // on whatever the last drag was over.
                .onChange(of: monthAnchor) { _, _ in visibleIndex = nil }
                #else
                monthPage(for: monthAnchor)
                #endif
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Tappable month-year → inline wheel pickers (jump months/years
            // quickly). A TOGGLE: tap again to collapse.
            Button { withAnimation(.easeInOut(duration: 0.2)) { showingMonthYearPicker.toggle() } } label: {
                // Matches the system date picker's header: one chevron that turns to
                // point down while the wheels are open, and a tinted label with it.
                HStack(spacing: 4) {
                    Text(monthLabel).font(.headline)
                        // Tinted only while open — collapsed, the system leaves the
                        // month name in the label colour and tints just the chevron.
                        .foregroundStyle(showingMonthYearPicker ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary))
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .rotationEffect(.degrees(showingMonthYearPicker ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Month and year")
            // The label names the CONTROL, which left the anchored month itself
            // unspoken — VoiceOver read "Month and year, button" wherever you had
            // paged to. The value carries the month the grid is actually showing.
            .accessibilityValue(monthLabel)
            Spacer()
            // .borderless so each button is its own tap target inside the List
            // row (default-styled buttons in a List row fire together / not at all).
            Button("Today") { monthAnchor = Self.firstOfMonth(forISO: wallToday); selectedDay = wallToday }
                .font(.body)
                .buttonStyle(.borderless)
            // Prev/next grouped together, to the right of the year-month.
            HStack(spacing: 18) {
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.body.weight(.medium)) }
                    .accessibilityLabel("Previous month").buttonStyle(.borderless)
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.body.weight(.medium)) }
                    .accessibilityLabel("Next month").buttonStyle(.borderless)
            }
        }
    }

    /// Side-by-side month + year wheels, expanded INLINE below the header (see
    /// the body comment for why a presentation cannot work here). Both write
    /// straight back to `monthAnchor`, so the grid below follows live.
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
        #if os(iOS)
        .frame(height: 190)
        #endif
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

    /// Income / expense presence for one day — privacy mode's stand-in for the
    /// amount lines. Presence only: never magnitude, never a count.
    enum Mark: Hashable { case income, expense }

    /// Which presence dots a day cell draws. Empty unless masked: an unmasked
    /// cell draws real amount lines and never dots. Income first — its dot sits
    /// above the expense one, mirroring the line order it replaces.
    static func marks(income: Double, expense: Double, masked: Bool) -> [Mark] {
        guard masked else { return [] }
        var out: [Mark] = []
        if income > 0 { out.append(.income) }
        if expense > 0 { out.append(.expense) }
        return out
    }

    /// VoiceOver text for a masked cell. The dots are shapes — without this a
    /// screen reader would hear the day number and nothing else. Scoped to the
    /// masked branch on purpose: combining the whole cell's children would
    /// change how an UNMASKED cell reads, and privacy-off must change nothing.
    static func marksLabel(_ marks: [Mark]) -> Text? {
        if marks == [.income, .expense] { return Text("Income and spending") }
        if marks == [.income] { return Text("Income") }
        if marks == [.expense] { return Text("Spending") }
        return nil
    }

    /// Week rows a month actually needs (5 for most, 4 or 6 at the extremes).
    static func weekRows(firstWeekday: Int, days: Int) -> Int { (firstWeekday + days + 6) / 7 }
    /// CONSTANT grid height (a 6-week month at 62pt cells + 4pt spacing) so every
    /// month — and every carousel page — renders the same height: no layout
    /// jump when paging. Months with fewer weeks stretch their rows to fill
    /// (`cellHeight(rows:)`) instead of carrying an empty padded week.
    static let gridHeight: CGFloat = 6 * 62 + 5 * 4
    static func cellHeight(rows: Int) -> CGFloat { (gridHeight - 4 * CGFloat(rows - 1)) / CGFloat(rows) }

    /// Absolute month index (year*12+month, civil calendar) — one number per month,
    /// contiguous across year boundaries. This is the pager's page identity: a page
    /// knows its own month, so its neighbours are simply ±1.
    static func monthIndex(_ d: Date) -> Int {
        let c = AppDate.civil.dateComponents([.year, .month], from: d)
        return (c.year ?? 2000) * 12 + (c.month ?? 1) - 1
    }
    /// The anchored month as a page index, written back when a swipe settles. The
    /// carousel has no month state of its own — `monthAnchor` IS its position, so
    /// the two cannot drift apart mid-gesture.
    private var monthIndexBinding: Binding<Int> {
        Binding(get: { Self.monthIndex(monthAnchor) },
                set: { monthAnchor = Self.date(fromMonthIndex: $0) })
    }

    /// Months the carousel can reach: 50 years either side of today. Deliberately
    /// CONSTANT for a given `wallToday` — a range that grew as you paged would change
    /// the carousel's contents mid-swipe, which is the class of churn this pager
    /// exists to avoid. `LazyHStack` builds only the months on screen, so the span
    /// costs nothing; the bounds widen only for an anchor already outside it (data
    /// far in the past), where the alternative is a page that cannot be shown.
    private var pageRange: ClosedRange<Int> {
        let today = Self.monthIndex(Self.firstOfMonth(forISO: wallToday))
        let anchor = Self.monthIndex(monthAnchor)
        return min(today - 600, anchor - 1)...max(today + 600, anchor + 1)
    }

    /// `monthIndex` inverted — the first of the month that index names.
    static func date(fromMonthIndex i: Int) -> Date {
        var c = DateComponents()
        c.year = i / 12
        c.month = i % 12 + 1
        c.day = 1
        return AppDate.civil.date(from: c) ?? Date()
    }

    /// One month's grid, self-contained (fetches its own amounts map) so the
    /// carousel's neighbouring pages render their own real content.
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
        let marks = Self.marks(income: amounts?.income ?? 0,
                               expense: amounts?.expense ?? 0,
                               masked: masked)
        return VStack(spacing: 2) {
            // Today gets a filled accent circle (white number); other days plain.
            Text("\(day)")
                .font(.callout).fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            // Fixed-height two-line slot (rows align whether or not a day has
            // amounts). Privacy mode swaps the exact figures for presence dots
            // INSIDE the same slot — the grid must not shift when it toggles.
            Group {
                if masked {
                    VStack(spacing: 3) {
                        ForEach(marks, id: \.self) { dot($0) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.marksLabel(marks) ?? Text(verbatim: ""))
                    .accessibilityHidden(marks.isEmpty)
                } else {
                    // Exact figures (cents only when non-zero), sign-prefixed;
                    // nil from `format` drops the line. The VStack is rendered
                    // unconditionally — the `if let` must stay INSIDE it. Branch
                    // it away for a day with no amounts and the 32pt slot stops
                    // being reserved, so that cell's number re-centres ~13pt
                    // lower than its neighbours' and the whole row staggers.
                    VStack(spacing: 0) {
                        if let a = amounts {
                            if a.income > 0, let s = format(a.income) { amountLine("+" + s, .green) }
                            if a.expense > 0, let s = format(a.expense) { amountLine("−" + s, .red) }
                        }
                    }
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

    /// One presence dot — privacy mode's stand-in for an amount line. Fixed
    /// size on purpose: scaling it by amount would leak the magnitude the
    /// mask exists to hide.
    private func dot(_ mark: Mark) -> some View {
        Circle()
            .fill(mark == .income ? Color.green : Color.red)
            .frame(width: 6, height: 6)
    }

    /// Chevron step. One assignment on both platforms: on iOS the pager sees a
    /// ±1 change of anchor and slides to it itself, so the chevrons and a swipe
    /// share one path to the same animation.
    private func step(_ n: Int) {
        guard let d = AppDate.civil.date(byAdding: .month, value: n, to: monthAnchor) else { return }
        monthAnchor = d
    }
}
