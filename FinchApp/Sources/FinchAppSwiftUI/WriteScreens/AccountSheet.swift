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

    // Detail fields (schema 2026-08-12). Days are 0 = "not set" in the picker,
    // stored as NULL — a card with no statement day is normal, not day zero.
    @State private var icon = ""
    @State private var notes = ""
    @State private var institution = ""
    @State private var last4 = ""
    @State private var statementDay = 0
    @State private var dueDay = 0
    @State private var creditLimit = ""
    @State private var openingDate = Date()
    @State private var hasOpeningDate = false

    /// Basic holds what every account needs; Advanced holds what most never set.
    /// A save error switches back to whichever tab owns the offending field —
    /// otherwise the message lands on a screen you cannot see.
    private enum Tab: Hashable { case basic, advanced }
    @State private var tab: Tab = .basic

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
            _openingBalance = State(initialValue: DecimalInput.text(ob, currency: account?.currency ?? defaultCurrency))
        }
        _icon = State(initialValue: account?.icon ?? "")
        _notes = State(initialValue: account?.notes ?? "")
        _institution = State(initialValue: account?.institution ?? "")
        _last4 = State(initialValue: account?.accountLast4 ?? "")
        _statementDay = State(initialValue: account?.statementDay ?? 0)
        _dueDay = State(initialValue: account?.dueDay ?? 0)
        if let cl = account?.creditLimit {
            _creditLimit = State(initialValue: DecimalInput.text(cl, currency: account?.currency ?? defaultCurrency))
        }
        if let d = account?.openingDate, let parsed = AppDate.isoDay.date(from: d) {
            _openingDate = State(initialValue: parsed)
            _hasOpeningDate = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                ViewModePickerRow(selection: $tab,
                                  options: [(.basic, String(localized: "Basic")),
                                            (.advanced, String(localized: "Advanced"))])
                if tab == .basic { basicFields } else { advancedFields }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
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

    @ViewBuilder private var basicFields: some View {
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
        } footer: {
            // Says what is not obvious from the labels, and NOTHING that merely restates
            // them — "Name: the account's name" is noise, and noise trains people to stop
            // reading footers, which is what makes the one useful sentence invisible.
            //
            // The currency line is the one that costs real money to learn late: it is
            // fixed once the account exists, which is why the row goes read-only on edit
            // rather than silently refusing later.
            if isEdit {
                Text("Currency can't be changed after an account is created — it is what every balance on this account is recorded in.")
            } else {
                Text("Currency is fixed once the account is created. Type decides how the balance is read: a credit card counts what you owe, so its balance is normally negative.")
            }
        }

        // Card cycle sits in Basic, not Advanced: these are what DEFINE a credit
        // card, and behind a tab most cards would never get one set. Hidden
        // entirely for other types rather than shown disabled.
        if type == "credit_card" {
            Section {
                dayRow(title: "Statement closes", selection: $statementDay)
                dayRow(title: "Payment due", selection: $dueDay)
                FieldRow(glyph: .amount, title: "Credit limit") {
                    TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: currency)),
                              text: $creditLimit)
                        .moneyInput($creditLimit, currency: currency)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                finchSectionHeader("Credit card")
            } footer: {
                Text("A day past the end of a short month falls on that month's last day.")
            }
        }

        Section {
            FieldRow(glyph: .amount, title: "Amount") {
                TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: currency)),
                          text: $openingBalance)
                    .moneyInput($openingBalance, currency: currency)
                    .keyboardType(.decimalPad)
            }
            // The date the opening figure applies FROM. Without it the entry is
            // stamped today, which is wrong for an account you are back-filling —
            // the figure means nothing without the date it starts at.
            FieldRow(glyph: .date, title: "As of", showsDefaultTrailing: false) {
                DatePicker("As of", selection: $openingDate, displayedComponents: [.date])
                    .labelsHidden()
                    .onChange(of: openingDate) { _, _ in hasOpeningDate = true }
            }
        } header: {
            finchSectionHeader("Opening balance")
        } footer: {
            // The ADD case was silent, which is backwards: someone editing has already
            // met these fields, and someone creating an account has not. "As of" in
            // particular means nothing until you are told what it anchors.
            if isEdit {
                Text("The balance before finch started tracking, in the account's currency. Changing it adjusts the account's balance.")
            } else {
                Text("What the account held before finch started tracking it, and the date that figure is from. Leave the amount empty for a new account starting at zero.")
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
    }

    @ViewBuilder private var advancedFields: some View {
        Section {
            IconPickerRow(title: "Icon", glyph: .icon, selection: $icon)
            FieldRow(glyph: .account, title: "Institution") {
                TextField("Bank or issuer", text: $institution)
            }
            FieldRow(glyph: .card, title: "Last 4 digits") {
                TextField("0000", text: $last4)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: last4) { _, v in
                        // Four digits, digits only. Stored as text so a leading
                        // zero survives; only the last four, never the full number.
                        last4 = String(v.filter(\.isNumber).prefix(4))
                    }
            }
        } footer: {
            Text("Only the last four digits — enough to tell cards apart on a statement.")
        }

        Section {
            FieldRow(glyph: .note, title: "Note") {
                TextField("Note (optional)", text: $notes, axis: .vertical)
            }
        }

        if isEdit, let account {
            Section {
                FieldRow(glyph: .status, title: "Include in net worth") {
                    Toggle("Include in net worth", isOn: $includeInNetWorth).switchOnlyToggles()
                }
                // Edit only: a budget cannot name an account that does not exist yet,
                // and the row writes to the BUDGETS, not to this sheet's own state.
                AccountBudgetsRow(accountId: account.id)
            }
        }
    }

    /// Day-of-month picker; 0 renders as "Not set" and stores NULL.
    ///
    /// Unlike every other row here, the picker keeps its LABEL. `FieldRow` shows
    /// its title only while the row is empty and otherwise lets the glyph carry
    /// the field's identity — which works when each field owns a distinct glyph.
    /// These two are both dates and both read "Not set", so glyph-only made them
    /// literally indistinguishable on screen.
    @ViewBuilder private func dayRow(title: String, selection: Binding<Int>) -> some View {
        FieldRow(glyph: .date, title: LocalizedStringKey(title), showsDefaultTrailing: false) {
            Picker(LocalizedStringKey(title), selection: selection) {
                Text("Not set").tag(0)
                ForEach(1...31, id: \.self) { Text(Self.ordinal($0)).tag($0) }
            }
        }
    }

    private static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var currencyOptions: [String] {
        Self.currencies.contains(currency) ? Self.currencies : [currency] + Self.currencies
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            // Name lives on Basic; surfacing its error while Advanced is showing
            // would put the message on a screen the user cannot see.
            tab = .basic
            errorMessage = "Enter a name."
            return
        }

        // Card fields are only meaningful on a card. They are NOT cleared when
        // the type changes — switching type by mistake would silently discard a
        // limit and two days you would then have to look up again.
        let isCard = type == "credit_card"
        let dayValue: (Int) -> JSONValue = { $0 == 0 ? .null : .int($0) }
        let limitValue: JSONValue = {
            guard isCard, let v = DecimalInput.parse(creditLimit) else { return .null }
            return .double(v)
        }()
        let textValue: (String) -> JSONValue = { t in
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? .null : .string(s)
        }

        if let account {
            var patch: [String: JSONValue] = [
                "name": .string(trimmed), "type": .string(type),
                "includeInNetWorth": .int(includeInNetWorth ? 1 : 0),
                "groupId": groupId.isEmpty ? .null : .string(groupId),
                "icon": textValue(icon),
                "notes": textValue(notes),
                "institution": textValue(institution),
                "accountLast4": textValue(last4),
                "creditLimit": limitValue,
            ]
            if isCard {
                patch["statementDay"] = dayValue(statementDay)
                patch["dueDay"] = dayValue(dueDay)
            }
            // Colour clears on explicit null, like every other optional here —
            // without this, deselecting a swatch could never be saved.
            patch["color"] = colorHex.isEmpty ? .null : .string(colorHex)
            do {
                try store.apply(.updateAccount, Args(["id": .string(account.id), "patch": .object(patch)]))
                // Opening balance rides along only when the amount OR the date
                // changed — its own action, since it rewrites the open-<id> entry.
                let newOpening = DecimalInput.parse(openingBalance) ?? 0
                let newDate = AppDate.isoDay.string(from: openingDate)
                let dateChanged = hasOpeningDate && newDate != (account.openingDate ?? "")
                if newOpening != (account.openingBalance ?? 0) || dateChanged {
                    var a: [String: JSONValue] = ["id": .string(account.id), "amount": .double(newOpening)]
                    if hasOpeningDate { a["date"] = .string(newDate) }
                    try store.apply(.setOpeningBalance, Args(a))
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
            for (key, value) in ["icon": icon, "notes": notes,
                                 "institution": institution, "accountLast4": last4] {
                if case .string(let v) = textValue(value) { args[key] = .string(v) }
            }
            if isCard {
                if statementDay != 0 { args["statementDay"] = .int(statementDay) }
                if dueDay != 0 { args["dueDay"] = .int(dueDay) }
                if let v = DecimalInput.parse(creditLimit) { args["creditLimit"] = .double(v) }
            }
            if let ob = DecimalInput.parse(openingBalance), ob != 0 {
                args["openingBalance"] = .double(ob)
                if hasOpeningDate { args["openingDate"] = .string(AppDate.isoDay.string(from: openingDate)) }
            }
            do { try store.apply(.createAccount, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }
}
