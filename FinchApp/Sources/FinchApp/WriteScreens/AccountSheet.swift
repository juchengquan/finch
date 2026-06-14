import SwiftUI
import FinchCore

/// Add or edit an account. `nil` account = add (`createAccount`); otherwise edit
/// (`updateAccount`). Currency is **add-only** (the engine intentionally doesn't
/// patch it); opening balance is add-only. Routes through FinchStore.apply.
struct AccountSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let account: AccountRow?

    @State private var name: String
    @State private var type: String
    @State private var currency: String
    @State private var groupId: String          // "" = none
    @State private var openingBalance = ""
    @State private var colorHex = ""             // "" = none
    @State private var includeInNetWorth: Bool
    @State private var errorMessage: String?

    private var isEdit: Bool { account != nil }

    private static let types = ["cash", "savings", "credit_card", "investment", "fx", "virtual"]
    private static func typeLabel(_ t: String) -> String {
        switch t {
        case "credit_card": return "Credit Card"
        case "fx": return "Foreign Currency"
        default: return t.capitalized
        }
    }
    private static let currencies = ["USD", "EUR", "GBP", "JPY", "SGD", "CNY", "AUD", "CAD", "CHF", "HKD", "INR"]
    private static let palette: [(hex: String, color: Color)] = [
        ("#1f3a5f", .blue), ("#2e7d32", .green), ("#c62828", .red),
        ("#6a1b9a", .purple), ("#ef6c00", .orange), ("#00838f", .teal),
    ]

    init(account: AccountRow? = nil, defaultCurrency: String = "USD") {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? "cash")
        _currency = State(initialValue: account?.currency ?? defaultCurrency)
        _groupId = State(initialValue: account?.groupId ?? "")
        _includeInNetWorth = State(initialValue: (account?.includeInNetWorth ?? 1) == 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(Self.types, id: \.self) { Text(Self.typeLabel($0)).tag($0) }
                    }
                    if isEdit {
                        LabeledContent("Currency", value: currency)   // not editable post-creation
                    } else {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Picker("Group", selection: $groupId) {
                        Text("None").tag("")
                        ForEach(store.accountGroups) { Text($0.name).tag($0.id) }
                    }
                }

                if !isEdit {
                    Section("Opening balance") {
                        HStack {
                            Text("Amount"); Spacer()
                            TextField("0.00", text: $openingBalance)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                }

                if isEdit {
                    Section { Toggle("Include in net worth", isOn: $includeInNetWorth) }
                }

                Section("Color") {
                    HStack(spacing: 14) {
                        ForEach(Self.palette, id: \.hex) { swatch in
                            Circle().fill(swatch.color).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == swatch.hex ? 2.5 : 0))
                                .onTapGesture { colorHex = (colorHex == swatch.hex ? "" : swatch.hex) }
                                .accessibilityLabel("Color \(swatch.hex)")
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "Edit Account" : "Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private var currencyOptions: [String] {
        Self.currencies.contains(currency) ? Self.currencies : [currency] + Self.currencies
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }

        if let account {
            var patch: [String: JSONValue] = [
                "name": .string(trimmed), "type": .string(type),
                "includeInNetWorth": .int(includeInNetWorth ? 1 : 0),
                "groupId": groupId.isEmpty ? .null : .string(groupId),
            ]
            if !colorHex.isEmpty { patch["color"] = .string(colorHex) }
            do { try store.apply(.updateAccount, Args(["id": .string(account.id), "patch": .object(patch)])); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        } else {
            var args: [String: JSONValue] = [
                "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                "type": .string(type), "currency": .string(currency),
            ]
            if !groupId.isEmpty { args["groupId"] = .string(groupId) }
            if !colorHex.isEmpty { args["color"] = .string(colorHex) }
            if let ob = Double(openingBalance), ob != 0 { args["openingBalance"] = .double(ob) }
            do { try store.apply(.createAccount, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }
}
