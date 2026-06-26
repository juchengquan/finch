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
    var onPost: (ScheduledTemplate) -> Void
    var onAdd: (Date) -> Void

    @State private var monthAnchor: Date = ScheduledCalendarView.firstOfMonth(forISO: nil)
    @State private var selectedDay: String?
    @State private var showingMonthYearPicker = false

    private static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private static let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    static func firstOfMonth(forISO iso: String?) -> Date {
        let base = iso.flatMap { AppDate.isoDay.date(from: $0) } ?? Date()
        let c = utc.dateComponents([.year, .month], from: base)
        return utc.date(from: c) ?? base
    }

    private var year: Int { Self.utc.component(.year, from: monthAnchor) }
    private var month: Int { Self.utc.component(.month, from: monthAnchor) }
    private var daysInMonth: Int { Self.utc.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30 }
    private var firstWeekday: Int { Self.utc.component(.weekday, from: monthAnchor) - 1 }  // 0=Sun
    private func iso(_ day: Int) -> String { String(format: "%04d-%02d-%02d", year, month, day) }
    private var monthLabel: String { let f = DateFormatter(); f.calendar = Self.utc; f.timeZone = Self.utc.timeZone; f.dateFormat = "LLLL yyyy"; return f.string(from: monthAnchor) }

    var body: some View {
        let monthStart = iso(1), monthEnd = iso(daysInMonth)
        let byDay = Dictionary(grouping: Selectors.occurrencesInRange(templates, from: monthStart, through: monthEnd), by: { $0.date })
        let posted = Selectors.scheduledPostedMap(store.txns)
        return List {
            // The month grid sits in its own section card (one row, so no internal
            // separators); the day-detail / upcoming list follows as a second section.
            Section {
                VStack(spacing: 12) {
                    header
                    weekdayRow
                    grid(byDay: byDay)
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
            Button("Today") { monthAnchor = Self.firstOfMonth(forISO: store.today); selectedDay = store.today }
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
        let base = Int(store.today.prefix(4)) ?? year
        return Array(min(base - 10, year)...max(base + 10, year))
    }
    private func monthName(_ m: Int) -> String {
        let f = DateFormatter(); f.calendar = Self.utc
        return f.standaloneMonthSymbols[m - 1]
    }
    private func setMonthYear(month m: Int, year y: Int) {
        var c = DateComponents(); c.year = y; c.month = m; c.day = 1
        if let d = Self.utc.date(from: c) { monthAnchor = d }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(byDay: [String: [(date: String, template: ScheduledTemplate)]]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<firstWeekday, id: \.self) { _ in Color.clear.frame(height: 44) }
            ForEach(1...daysInMonth, id: \.self) { day in dayCell(day, occ: byDay[iso(day)] ?? []) }
        }
    }

    private func dayCell(_ day: Int, occ: [(date: String, template: ScheduledTemplate)]) -> some View {
        let d = iso(day)
        let isSel = d == selectedDay, isToday = d == store.today
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
            let end = Self.utc.date(byAdding: .day, value: 90, to: AppDate.isoDay.date(from: store.today) ?? Date()).map { AppDate.isoDay.string(from: $0) } ?? store.today
            let up = Array(Selectors.occurrencesInRange(templates, from: store.today, through: end).prefix(20))
            if up.isEmpty { Text("No upcoming items.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            else { ForEach(Array(up.enumerated()), id: \.offset) { _, o in occurrenceRow(o.template, date: o.date, posted: posted) } }
        }
    }

    private func occurrenceRow(_ t: ScheduledTemplate, date: String, posted: [String: Bool]) -> some View {
        let st = status(t.id, date, posted)
        let acct = store.accounts.first { $0.id == t.accountId }
        return HStack {
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
        .contextMenu {
            Button { onEdit(t) } label: { Label("Edit", systemImage: "pencil") }
            if st == .upcoming { Button { onPost(t) } label: { Label("Post now", systemImage: "checkmark.circle") } }
        }
    }

    private enum OccStatus { case upcoming, pending, done }
    private func status(_ id: String, _ date: String, _ posted: [String: Bool]) -> OccStatus {
        switch posted["\(id)|\(date)"] { case .none: return .upcoming; case .some(true): return .pending; case .some(false): return .done }
    }
    @ViewBuilder private func statusBadge(_ s: OccStatus) -> some View {
        let (label, color): (String, Color) = {
            switch s { case .upcoming: return ("upcoming", .secondary); case .pending: return ("pending", .orange); case .done: return ("done", .green) }
        }()
        Text(label).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundStyle(color).clipShape(Capsule())
    }

    private func step(_ n: Int) { if let d = Self.utc.date(byAdding: .month, value: n, to: monthAnchor) { monthAnchor = d } }
    private func pretty(_ iso: String) -> String {
        guard let d = AppDate.isoDay.date(from: iso) else { return iso }
        let f = DateFormatter(); f.calendar = Self.utc; f.timeZone = Self.utc.timeZone; f.dateFormat = "EEE, MMM d"; return f.string(from: d)
    }
}
