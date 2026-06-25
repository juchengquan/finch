# Scheduled calendar view — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `List | Calendar` toggle to the Scheduled tab; the calendar shows a month grid with per-day occurrence dots, a selected-day detail with status (upcoming/pending/done) + post/edit, an Upcoming fallback, and day quick-add.

**Architecture:** No engine change. (1) FinchCore: project the existing `scheduled_templates.color`; add two pure selectors (`occurrencesInRange`, `scheduledPostedMap`) wrapping the existing `occurrencesUpTo`. (2) FinchApp: a `ScheduledCalendarView` + a mode toggle in `ScheduledTab`; `ScheduledSheet` gains an optional prefilled start date.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No engine/schema change.** Reuse `Selectors.occurrencesUpTo` (Forecast.swift:98) for expansion; derive status from `Tx.sourceTemplateId`/`Tx.pending`.
- Status: occurrence with no linked tx ⇒ **upcoming**; linked tx pending ⇒ **pending**; linked tx confirmed ⇒ **done**.
- Calendar: chevron month nav + **Today**; 7-col Sun–Sat grid; **max 3 colored dots + "+N"** per day; today ring; selected highlight.
- Day-detail quick-add opens `ScheduledSheet` with `startDate` prefilled to the selected day.
- **Toggle, not replace** — the existing List view is unchanged.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):** `ios/FinchCore/Sources/FinchCore/Selectors/Forecast.swift` (ScheduledTemplate.color + 2 selectors), `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` (project color).
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/ScheduledCalendarTests.swift`.
**Create (FinchApp):** `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift` (mode toggle), `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift` (prefillStart init param).

---

### Task 1: `color` projection + occurrence/status selectors

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Forecast.swift`
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/ScheduledCalendarTests.swift`

**Interfaces:**
- Produces: `ScheduledTemplate.color: String?` (projected); `Selectors.occurrencesInRange(_:from:through:) -> [(date: String, template: ScheduledTemplate)]`; `Selectors.scheduledPostedMap(_:) -> [String: Bool]`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/ScheduledCalendarTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class ScheduledCalendarTests: XCTestCase {
    private func tmpl(_ id: String, freq: String, start: String, end: String? = nil, dom: Int = 1) -> ScheduledTemplate {
        ScheduledTemplate(id: id, name: id, type: "expense", amount: 10, frequency: freq, dayOfMonth: dom,
                          accountId: "a1", startDate: start, endDate: end, nextRun: start)
    }

    func test_occurrencesInRange_monthly() {
        let t = tmpl("m", freq: "monthly", start: "2026-01-15", dom: 15)
        let occ = Selectors.occurrencesInRange([t], from: "2026-03-01", through: "2026-05-31").map(\.date)
        XCTAssertEqual(occ, ["2026-03-15", "2026-04-15", "2026-05-15"])
    }

    func test_occurrencesInRange_weekly_count_in_month() {
        let t = tmpl("w", freq: "weekly", start: "2026-06-01")   // Mondays-ish weekly from Jun 1
        let occ = Selectors.occurrencesInRange([t], from: "2026-06-01", through: "2026-06-30").map(\.date)
        XCTAssertEqual(occ, ["2026-06-01", "2026-06-08", "2026-06-15", "2026-06-22", "2026-06-29"])
    }

    func test_occurrencesInRange_once_and_bounds() {
        let once = tmpl("o", freq: "once", start: "2026-06-10")
        XCTAssertEqual(Selectors.occurrencesInRange([once], from: "2026-06-01", through: "2026-06-30").map(\.date), ["2026-06-10"])
        XCTAssertTrue(Selectors.occurrencesInRange([once], from: "2026-07-01", through: "2026-07-31").isEmpty)   // out of range
        let ended = tmpl("e", freq: "monthly", start: "2026-01-10", end: "2026-02-28", dom: 10)
        XCTAssertEqual(Selectors.occurrencesInRange([ended], from: "2026-01-01", through: "2026-06-30").map(\.date), ["2026-01-10", "2026-02-10"])   // respects endDate
    }

    func test_occurrencesInRange_sorted_across_templates() {
        let a = tmpl("a", freq: "monthly", start: "2026-06-20", dom: 20)
        let b = tmpl("b", freq: "monthly", start: "2026-06-05", dom: 5)
        XCTAssertEqual(Selectors.occurrencesInRange([a, b], from: "2026-06-01", through: "2026-06-30").map(\.date), ["2026-06-05", "2026-06-20"])
    }

    func test_scheduledPostedMap() {
        let txns = [
            Tx(id: "t1", merchant: "x", amount: -10, account: "a1", date: "2026-06-05", sourceTemplateId: "b", pending: false), // done
            Tx(id: "t2", merchant: "x", amount: -10, account: "a1", date: "2026-06-20", sourceTemplateId: "a", pending: true),  // pending
            Tx(id: "t3", merchant: "x", amount: -10, account: "a1", date: "2026-06-01"),                                        // no template
        ]
        let m = Selectors.scheduledPostedMap(txns)
        XCTAssertEqual(m["b|2026-06-05"], false)
        XCTAssertEqual(m["a|2026-06-20"], true)
        XCTAssertNil(m["x|2026-06-01"])
    }
}
```

