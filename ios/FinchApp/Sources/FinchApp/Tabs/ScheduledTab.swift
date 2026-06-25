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
    @State private var mode: Mode = .list
    @State private var addPrefill: Date?
    private enum Mode: String, CaseIterable { case list = "List", calendar = "Calendar" }

    var body: some View {
        // A primary tab supplies its own NavigationStack (like Accounts/Insights);
        // it no longer lands in the system More overflow, so MoreTabNavigationStack
        // (a no-op in compact width) would leave it with no nav bar or title.
        NavigationStack {
            Group {
                if store.scheduled.isEmpty {
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
            }
            .navigationTitle("Scheduled")
            .settingsPush()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { SettingsBarButton() }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Scheduled")
                        .disabled(store.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { addPrefill = nil }) { ScheduledSheet(prefillStart: addPrefill) }
            .sheet(item: $editing) { ScheduledSheet(template: $0) }
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

    var body: some View {
        HStack {
            Image(systemName: template.type == "transfer" ? "arrow.left.arrow.right"
                  : template.type == "income" ? "arrow.down.circle" : "arrow.up.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).fontWeight(.medium)
                Text("\(template.frequency.capitalized) · next \(template.nextRun)")
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
