# Scheduled Detail Column (iPad/macOS, #414 CP2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Scheduled tab joins the three-column shell — selecting a template (list row OR calendar occurrence) fills the third column with a read-only detail whose toolbar offers Post now + Edit.

**Architecture:** Task 1 extracts the next-run computation into a shared helper (pure move) and builds the self-contained `ScheduledDetailView`. Task 2 threads selection mode through `ScheduledTab` (4 gated touch points, nil path unchanged; the calendar `onEdit` remap needs no `ScheduledCalendarView` changes) and wires `.scheduled` into `SplitViewShell`.

**Tech Stack:** Swift/SwiftUI; XcodeGen; XCTest regression only. Spec: `plans/ios-macos/2026-07-16-scheduled-detail-column-spec.md`.

## Global Constraints

- **`ScheduledTab`'s `selection == nil` path must be behavior-identical.** Allowed changes: the property, the List binding, the list-row Button action, the macOS ↵ condition, the calendar `onEdit` closure remap — nothing else. `onPost`/`onAdd` closures, swipe/context menus, detected-charges section, search, mode picker: untouched.
- The next-run extraction is a **pure move** — `ScheduledRow`'s displayed value must not change.
- **No `scheduled:` deep-link consumption** (nothing emits those ids — spec non-goal).
- Money via store formatters; detail decomposed into small section funcs (macOS type-check trap).
- Build BOTH FinchApp (iOS) + FinchMac (macOS) + full FinchAppTests. From `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` after adding files. iPad check on a FRESH sim (reused sims carry a UISplitViewController restoration key — #441 gotcha); delete created sims afterwards. Tap flows = manual checklist in the PR body.

---

### Task 1: shared next-run helper + `ScheduledDetailView`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift` (extract the helper; `ScheduledRow` consumes it)
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledDetailView.swift`

**Interfaces:**
- Produces: `func scheduledNextRun(_ template: ScheduledTemplate, today: String) -> String` (internal, file-scope in ScheduledTab.swift) and `struct ScheduledDetailView: View` with `init(templateId: String)`.
- Consumes (existing): `Selectors.occurrencesInRange`, `store.displayMoney(_:from:)`, `store.categoryName(_:)`, `store.apply(.postScheduled, …)`, `ScheduledSheet(template:)`, `DetailPlaceholder(systemImage:label:)`, `errorAlert`.

- [ ] **Step 1: Extract the next-run helper (pure move)**

In `ScheduledTab.swift`, add at file scope (below the `ScheduledRow` struct):

```swift
/// The template's next occurrence date. next_run is never persisted (NULL on
/// insert), so derive it from the recurrence — a ~400-day horizon covers yearly
/// templates. Shared by ScheduledRow and ScheduledDetailView.
func scheduledNextRun(_ template: ScheduledTemplate, today: String) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let base = cal.date(from: DateComponents(
        year: Int(today.prefix(4)), month: Int(today.dropFirst(5).prefix(2)),
        day: Int(today.dropFirst(8).prefix(2)))) ?? Date()
    let h = cal.dateComponents([.year, .month, .day],
                               from: cal.date(byAdding: .day, value: 400, to: base) ?? base)
    let horizon = String(format: "%04d-%02d-%02d", h.year ?? 0, h.month ?? 1, h.day ?? 1)
    return Selectors.occurrencesInRange([template], from: today, through: horizon).first?.date
        ?? (template.nextRun.isEmpty ? "—" : template.nextRun)
}
```

Replace `ScheduledRow.nextRunDisplay`'s body with a delegation (keep the property so the row's body is untouched):

```swift
    private var nextRunDisplay: String { scheduledNextRun(template, today: store.today) }
```
(Delete the now-moved computation from the property; the doc comment moves with the helper.)

- [ ] **Step 2: Create `ScheduledDetailView.swift`**

```swift
import SwiftUI
import FinchCore

