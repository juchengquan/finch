import SwiftUI
import FinchCore

/// Guided per-account reconcile: enter the statement balance, tick transactions as
/// cleared, and finish. (CP1: ticking + tracker + finish. CP2 adds quick-add + confirm-and-clear.)
struct ReconcileSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let preselect: String?
    @State private var accountId = ""
    @State private var statementBalance = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var addMerchant = ""
    @State private var addAmount = ""
    @State private var addIsExpense = true

    init(preselect: String? = nil) { self.preselect = preselect }

    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }

    var body: some View {
        NavigationStack {
            Form {
                if preselect == nil {
                    Picker("Account", selection: $accountId) {
                        ForEach(store.accounts) { Text($0.name ?? "—").tag($0.id) }
                    }
                }
                if let a = account {
                    Section {
                        LabeledContent("Current balance", value: store.displayMoney(a.balance, from: a.currency))
                        HStack {
                            Text("Statement balance"); Spacer()
                            TextField("0.00", text: $statementBalance).numericInput($statementBalance).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        // Date AND time: a statement is cut at a moment, and the
                        // adjustment this sheet posts is dated to it.
                        DatePicker("Statement date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, AppDate.h24Locale)
                    } footer: {
                        // The detail page shows only the seal; the checkpoint's
                        // date lives here, where the next reconcile happens.
                        // The checkpoint carries a time when one was given; show it,
                        // since it is the thing that distinguishes two reconciles of
                        // the same account on the same day.
                        if let last = a.lastReconciledAt, last.count > 10,
                           let d = AppDate.isoDateTime.date(from: String(last.prefix(16))) {
                            Text("Last reconciled on \(d.formatted(date: .abbreviated, time: .shortened))")
                        } else if let last = a.lastReconciledAt,
                                  let d = AppDate.isoDay.date(from: String(last.prefix(10))) {
                            Text("Last reconciled on \(d.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    trackerSection(a)
                    quickAddSection(a)
                    pendingSection(a)
                    transactionsSection(a)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Reconcile")
            .finchSectionSpacing()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let a = account, parse(statementBalance) != 0 || !statementBalance.isEmpty {
                        let s = recState(a)
                        if s.balanced {
                            Button { finish(postAdjustment: false) } label: { Text("Done") }.bold()
                        } else {
                            Button { finish(postAdjustment: true) } label: {
                                Text("Adjust \(store.displayMoney(s.difference, from: a.currency))")
                            }
                        }
                    }
                }
            }
            .onAppear { if accountId.isEmpty { accountId = preselect ?? store.accounts.first?.id ?? "" } }
        }
    }

    private func recState(_ a: AccountRow) -> ReconcileState {
        Selectors.reconcileState(a, store.transactions(for: a.id), DecimalInput.parse(statementBalance) ?? 0)
    }

    @ViewBuilder private func trackerSection(_ a: AccountRow) -> some View {
        if DecimalInput.parse(statementBalance) != nil {
            let s = recState(a)
            Section {
                LabeledContent("Cleared", value: store.displayMoney(s.clearedBalance, from: a.currency))
                LabeledContent("Difference",
                    value: store.displayMoney(s.difference, from: a.currency))
                    .foregroundStyle(s.balanced ? .green : .orange)
                ProgressView(value: progress(s, parse(statementBalance)))
                    .tint(s.balanced ? .green : .orange)
                Text("Cleared \(s.clearedCount) · To review \(s.unclearedCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func parse(_ s: String) -> Double { DecimalInput.parse(s) ?? 0 }
    private func progress(_ s: ReconcileState, _ target: Double) -> Double {
        guard target != 0 else { return s.balanced ? 1 : 0 }
        return min(1, max(0, abs(s.clearedBalance / target)))
    }

    @ViewBuilder private func transactionsSection(_ a: AccountRow) -> some View {
        let txns = store.transactions(for: a.id).filter { $0.pending != true }
        Section("Transactions") {
            if txns.isEmpty {
                Text("No transactions").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(txns, id: \.id) { t in clearRow(a, t) }
            }
        }
    }

    @ViewBuilder private func clearRow(_ a: AccountRow, _ t: Tx) -> some View {
        let cleared = t.clearedAt != nil
        Button { toggleCleared(t, !cleared) } label: {
            HStack {
                Image(systemName: cleared ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(cleared ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.merchant).lineLimit(1)
                    Text(t.date).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.displayMoney(t.nativeAmount ?? t.amount, from: a.currency)).fontWeight(.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(cleared ? Color.green.opacity(0.08) : nil)
    }

    private func toggleCleared(_ t: Tx, _ cleared: Bool) {
        do { try store.apply(.setCleared, Args(["id": .string(t.id), "cleared": .bool(cleared)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    private func finish(postAdjustment: Bool) {
        errorMessage = nil
        guard let bal = DecimalInput.parse(statementBalance) else { errorMessage = "Enter the statement balance."; return }
        do {
            try store.apply(.reconcileAccount, Args([
                "accountId": .string(accountId), "statementBalance": .double(bal),
                "statementDate": .string(AppDate.isoDay.string(from: date)),
                "statementTime": .string(AppDate.isoTime.string(from: date)),
                "postAdjustment": .bool(postAdjustment)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }

    @ViewBuilder private func quickAddSection(_ a: AccountRow) -> some View {
        Section("Add missing transaction") {
            Picker("Type", selection: $addIsExpense) {
                Text("Expense").tag(true)
                Text("Income").tag(false)
            }.pickerStyle(.segmented)
            TextField("Merchant", text: $addMerchant)
            HStack {
                Text("Amount"); Spacer()
                TextField("0.00", text: $addAmount).numericInput($addAmount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Button("Add") { quickAdd(a) }
                .disabled(DecimalInput.parse(addAmount) == nil)
        }
    }

    @ViewBuilder private func pendingSection(_ a: AccountRow) -> some View {
        let pending = store.transactions(for: a.id).filter { $0.pending == true }
        if !pending.isEmpty {
            Section("To confirm (\(pending.count))") {
                ForEach(pending, id: \.id) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.merchant).lineLimit(1)
                            Text(t.date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.displayMoney(t.nativeAmount ?? t.amount, from: a.currency)).fontWeight(.medium)
                        Button("Confirm & clear") { confirmAndClear(t) }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
    }

    private func confirmAndClear(_ t: Tx) {
        errorMessage = nil
        do {
            try store.apply(.confirmTransaction, Args(["id": .string(t.id)]))
            try store.apply(.setCleared, Args(["id": .string(t.id), "cleared": .bool(true)]))
        } catch { errorMessage = i18nMessage(error) }
    }

    private func quickAdd(_ a: AccountRow) {
        errorMessage = nil
        guard let v = DecimalInput.parse(addAmount), v != 0 else { return }
        let signed = addIsExpense ? -abs(v) : abs(v)
        let args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(a.id),
            "amount": .double(signed),
            "merchant": .string(addMerchant.isEmpty ? "Reconcile" : addMerchant),
            "date": .string(AppDate.isoDay.string(from: date)),
            "time": .string(AppDate.isoTime.string(from: date)), "status": .string("confirmed")]
        do {
            if let id = try store.applyReturningId(.addTransaction, Args(args)) {
                try store.apply(.setCleared, Args(["id": .string(id), "cleared": .bool(true)]))
            }
            addMerchant = ""; addAmount = ""
        } catch { errorMessage = i18nMessage(error) }
    }
}
