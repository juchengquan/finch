import SwiftUI
import FinchCore

/// Scheduled templates (recurring + installment plans) — a primary bottom-bar
/// tab (after Budgets), now writable (Phase 2 Task 19). Lists each template with
/// its cadence, next run, amount, and installment progress. Add via the '+'
/// toolbar; per-row context menu / swipe to Post-now or Delete. All writes go
/// through FinchStore.apply.
struct ScheduledTab: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var editing: ScheduledTemplate?
    @State private var errorMessage: String?
    @State private var mode: Mode = .calendar
    @State private var pendingDelete: ScheduledTemplate?   // template awaiting delete confirmation
    @State private var addPrefill: Date?
    @State private var addFromCharge: RecurringCharge?
    @State private var searchQuery = ""                // filters the list view by name
    @State private var kbSel: String?            // macOS keyboard-open selection
    @State private var postPrefill: PostPrefill?
    /// Non-nil → three-column selection mode (rows/occurrences select and the
    /// shell renders the detail column); nil → taps open the edit sheet. Same
    /// convention as AccountsTab/BudgetsTab/ActivityFeedView (#414/#23).
    var selection: Binding<String?>? = nil
    // Calendar first (default); List second.
    private enum Mode: String, CaseIterable { case calendar = "Calendar", list = "List" }

    /// One calendar occurrence awaiting its prefilled Add sheet. `.sheet(item:)`
    /// needs Identifiable and a tuple can't conform. The id deliberately combines
    /// template AND occurrence: posting two occurrences of the same template in
    /// one sitting must re-present the sheet, which a template-only id would suppress.
    struct PostPrefill: Identifiable {
        let template: ScheduledTemplate
        let occurrence: String
        var id: String { "\(template.id)|\(occurrence)" }
    }

    private var detected: [RecurringCharge] {
        Selectors.detectRecurring(store.txns, store.activeLedgerId, store.wallToday, store.scheduled).filter { !$0.isScheduled }
    }

    /// True while the user has typed a non-empty search.
    private var searchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Scheduled templates narrowed by the search query (case-insensitive name).
    private var filteredScheduled: [ScheduledTemplate] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.scheduled }
        return store.scheduled.filter { $0.name.lowercased().contains(q) }
    }
    /// Detected (not-yet-scheduled) charges narrowed by the same query.
    private var filteredDetected: [RecurringCharge] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return detected }
        return detected.filter { $0.merchantName.lowercased().contains(q) }
    }

    var body: some View {
        // A primary tab supplies its own NavigationStack (like Accounts/Insights)
        // so it gets a nav bar, large title, and working NavigationLinks in
        // compact width.
        NavigationStack {
            Group {
                // Empty state only when nothing CAN be scheduled (no accounts; the
                // + button is disabled too). With accounts, the calendar always
                // renders — an empty month grid still offers day-tap add.
                if store.accounts.isEmpty {
                    EmptyState(tab: .scheduled,
                               description: "Import a .finch pack or add an account first.")
                } else {
                    // The mode picker lives INSIDE each List (first row) rather than
                    // in a VStack above it: wrapped in a VStack the List is no longer
                    // the nav stack's primary scroll view, so the large title never
                    // collapsed on scroll like every other tab. (safeAreaInset(.top)
                    // is no alternative — it makes the List render as pre-scrolled
                    // and the title disappears entirely.)
                    Group {
                        if mode == .list {
                            List(selection: selection ?? $kbSel) {
                                modePickerRow
                                if filteredScheduled.isEmpty && filteredDetected.isEmpty && !searchActive {
                                    Text("Tap + or a calendar day to add a recurring transaction.")
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(filteredScheduled, id: \.id) { t in
                                    Button {
                                        if let selection { selection.wrappedValue = t.id } else { editing = t }
                                    } label: { ScheduledRow(template: t).contentShape(Rectangle()) }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing) {
                                            // Edit declared first → sits at the trailing edge (rightmost); Delete to its left.
                                            // Not role: .destructive — the role plays a fake row-removal animation before the confirm.
                                            Button { editing = t } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                            Button { pendingDelete = t } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button { postNow(t) } label: { Label("Post", systemImage: "checkmark.circle") }.tint(.green)
                                        }
                                        .contextMenu {
                                            Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                                            Button { postNow(t) } label: { Label("Post now", systemImage: "checkmark.circle") }
                                            Button(role: .destructive) { pendingDelete = t } label: { Label("Delete", systemImage: "trash") }
                                        }
                                        .tag(t.id)
                                }
                                if !filteredDetected.isEmpty {
                                    Section {
                                        ForEach(filteredDetected) { r in
                                            Button { addFromCharge = r } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(r.merchantName)
                                                        Text("\(r.cadence.capitalized) · next ~\(r.nextEstimatedDate)")
                                                            .font(.caption).foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Text(store.displayMoneyBase(r.averageAmount)).fontWeight(.medium)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } header: {
                                        HStack {
                                            Text("Detected · not scheduled")
                                            Spacer()
                                            Text("~\(store.displayMoneyBase(filteredDetected.reduce(0) { $0 + $1.monthlyEstimate }))/mo · \(filteredDetected.count)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .overlay {
                                if searchActive && filteredScheduled.isEmpty && filteredDetected.isEmpty {
                                    ContentUnavailableView.search(text: searchQuery)
                                }
                            }
                            #if os(macOS)
                            .onKeyPress(.return) {
                                // In three-column selection mode the selection already
                                // drives the detail column — ↵ falls through.
                                if selection == nil, let id = kbSel, let t = filteredScheduled.first(where: { $0.id == id }) { editing = t; return .handled }
                                return .ignored
                            }
                            #endif
                        } else {
                            // In selection mode a calendar TAP selects the occurrence's
                            // template in the detail column (onSelect), while the context
                            // menu's "Edit" keeps opening the editor (onEdit).
                            ScheduledCalendarView(templates: filteredScheduled,
                                                  onEdit: { editing = $0 },
                                                  onPost: { postNow($0, occurrence: $1) },
                                                  onDelete: { pendingDelete = $0 },
                                                  onAdd: { addPrefill = $0; showingAdd = true },
                                                  onSelect: selection.map { sel in { sel.wrappedValue = $0.id } },
                                                  topRow: AnyView(modePickerRow))
                        }
                    }
                    // Search lives outside the Calendar/List toggle, so it's pinned
                    // at the top and applies to whichever view is showing.
                    #if os(iOS)
                    .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search scheduled")
                    #else
                    .searchable(text: $searchQuery, prompt: "Search scheduled")
                    #endif
                }
            }
            .navigationTitle("Scheduled")
            .ledgerPush()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }
                #endif
                ToolbarItem(placement: .primaryAction) { PrivacyToggleButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Scheduled")
                        .disabled(store.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { addPrefill = nil }) { ScheduledSheet(prefillStart: addPrefill) }
            .sheet(item: $editing) { ScheduledSheet(template: $0) }
            .sheet(item: $addFromCharge) { ScheduledSheet(fromCharge: $0) }
            .sheet(item: $postPrefill) { p in
                AddTransactionSheet(prefill: store.txPrefill(for: p.template, occurrence: p.occurrence),
                                    postsScheduledOccurrence: true)
            }
            // Centered ALERT (window-level) — see ActivityTab's delete alert.
            .alert("Delete scheduled item?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete) { t in
                Button("Delete", role: .destructive) { delete(t) }
                Button("Cancel", role: .cancel) {}
            } message: { t in
                Text("\(t.name) — future runs will stop.")
            }
            .errorAlert($errorMessage)
        }
    }

    /// The Calendar/List toggle as a list row (clear background, no separator)
    /// — shared by both modes so each List can own it as its first row.
    private var modePickerRow: some View {
        Picker("View", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// The list rows' Post — no occurrence in hand, so the engine stamps today
    /// (unchanged legacy behaviour; the calendar is the occurrence-aware path).
    private func postNow(_ t: ScheduledTemplate) {
        do { try store.apply(.postScheduled, Args(["templateId": .string(t.id)])) } catch { errorMessage = i18nMessage(error) }
    }

    /// Post ONE calendar occurrence. Most templates open a prefilled sheet so the
    /// user confirms the date/amount before it lands; split-income templates stay
    /// on the silent engine path (see `ScheduledPostRouting`).
    private func postNow(_ t: ScheduledTemplate, occurrence: String) {
        // The installment cap lives in `Scheduled.post`, which the sheet path
        // bypasses — re-check it here, with the ENGINE's message key so the copy
        // (and its zh translation) is the same wherever the user hits the cap.
        if let total = t.installmentTotal, (t.installmentPaid ?? 0) >= total {
            errorMessage = i18nMessage(I18nError("error.scheduled.installmentDone",
                                                 ["name": t.name, "total": String(total)],
                                                 "\"\(t.name)\" has finished its \(total)-payment plan"))
            return
        }
        // A transfer template with no from-account is malformed. The sheet's
        // account fallbacks would otherwise silently fill From/To with the
        // first two accounts — a complete, valid-looking form that fails on
        // Save forever with no way to fix it. Catch it here, before
        // presenting, with the same engine error the silent path throws.
        if t.type == "transfer", t.fromAccountId == nil {
            errorMessage = i18nMessage(I18nError("error.scheduled.missingAccount",
                                                 ["name": t.name],
                                                 "\"\(t.name)\" is missing an account"))
            return
        }
        switch ScheduledPostRouting.routeForPost(t, store: store) {
        case .sheet:
            postPrefill = PostPrefill(template: t, occurrence: occurrence)
        case .silent:
            do {
                try store.apply(.postScheduled, Args([
                    "templateId": .string(t.id), "date": .string(occurrence),
                ]))
            } catch { errorMessage = i18nMessage(error) }
        }
    }

    private func delete(_ t: ScheduledTemplate) {
        do { try store.apply(.deleteScheduled, Args(["id": .string(t.id)])) } catch { errorMessage = i18nMessage(error) }
    }
}

struct ScheduledRow: View {
    @EnvironmentObject private var store: FinchStore
    let template: ScheduledTemplate

    private var accountName: String {
        store.accounts.first { $0.id == template.accountId }?.name ?? "—"
    }
    private var accountCurrency: String {
        store.accounts.first { $0.id == template.accountId }?.currency ?? store.displayCurrency
    }
    private var nextRunDisplay: String { scheduledNextRun(template, today: store.wallToday) }

    /// Leading stripe color by template type — mirrors TxRow's kind stripe so
    /// Scheduled reads the same as the transaction feeds (expense red, income
    /// green, transfer blue, refund purple, adjustment gray).
    private var typeColor: Color {
        switch template.type {
        case "income": .green
        case "refund": .purple
        case "transfer": .blue
        case "adjustment": Color.gray
        default: .red
        }
    }
    private var typeA11yLabel: Text {
        switch template.type {
        case "income": Text("Income")
        case "refund": Text("Refund")
        case "transfer": Text("Transfer")
        case "adjustment": Text("Adjustment")
        default: Text("Expense")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Thin type stripe — matches TxRow's leading kind stripe (the icon's
            // replacement) so Scheduled scans the same as the transaction lists.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(typeColor)
                .frame(width: 3)
                .accessibilityLabel(typeA11yLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).fontWeight(.medium)
                Text("\(template.frequency.capitalized) · next \(nextRunDisplay)")
                    .font(.caption).foregroundStyle(.secondary)
                if let total = template.installmentTotal {
                    Text("Installment \(template.installmentPaid ?? 0)/\(total) · \(accountName)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let amount = template.amount {
                Text(store.displayMoney(amount, from: accountCurrency)).fontWeight(.semibold)
            } else {
                Text("Variable").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

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