/// Read-only scheduled-template detail for the iPad/macOS third column (#414
/// CP2). Resolves the template live from the store so posts/edits reflect
/// immediately. Post now performs the same one-line engine call the tab's rows
/// use; Edit opens the existing ScheduledSheet — the sheet stays the write path.
struct ScheduledDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let templateId: String
    @State private var editing: ScheduledTemplate?
    @State private var errorMessage: String?

    private var template: ScheduledTemplate? { store.scheduled.first { $0.id == templateId } }
    private func account(_ id: String) -> AccountRow? { store.accounts.first { $0.id == id } }

    var body: some View {
        if let t = template {
            List {
                headerSection(t)
                scheduleSection(t)
                postingSection(t)
                progressSection(t)
                if let d = t.description, !d.isEmpty {
                    Section("Description") { Text(d) }
                }
            }
            .navigationTitle("Scheduled")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { postNow(t) } label: { Label("Post now", systemImage: "checkmark.circle") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                }
            }
            .sheet(item: $editing) { ScheduledSheet(template: $0) }
            .errorAlert($errorMessage)
        } else {
            DetailPlaceholder(systemImage: "calendar", label: "Select a scheduled item")
        }
    }

    @ViewBuilder private func headerSection(_ t: ScheduledTemplate) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: t.type == "transfer" ? "arrow.left.arrow.right"
                      : t.type == "income" ? "arrow.down.circle" : "arrow.up.circle")
                    .font(.title2)
                    .foregroundStyle(t.type == "income" ? .green
                                     : t.type == "transfer" ? .blue : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.headline)
                    if let amount = t.amount {
                        Text(store.displayMoney(amount, from: account(t.accountId)?.currency ?? store.displayCurrency))
                            .font(.title3).fontWeight(.semibold)
                    } else {
                        Text("Variable").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func scheduleSection(_ t: ScheduledTemplate) -> some View {
        Section("Schedule") {
            LabeledContent("Frequency", value: t.frequency.capitalized)
            LabeledContent("Next run", value: scheduledNextRun(t, today: store.today))
            if t.frequency == "monthly" || t.frequency == "yearly" {
                LabeledContent("Day of month", value: "\(t.dayOfMonth)")
            }
            if let wd = t.weekDay {
                LabeledContent("Weekday", value: Calendar.current.weekdaySymbols[(wd - 1 + 7) % 7])
            }
            if let start = t.startDate { LabeledContent("Starts", value: String(start.prefix(10))) }
            if let end = t.endDate { LabeledContent("Ends", value: String(end.prefix(10))) }
        }
    }

    @ViewBuilder private func postingSection(_ t: ScheduledTemplate) -> some View {
        Section("Posts to") {
            LabeledContent("Account", value: account(t.accountId)?.name ?? t.accountId)
            if let from = t.fromAccountId {
                LabeledContent("From account", value: account(from)?.name ?? from)
            }
            if let cat = t.categoryId {
                LabeledContent("Category", value: store.categoryName(cat) ?? cat)
            }
        }
    }

    @ViewBuilder private func progressSection(_ t: ScheduledTemplate) -> some View {
        if t.installmentTotal != nil || t.maxExecutions != nil {
            Section("Progress") {
                if let total = t.installmentTotal {
                    LabeledContent("Installment", value: "\(t.installmentPaid ?? 0) of \(total)")
                }
                if let maxEx = t.maxExecutions {
                    LabeledContent("Max executions", value: "\(maxEx)")
                }
            }
        }
    }

    private func postNow(_ t: ScheduledTemplate) {
        do { try store.apply(.postScheduled, Args(["templateId": .string(t.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 3: Build iOS + macOS (view unused yet; the helper move must keep the row compiling)**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledDetailView.swift
git commit -m "feat(ios): ScheduledDetailView + shared next-run helper (#414 CP2 part 1)"
```

---

### Task 2: `ScheduledTab` selection mode + shell wiring

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift` (5 gated additions)
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift` (`.scheduled` branch)

**Interfaces:**
- Consumes (Task 1): `ScheduledDetailView(templateId:)`. Existing: `ThreeColumnShell`, `DetailPlaceholder`, the `selection: Binding<String?>?` convention.

- [ ] **Step 1: Add the selection property to `ScheduledTab`**

Next to the other properties (e.g. after `@State private var mode`):
```swift
    /// Non-nil → three-column selection mode (rows/occurrences select and the
    /// shell renders the detail column); nil → taps open the edit sheet. Same
    /// convention as AccountsTab/BudgetsTab/ActivityFeedView (#414/#23).
    var selection: Binding<String?>? = nil
```

- [ ] **Step 2: List binding**

Change `List(selection: $kbSel) {` (list mode) to:
```swift
                            List(selection: selection ?? $kbSel) {
```

- [ ] **Step 3: List-row action**

Change:
```swift
                                ForEach(filteredScheduled, id: \.id) { t in
                                    Button { editing = t } label: { ScheduledRow(template: t).contentShape(Rectangle()) }
```
to:
```swift
                                ForEach(filteredScheduled, id: \.id) { t in
                                    Button {
                                        if let selection { selection.wrappedValue = t.id } else { editing = t }
                                    } label: { ScheduledRow(template: t).contentShape(Rectangle()) }
```

- [ ] **Step 4: macOS ↵ gate**

Change:
```swift
                            .onKeyPress(.return) {
                                if let id = kbSel, let t = filteredScheduled.first(where: { $0.id == id }) { editing = t; return .handled }
                                return .ignored
                            }
```
to:
```swift
                            .onKeyPress(.return) {
                                // In three-column selection mode the selection already
                                // drives the detail column — ↵ falls through.
                                if selection == nil, let id = kbSel, let t = filteredScheduled.first(where: { $0.id == id }) { editing = t; return .handled }
                                return .ignored
                            }
```

- [ ] **Step 5: Calendar `onEdit` remap (no `ScheduledCalendarView` changes)**

Change:
```swift
                            ScheduledCalendarView(templates: filteredScheduled, onEdit: { editing = $0 },
                                                  onPost: postNow, onAdd: { addPrefill = $0; showingAdd = true })
```
to:
```swift
                            // In selection mode a calendar tap selects the occurrence's
                            // template in the detail column instead of opening the sheet.
                            ScheduledCalendarView(templates: filteredScheduled,
                                                  onEdit: { t in
                                                      if let selection { selection.wrappedValue = t.id } else { editing = t }
                                                  },
                                                  onPost: postNow, onAdd: { addPrefill = $0; showingAdd = true })
```

- [ ] **Step 6: Shell wiring**

In `SplitViewShell` (AdaptiveShell.swift): add `@State private var scheduledSelection: String?` next to `txSelection`; insert before `default:`:
```swift
            case .scheduled:
                ThreeColumnShell {
                    ScheduledTab(selection: $scheduledSelection)
                } detail: {
                    // Guard against a stale selection (deleted template / ledger switch).
                    if let id = scheduledSelection, store.scheduled.contains(where: { $0.id == id }) {
                        NavigationStack { ScheduledDetailView(templateId: id) }
                    } else {
                        DetailPlaceholder(systemImage: "calendar", label: "Select a scheduled item")
                    }
                }
```
and add `scheduledSelection = nil` to the ledger-switch `onChange` block.

- [ ] **Step 7: Build both platforms + full FinchAppTests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -only-testing:FinchAppTests 2>&1 | grep -iE "Executed .* tests|TEST SUCCEEDED|TEST FAILED"
```
Expected: both builds SUCCEED; suite green.

- [ ] **Step 8: iPad simulator (scripted parts) + manual checklist**

Fresh iPad sim (per the #441 gotcha), install, `-initialTab scheduled`, screenshot → sidebar │ scheduled (calendar mode) │ "Select a scheduled item" placeholder. iPhone sanity screenshot (compact unchanged). Delete created sims. Manual checklist (PR body):
1. List mode: tap a row → detail fills; tap another → updates.
2. Calendar mode: tap an occurrence → the template's detail fills (no sheet).
3. Post now from the column → next-run advances in place; the feed shows the posted transaction.
4. Edit → sheet → save → detail reflects it.
5. Delete the selected template (list swipe) → placeholder returns.
6. iPhone: both modes still open the sheet on tap.

- [ ] **Step 9: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift \
        ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift
git commit -m "feat(ios): Scheduled joins the three-column shell — selection in both modes (#414 CP2)"
```

---

## Self-Review

**1. Spec coverage:** shared helper pure-move → Task 1 Step 1 (delegating property keeps the row body untouched); detail view (all sections, Post now + Edit, live resolution, placeholder) → Task 1 Step 2; the 5 gated touch points incl. the calendar remap → Task 2 Steps 1-5 (`onPost`/`onAdd` untouched — visible in the Step 5 diff); shell branch + ledger clear + stale guard → Task 2 Step 6; no deep-link consumption (nothing added — spec non-goal); builds/tests/iPad screenshot + manual checklist → Task 2 Steps 7-8. CP1's lesson → the reviewer prompt should audit ScheduledTab for other router consumption. ✅
**2. Placeholder scan:** none — complete code everywhere.
**3. Type consistency:** `scheduledNextRun(_:today:)` used by both the row's delegating property and the detail view; `ScheduledDetailView(templateId:)` matches Task 2's shell usage; `ScheduledTab(selection:)` uses the property-default init; `weekdaySymbols` indexing guarded by modulo; `Args`/`.postScheduled`/`i18nMessage` mirror the tab's own `postNow` verbatim.