(If `Tx(...)`'s positional init differs, mirror the initializer used in the existing `RulesEditingTests`/`FxSourceTests` test helpers — `Tx(id:merchant:amount:account:date:…)` with defaulted tails.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter ScheduledCalendarTests`
Expected: FAIL to compile — `occurrencesInRange`/`scheduledPostedMap` undefined; `ScheduledTemplate` init has no `color` (only if a test passes color — it doesn't, so the failure is the selectors).

- [ ] **Step 3: Add `color` to `ScheduledTemplate`**

In `Forecast.swift`, in the `ScheduledTemplate` struct: after `public let installmentPaid: Int?` add a field, extend the init signature, and assign it.

(a) field — replace:
```swift
    public let installmentPaid: Int?

    public init(id: String, name: String, description: String? = nil, type: String,
```
with:
```swift
    public let installmentPaid: Int?
    public let color: String?

    public init(id: String, name: String, description: String? = nil, type: String,
```

(b) init param — replace:
```swift
                installmentTotal: Int? = nil, installmentPaid: Int? = nil) {
```
with:
```swift
                installmentTotal: Int? = nil, installmentPaid: Int? = nil, color: String? = nil) {
```

(c) init body — replace:
```swift
        self.installmentTotal = installmentTotal
        self.installmentPaid = installmentPaid
    }
```
with:
```swift
        self.installmentTotal = installmentTotal
        self.installmentPaid = installmentPaid
        self.color = color
    }
```

- [ ] **Step 4: Project `color`**

In `Projections+State.swift`, the `scheduledTemplates` query:

(a) SELECT — replace `t.installment_total, COALESCE(p.n, 0) AS installment_paid` with `t.installment_total, t.color, COALESCE(p.n, 0) AS installment_paid`.

(b) map — replace `installmentTotal: r["installment_total"], installmentPaid: r["installment_paid"])` with `installmentTotal: r["installment_total"], installmentPaid: r["installment_paid"], color: r["color"])`.

- [ ] **Step 5: Add the two selectors**

In `Forecast.swift`, inside `extension Selectors { … }` (the block that contains `occurrencesUpTo` and `accountForecast`, closing brace ~line 234), add before that closing `}`:

```swift
    /// All occurrences of `templates` within [from, through] inclusive, each paired
    /// with its template, sorted by date. Reuses `occurrencesUpTo`.
    public static func occurrencesInRange(_ templates: [ScheduledTemplate], from: String, through: String)
        -> [(date: String, template: ScheduledTemplate)] {
        var out: [(date: String, template: ScheduledTemplate)] = []
        for t in templates {
            for d in occurrencesUpTo(t, through) where d >= from { out.append((d, t)) }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// "templateId|date" → isPending, for every posted occurrence (txns whose
    /// sourceTemplateId is set). Absent key ⇒ upcoming; true ⇒ pending; false ⇒ done.
    public static func scheduledPostedMap(_ txns: [Tx]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for t in txns { if let s = t.sourceTemplateId { out["\(s)|\(t.date)"] = (t.pending ?? false) } }
        return out
    }
```

- [ ] **Step 6: Run tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter ScheduledCalendarTests`
Expected: PASS (5 tests). If `weekly` expected dates differ, adjust the expectation to what `occurrencesUpTo` actually steps (weekly = +7 days from anchor); the point is the count/cadence within the month.

- [ ] **Step 7: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass (defaulted `color` keeps other `ScheduledTemplate(...)` call sites valid).

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Selectors/Forecast.swift \
        ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift \
        ios/FinchCore/Tests/FinchCoreTests/ScheduledCalendarTests.swift
git commit -m "feat(ios): project scheduled color + occurrencesInRange/scheduledPostedMap selectors"
```

---

### Task 2: Calendar view + `ScheduledTab` toggle

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift` (prefillStart)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift` (mode toggle)

**Interfaces:**
- Consumes: `ScheduledTemplate.color`, `Selectors.occurrencesInRange`, `Selectors.scheduledPostedMap` (Task 1); `store.scheduled`/`txns`/`today`/`accounts`/`displayMoney`/`displayCurrency`; `Color(hex:)`; `AppDate.isoDay`; `ScheduledSheet`.

- [ ] **Step 1: `ScheduledSheet` — optional prefilled start date**

In `WriteScreens/ScheduledSheet.swift`:

(a) replace `init(template: ScheduledTemplate? = nil) {` with `init(template: ScheduledTemplate? = nil, prefillStart: Date? = nil) {`

(b) replace the start-date initializer line
```swift
        _startDate = State(initialValue: template?.startDate.flatMap { AppDate.isoDay.date(from: $0) } ?? Date())
```
with
```swift
        _startDate = State(initialValue: template?.startDate.flatMap { AppDate.isoDay.date(from: $0) } ?? prefillStart ?? Date())
```

- [ ] **Step 2: Create `ScheduledCalendarView`**

Create `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift`:

```swift
import SwiftUI
import FinchCore

/// Month-grid calendar lens for the Scheduled tab: per-day occurrence dots + a
/// selected-day detail (status + post/edit) with an "Upcoming" fallback.
/// Mutations route through the parent's closures; expansion via Selectors.
struct ScheduledCalendarView: View {
    @EnvironmentObject private var store: FinchStore
    var onEdit: (ScheduledTemplate) -> Void
    var onPost: (ScheduledTemplate) -> Void
    var onAdd: (Date) -> Void

    @State private var monthAnchor: Date = ScheduledCalendarView.firstOfMonth(forISO: nil)
    @State private var selectedDay: String?

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
        let byDay = Dictionary(grouping: Selectors.occurrencesInRange(store.scheduled, from: monthStart, through: monthEnd), by: { $0.date })
        let posted = Selectors.scheduledPostedMap(store.txns)
        return ScrollView {
            VStack(spacing: 12) {
                header
                weekdayRow
                grid(byDay: byDay)
                Divider()
                detail(byDay: byDay, posted: posted)
            }
            .padding(.horizontal)
        }
    }

    private var header: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
            Spacer()
            Text(monthLabel).font(.headline)
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
            Button("Today") { monthAnchor = Self.firstOfMonth(forISO: store.today); selectedDay = store.today }
                .font(.caption)
        }
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
            Text("\(day)").font(.callout).foregroundStyle(isToday ? Color.accentColor : .primary)
            HStack(spacing: 2) {
                ForEach(Array(occ.prefix(3).enumerated()), id: \.offset) { _, o in
                    Circle().fill(Color(hex: o.template.color ?? "") ?? .accentColor).frame(width: 6, height: 6)
                }
                if occ.count > 3 { Text("+\(occ.count - 3)").font(.system(size: 8)).foregroundStyle(.secondary) }
            }.frame(height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSel ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isToday ? Color.accentColor : .clear, lineWidth: 1))
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
            let up = Array(Selectors.occurrencesInRange(store.scheduled, from: store.today, through: end).prefix(20))
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
```

- [ ] **Step 3: Wire the toggle into `ScheduledTab`**

Replace the `body` of `ScheduledTab` (and add the `Mode` enum + `addPrefill`/`mode` state) so the non-empty branch shows a `List | Calendar` picker. Specifically:

(a) add state + enum after the existing `@State` lines:
```swift
    @State private var mode: Mode = .list
    @State private var addPrefill: Date?
    private enum Mode: String, CaseIterable { case list = "List", calendar = "Calendar" }
```

(b) replace the non-empty `else { List { … } }` branch (the whole `else` block) with:
```swift
                } else {
                    VStack(spacing: 0) {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 4)
                        if mode == .list {
                            List {
                                ForEach(store.scheduled, id: \.id) { t in
                                    Button { editing = t } label: { ScheduledRow(template: t).contentShape(Rectangle()) }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { delete(t) } label: { Label("Delete", systemImage: "trash") }
                                            Button { editing = t } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button { postNow(t) } label: { Label("Post", systemImage: "checkmark.circle") }.tint(.green)
                                        }
                                        .contextMenu {
                                            Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                                            Button { postNow(t) } label: { Label("Post now", systemImage: "checkmark.circle") }
                                            Button(role: .destructive) { delete(t) } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            }
                        } else {
                            ScheduledCalendarView(onEdit: { editing = $0 }, onPost: postNow,
                                                  onAdd: { addPrefill = $0; showingAdd = true })
                        }
                    }
                }
```

(c) replace the add sheet line `.sheet(isPresented: $showingAdd) { ScheduledSheet() }` with:
```swift
            .sheet(isPresented: $showingAdd, onDismiss: { addPrefill = nil }) { ScheduledSheet(prefillStart: addPrefill) }
```

(The toolbar `+` already sets `showingAdd = true`; `addPrefill` stays nil for it → a blank new template. `postNow`/`delete` are unchanged and reused by both modes.)

- [ ] **Step 4: Generate + build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`. (New file → `xcodegen` picks it up. Likely compile spots: the `LazyVGrid`/`ForEach(0..<firstWeekday)` ranges, and the tuple-element `ForEach(occ, id: \.template.id)`.)

- [ ] **Step 5: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass.

- [ ] **Step 6: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Manual verification on the simulator**

Launch the Scheduled tab. Then:
- Toggle to **Calendar**: month grid renders; days with templates show colored dots (cap 3 + "+N"); today has a ring.
- ‹ / › change month; **Today** jumps back + selects today.
- Tap a day → its occurrences with status badges; an unposted one shows **Post now** (context menu) → posting flips it to **done** (a tx now links it).
- No day selected → **Upcoming** list.
- Day-detail **+** opens the sheet with that day's date prefilled as start.
- Toggle back to **List** → unchanged.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab scheduled
```
(If `-initialTab scheduled` isn't a recognized arg, just navigate there manually.)

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift
git commit -m "feat(ios): scheduled calendar view (month grid + occurrence status + quick-add)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-25-ios-scheduled-calendar-design.md`):
- color projection → Task 1 steps 3-4. ✓
- `occurrencesInRange` + `scheduledPostedMap` + tests → Task 1 steps 1,5. ✓
- List|Calendar toggle → Task 2 step 3. ✓
- Month grid (dots cap 3 + "+N", today ring, selected highlight, nav + Today) → Task 2 step 2 (`grid`/`dayCell`/`header`). ✓
- Selected-day detail + status badge + Post-now/Edit + Upcoming fallback → Task 2 (`detail`/`occurrenceRow`/`statusBadge`). ✓
- Quick-add prefilling startDate → Task 2 steps 1,3 (`prefillStart`, `onAdd`). ✓
- No engine change; build iOS+macOS; full tests → Task 2 steps 4-6. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `ScheduledTemplate.color` defaulted init keeps call sites valid; `occurrencesInRange` returns `[(date,template)]` consumed by `grid`/`detail` (grouped by `.date`, rows keyed `\.template.id`); `scheduledPostedMap` → `[String:Bool]` consumed by `status(...)`; `ScheduledCalendarView(onEdit:onPost:onAdd:)` matches the call in `ScheduledTab`; `ScheduledSheet(prefillStart:)` matches the new init; `Color(hex:)` failable → `?? .accentColor`. ✓

---

## Out of scope

Drag-reschedule; week/agenda views; editing an occurrence's individual date; schema/engine changes.
