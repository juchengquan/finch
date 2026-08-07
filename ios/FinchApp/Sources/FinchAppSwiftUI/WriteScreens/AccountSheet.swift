import SwiftUI
import FinchCore

/// Add or edit an account. `nil` account = add (`createAccount`); otherwise edit
/// (`updateAccount`). Currency is **add-only** (the engine intentionally doesn't
/// patch it); opening balance is editable — changes go through the native-first
/// `setOpeningBalance` action (rewrites the open-<id> entry). Routes through
/// FinchStore.apply.
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
        if let ob = account?.openingBalance, ob != 0 {
            _openingBalance = State(initialValue: String(format: "%g", ob))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FieldRow(glyph: .name, title: "Name") {
                        TextField("Name", text: $name)
                    }
                    FieldRow(glyph: .icon, title: "Type", showsDefaultTrailing: false) {
                        Picker("Type", selection: $type) {
                            ForEach(Self.types, id: \.self) { Text(Self.typeLabel($0)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    if isEdit {
                        FieldRow(glyph: .currency, title: "Currency") { Text(currency) }   // not editable post-creation
                    } else {
                        FieldRow(glyph: .currency, title: "Currency", showsDefaultTrailing: false) {
                            Picker("Currency", selection: $currency) {
                                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                    FieldRow(glyph: .group, title: "Group", showsDefaultTrailing: false) {
                        Picker("Group", selection: $groupId) {
                            Text("None").tag("")
                            ForEach(store.accountGroups) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                    }
                    if isEdit {
                        FieldRow(glyph: .status, title: "Include in net worth") {
                            Toggle("Include in net worth", isOn: $includeInNetWorth).switchOnlyToggles()
                        }
                    }
                }

                Section {
                    FieldRow(glyph: .amount, title: "Amount") {
                        TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: currency)),
                                  text: $openingBalance)
                            .moneyInput($openingBalance, currency: currency)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    finchSectionHeader("Opening balance")
                } footer: {
                    if isEdit {
                        Text("The balance before finch started tracking, in the account's currency. Changing it adjusts the account's balance.")
                    }
                }

                Section {
                    FieldRow(glyph: .color, title: "Color") {
                        HStack(spacing: 14) {
                            ForEach(Self.palette, id: \.hex) { swatch in
                                Circle().fill(swatch.color).frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == swatch.hex ? 2.5 : 0))
                                    .onTapGesture { colorHex = (colorHex == swatch.hex ? "" : swatch.hex) }
                                    .accessibilityLabel("Color \(swatch.hex)")
                            }
                        }
                    }
                } header: {
                    finchSectionHeader("Color")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "Edit Account" : "Add Account")
            .finchSheetForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
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
            do {
                try store.apply(.updateAccount, Args(["id": .string(account.id), "patch": .object(patch)]))
                // Opening balance rides along only when it actually changed —
                // its own action, since it rewrites the open-<id> entry.
                let newOpening = DecimalInput.parse(openingBalance) ?? 0
                if newOpening != (account.openingBalance ?? 0) {
                    try store.apply(.setOpeningBalance,
                                    Args(["id": .string(account.id), "amount": .double(newOpening)]))
                }
                dismiss()
            }
            catch { errorMessage = i18nMessage(error) }
        } else {
            var args: [String: JSONValue] = [
                "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                "type": .string(type), "currency": .string(currency),
            ]
            if !groupId.isEmpty { args["groupId"] = .string(groupId) }
            if !colorHex.isEmpty { args["color"] = .string(colorHex) }
            if let ob = DecimalInput.parse(openingBalance), ob != 0 { args["openingBalance"] = .double(ob) }
            do { try store.apply(.createAccount, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }
}
