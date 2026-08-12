import SwiftUI
import FinchCore

/// Which budgets track this account — the account-side view of `budgets.account_ids`.
///
/// The Budget sheet already edits this from the other end; doing it per budget meant one
/// edit per budget. What makes this side awkward is that the relationship is stored as a
/// LIST WITH A WILDCARD: an empty `accountIds` means "every account, including ones
/// created later". So a budget can track this account without naming it, and there is no
/// way to say "everything except this one".
///
/// That shapes every decision here:
///   - wildcard budgets show CHECKED, because they genuinely do track this account.
///     Hiding that would make the page lie about what is being counted.
///   - unchecking one has to NARROW it to an explicit list of today's accounts, which
///     permanently drops the "and future accounts" part. That is a one-way door, so it
///     asks first and says exactly what it costs.
///   - unchecking a budget that names ONLY this account is refused: emptying the list
///     would turn it into a wildcard, i.e. tracking every account — the opposite of what
///     the tap asked for.
struct AccountBudgetsRow: View {
    @EnvironmentObject private var store: FinchStore
    let accountId: String
    @State private var presented = false

    private var tracking: [BudgetRow] {
        store.budgets.filter { AccountBudgets.tracks($0, accountId) }
    }

    var body: some View {
        Button { presented = true } label: {
            // The LABEL is drawn here rather than left to FieldRow, which shows its
            // title only while a row is empty and otherwise lets the glyph identify
            // the field. "9 of 9" beside a lone glyph says nothing about what is
            // being counted — the same trap the credit-card day rows hit.
            FieldRow(glyph: .budget, title: "Budgets", isEmpty: false) {
                FieldRowChevron()
            } content: {
                HStack {
                    Text("Budgets")
                    Spacer()
                    Text(store.budgets.isEmpty
                         ? String(localized: "No budgets")
                         : String(localized: "\(tracking.count) of \(store.budgets.count)"))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.budgets.isEmpty)
        .sheet(isPresented: $presented) {
            AccountBudgetsSheet(accountId: accountId)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// Pure classification, kept out of the view so it can be tested.
enum AccountBudgets {
    /// A budget with no account filter tracks EVERY account, this one included.
    static func tracksEveryAccount(_ b: BudgetRow) -> Bool { b.accountIds.isEmpty }

    static func tracks(_ b: BudgetRow, _ accountId: String) -> Bool {
        tracksEveryAccount(b) || b.accountIds.contains(accountId)
    }

    /// Unchecking this would empty the list, which the selectors read as "every
    /// account" — so it must be refused rather than silently inverted.
    static func isOnlyAccount(_ b: BudgetRow, _ accountId: String) -> Bool {
        b.accountIds == [accountId]
    }

    /// What a wildcard budget becomes when this account is excluded: every account
    /// that exists TODAY, minus this one. The "and future accounts" meaning is not
    /// expressible once the list is explicit, which is the whole cost of the change.
    static func narrowed(_ all: [AccountRow], excluding accountId: String) -> [String] {
        all.map(\.id).filter { $0 != accountId }.sorted()
    }
}

private struct AccountBudgetsSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let accountId: String

    @State private var staged: Set<String> = []
    @State private var confirmingNarrow: [BudgetRow] = []
    @State private var blocked: BudgetRow?
    @State private var errorMessage: String?

    private var budgets: [BudgetRow] { store.budgets }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(budgets, id: \.id) { b in
                        Button { toggle(b) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.name)
                                    if let caption = caption(for: b) {
                                        Text(caption).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if staged.contains(b.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("A budget with no account filter counts every account, so it is shown ticked here.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Budgets")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: commit) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
            .onAppear {
                staged = Set(budgets.filter { AccountBudgets.tracks($0, accountId) }.map(\.id))
            }
            // Narrowing is the one-way door: say what it costs before doing it.
            .alert(confirmingNarrow.count == 1
                   ? String(localized: "Narrow this budget?")
                   : String(localized: "Narrow these budgets?"), isPresented: Binding(
                get: { !confirmingNarrow.isEmpty },
                set: { if !$0 { confirmingNarrow = [] } })) {
                Button("Narrow", role: .destructive) { write(narrowing: confirmingNarrow) }
                Button("Cancel", role: .cancel) { confirmingNarrow = [] }
            } message: {
                // Singular and plural are separate strings, not one with a joined
                // list: "Dining currently count every account" is what one budget
                // produced otherwise.
                let names = confirmingNarrow.map(\.name).joined(separator: ", ")
                if confirmingNarrow.count == 1 {
                    Text("\(names) currently counts every account. Excluding this one pins it to the accounts that exist today — accounts you add later will not be counted.")
                } else {
                    Text("\(names) currently count every account. Excluding this one pins them to the accounts that exist today — accounts you add later will not be counted.")
                }
            }
            .alert("Can't remove", isPresented: Binding(
                get: { blocked != nil }, set: { if !$0 { blocked = nil } }),
                presenting: blocked) { _ in
                Button("OK", role: .cancel) {}
            } message: { b in
                Text("\(b.name) tracks only this account. Removing it would leave no accounts, which counts every account instead. Edit or delete the budget itself.")
            }
        }
    }

    private func caption(for b: BudgetRow) -> String? {
        if AccountBudgets.tracksEveryAccount(b) { return String(localized: "Tracks every account") }
        if AccountBudgets.isOnlyAccount(b, accountId) { return String(localized: "This account only") }
        return nil
    }

    private func toggle(_ b: BudgetRow) {
        if staged.contains(b.id) {
            // Refuse at the tap, not at save — the reason is about THIS budget and
            // is far clearer next to the row you just touched.
            if AccountBudgets.isOnlyAccount(b, accountId) { blocked = b; return }
            staged.remove(b.id)
        } else {
            staged.insert(b.id)
        }
    }

    private func commit() {
        errorMessage = nil
        // A wildcard budget being unticked is the only case that needs consent.
        let narrowing = budgets.filter {
            AccountBudgets.tracksEveryAccount($0) && !staged.contains($0.id)
        }
        if narrowing.isEmpty { write(narrowing: []) } else { confirmingNarrow = narrowing }
    }

    private func write(narrowing: [BudgetRow]) {
        confirmingNarrow = []
        let narrowIds = Set(narrowing.map(\.id))
        do {
            for b in budgets {
                let wanted = staged.contains(b.id)
                let ids: [String]
                if narrowIds.contains(b.id) {
                    ids = AccountBudgets.narrowed(store.accounts, excluding: accountId)
                } else if AccountBudgets.tracksEveryAccount(b) {
                    continue                       // still a wildcard, still ticked — nothing to write
                } else if wanted == b.accountIds.contains(accountId) {
                    continue                       // unchanged
                } else if wanted {
                    ids = (b.accountIds + [accountId]).sorted()
                } else {
                    ids = b.accountIds.filter { $0 != accountId }.sorted()
                }
                try store.apply(.updateBudget, Args([
                    "id": .string(b.id),
                    "patch": .object(["accountIds": .array(ids.map { .string($0) })]),
                ]))
            }
            dismiss()
        } catch {
            errorMessage = i18nMessage(error)
        }
    }
}
