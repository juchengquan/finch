import SwiftUI
import FinchCore

/// Scheduled templates (recurring + installment plans) — the 6th tab, now
/// writable (Phase 2 Task 19). Lists each template with its cadence, next run,
/// amount, and installment progress. Add via the '+' toolbar; per-row context
/// menu / swipe to Post-now or Delete. All writes go through FinchStore.apply.
struct ScheduledTab: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false

    var body: some View {
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
                    List {
                        ForEach(store.scheduled, id: \.id) { t in
                            ScheduledRow(template: t)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(t) } label: { Label("Delete", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { postNow(t) } label: { Label("Post", systemImage: "checkmark.circle") }.tint(.green)
                                }
                                .contextMenu {
                                    Button { postNow(t) } label: { Label("Post now", systemImage: "checkmark.circle") }
                                    Button(role: .destructive) { delete(t) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Scheduled")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Scheduled")
                        .disabled(store.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd) { AddScheduledSheet() }
        }
    }

    private func postNow(_ t: ScheduledTemplate) { try? store.apply(.postScheduled, Args(["templateId": .string(t.id)])) }
    private func delete(_ t: ScheduledTemplate) { try? store.apply(.deleteScheduled, Args(["id": .string(t.id)])) }
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
            }
        }
    }
}
