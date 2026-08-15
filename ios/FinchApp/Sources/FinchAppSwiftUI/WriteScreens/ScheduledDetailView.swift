import SwiftUI
import FinchCore

/// Read-only scheduled-template detail for the iPad/macOS third column (#414
/// CP2). Resolves the template live from the store so posts/edits reflect
/// immediately. Post now resolves an occurrence and posts through the same
/// shared flow the tab's list/calendar use (`ScheduledPoster`) — no occurrence
/// is in hand here either, so it goes through occurrence resolution just like
/// the list's swipe/context-menu entry points; Edit opens the existing
/// ScheduledSheet — the sheet stays the write path.
struct ScheduledDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let templateId: String
    @State private var editing: ScheduledTemplate?
    @State private var errorMessage: String?
    @State private var postPrefill: PostPrefill?

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
            .scheduledPostSheet($postPrefill)
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
                    if let amount = t.signedAmount {
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
            LabeledContent("Next run", value: scheduledNextRun(t, today: store.wallToday))
            if t.frequency == "monthly" || t.frequency == "quarterly" || t.frequency == "yearly" {
                LabeledContent("Day of month", value: "\(t.dayOfMonth)")
            }
            if let wd = t.weekDay {
                // day_of_week is 0-based Sunday-first (DB schema + Forecast engine
                // + web all agree) — weekdaySymbols is too, so index directly.
                LabeledContent("Weekday", value: Calendar.current.weekdaySymbols[((wd % 7) + 7) % 7])
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

    /// No occurrence in hand here either (this is the toolbar, not a calendar
    /// tap) — resolve one and post through the same shared flow the tab uses.
    private func postNow(_ t: ScheduledTemplate) {
        ScheduledPoster.postNow(t, store: store, prefill: $postPrefill, errorMessage: $errorMessage)
    }
}
