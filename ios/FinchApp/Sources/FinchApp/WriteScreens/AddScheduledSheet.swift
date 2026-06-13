import SwiftUI
import FinchCore

/// Add a scheduled template (recurring transaction / installment plan) via
/// createScheduled. Covers the common case: name, type, amount, account,
/// frequency, monthly day-of-month, start date, and an optional installment
/// count. Splits/varies are not exposed (the engine supports them; the iOS form
/// keeps to the single-amount path for now). Routes FinchStore.apply.
struct AddScheduledSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    let frequencies = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly", "once"]

    @State private var name = ""
    @State private var kind: Kind = .expense
    @State private var amount = ""
    @State private var accountId = ""
    @State private var fromAccountId = ""
    @State private var categoryId = ""
    @State private var frequency = "monthly"
    @State private var dayOfMonth = 1
    @State private var startDate = Date()
    @State private var installmentEnabled = false
    @State private var installmentTotal = ""
    @State private var errorMessage: String?

    private var accounts: [AccountRow] { store.accounts }
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) { ForEach(Kind.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                    HStack {
                        Text("Amount"); Spacer()
                        TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    if kind == .transfer {
                        Picker("From", selection: $fromAccountId) { ForEach(accounts) { Text($0.name ?? "—").tag($0.id) } }
                        Picker("To", selection: $accountId) { ForEach(accounts) { Text($0.name ?? "—").tag($0.id) } }
                    } else {
                        Picker("Account", selection: $accountId) { ForEach(accounts) { Text($0.name ?? "—").tag($0.id) } }
                        Picker("Category", selection: $categoryId) { ForEach(categories) { Text($0.name).tag($0.id) } }
                    }
                }

                Section {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    if frequency == "monthly" {
                        Stepper("Day of month: \(dayOfMonth)", value: $dayOfMonth, in: 1...28)
                    }
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                }

                Section {
                    Toggle("Installment plan", isOn: $installmentEnabled)
                    if installmentEnabled {
                        HStack {
                            Text("Number of payments"); Spacer()
                            TextField("12", text: $installmentTotal).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Add Scheduled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onAppear(perform: seedDefaults)
        }
    }

    private func seedDefaults() {
        if accountId.isEmpty { accountId = accounts.first?.id ?? "" }
        if fromAccountId.isEmpty { fromAccountId = accounts.dropFirst().first?.id ?? accounts.first?.id ?? "" }
        if categoryId.isEmpty || !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? ""
        }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard let value = Double(amount), value > 0 else { errorMessage = "Enter an amount."; return }
        if kind == .transfer, fromAccountId == accountId { errorMessage = "Pick two different accounts."; return }

        var args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "name": .string(name),
            "type": .string(kind.rawValue), "amount": .double(value),
            "accountId": .string(accountId), "frequency": .string(frequency),
            "startDate": .string(Self.day(startDate)),
        ]
        if frequency == "monthly" { args["dayOfMonth"] = .double(Double(dayOfMonth)) }
        if kind == .transfer { args["fromAccountId"] = .string(fromAccountId) }
        else if !categoryId.isEmpty { args["category"] = .string(categoryId) }
        if installmentEnabled, let n = Int(installmentTotal), n > 0 {
            args["installmentTotal"] = .double(Double(n))
        }
        do {
            try store.apply(.createScheduled, Args(args))
            dismiss()
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
}
