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
    @State private var addPrefill: Date?
    @State private var addFromCharge: RecurringCharge?
    @State private var searchQuery = ""                // filters the list view by name
    // Calendar first (default); List second.
    private enum Mode: String, CaseIterable { case calendar = "Calendar", list = "List" }

    private var detected: [RecurringCharge] {
        Selectors.detectRecurring(store.txns, store.activeLedgerId, store.today, store.scheduled).filter { !$0.isScheduled }
    }
    private var detectedMonthly: Double { detected.reduce(0) { $0 + $1.monthlyEstimate } }

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
        // A primary tab supplies its own NavigationStack (like Accounts/Insights);
        // it no longer lands in the system More overflow, so MoreTabNavigationStack
        // (a no-op in compact width) would leave it with no nav bar or title.
        NavigationStack {
            Group {
                if store.scheduled.isEmpty && detected.isEmpty {
                    ContentUnavailableView {
                        Label("No scheduled items", systemImage: "calendar")
                    } description: {
                        Text(store.accounts.isEmpty
                             ? "Import a .finch pack or add an account first."
                             : "Tap + to add a recurring transaction or installment plan.")
                    }
                } else {
                    VStack(spacing: 0) {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 4)
                        if mode == .list {
                            List {
                                ForEach(filteredScheduled, id: \.id) { t in
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
                        } else {
                            ScheduledCalendarView(templates: filteredScheduled, onEdit: { editing = $0 },
                                                  onPost: postNow, onAdd: { addPrefill = $0; showingAdd = true })
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
            .settingsPush()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Scheduled")
                        .disabled(store.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { addPrefill = nil }) { ScheduledSheet(prefillStart: addPrefill) }
            .sheet(item: $editing) { ScheduledSheet(template: $0) }
            .sheet(item: $addFromCharge) { ScheduledSheet(fromCharge: $0) }
            .errorAlert($errorMessage)
        }
    }

    private func postNow(_ t: ScheduledTemplate) {
        do { try store.apply(.postScheduled, Args(["templateId": .string(t.id)])) } catch { errorMessage = i18nMessage(error) }
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
    /// next_run is never persisted (NULL on insert), so derive the next occurrence
    /// from the recurrence — keeps every row (seeded or user-created) showing a
    /// real date. Horizon of ~13 months covers yearly templates.
    private var nextRunDisplay: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = store.today
        let base = cal.date(from: DateComponents(
            year: Int(today.prefix(4)), month: Int(today.dropFirst(5).prefix(2)),
            day: Int(today.dropFirst(8).prefix(2)))) ?? Date()
        let h = cal.dateComponents([.year, .month, .day],
                                   from: cal.date(byAdding: .day, value: 400, to: base) ?? base)
        let horizon = String(format: "%04d-%02d-%02d", h.year ?? 0, h.month ?? 1, h.day ?? 1)
        return Selectors.occurrencesInRange([template], from: today, through: horizon).first?.date
            ?? (template.nextRun.isEmpty ? "—" : template.nextRun)
    }

    var body: some View {
        HStack {
            Image(systemName: template.type == "transfer" ? "arrow.left.arrow.right"
                  : template.type == "income" ? "arrow.down.circle" : "arrow.up.circle")
                .foregroundStyle(.secondary)
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
