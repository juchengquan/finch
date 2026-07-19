import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FinchCore

/// Add Transaction — the flagship write screen (port of the web add-expense-form).
/// Expense/income post one account leg + an auto-balanced category leg through
/// `addTransaction`; transfer posts two account legs through `createTransfer`.
/// Everything routes the FinchStore.apply chokepoint, which re-derives the base
/// figure + applies rules. The amount field is in the account's own currency.
struct AddTransactionSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    /// Optionally pre-select the account (e.g. when added from an account's
    /// detail screen). Falls back to the first account when nil.
    var defaultAccountId: String? = nil
    /// Optionally pre-select the category (e.g. when added from a budget's
    /// detail screen). Falls back to the first category when nil or not in the
    /// current kind's category list.
    var defaultCategoryId: String? = nil
    /// Duplicate flow: seed the form from an existing transaction (kind, amount,
    /// merchant, category, account, currency, tags). Date stays today and the
    /// note stays blank — a duplicate is a new event; the user confirms via Save.
    var prefill: Tx? = nil

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer, refund
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var iconName: String { TxnKindIcon.icon(for: rawValue) }
    }

    @State private var kind: Kind = .expense
    @State private var amount = ""
    @State private var merchant = ""
    @State private var categoryId = ""
    @State private var accountId = ""
    @State private var fromAccountId = ""
    @State private var toAccountId = ""
    @State private var received = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var currencyCode = ""
    @State private var errorMessage: String?
    @State private var pendingDuplicate: DuplicateMatch?   // soft duplicate nudge
    @State private var dupConfirmed = false
    @State private var status: Entries.Status = .confirmed
    @State private var selectedTags: Set<String> = []
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var pickedFileURL: URL?
    @State private var createCounterpartyOnSave = false   // set by the "Create <name>" row
    @State private var prefillApplied = false             // duplicate-prefill runs once
    @State private var pendingSplits: [SplitEditorView.DraftSplit]? = nil
    @State private var showingSplit = false
    @State private var refundedTxId: String? = nil
    @State private var showingRefundPicker = false

    private var accounts: [AccountRow] { store.accounts }

    /// Expense / income / refund all post a single account leg + category — they
    /// share the line-item field set and the status/tags/receipt/merchant extras.
    private var isLineItem: Bool { kind == .expense || kind == .income || kind == .refund }

    private var refundedSummary: String {
        guard let id = refundedTxId, let tx = store.txns.first(where: { $0.id == id }) else { return "Optional" }
        return tx.merchant.isEmpty ? tx.date : tx.merchant
    }

    /// The account currency + any currency with a known rate — the choices for a
    /// foreign-currency entry. (When the picked currency ≠ the account's, the
    /// engine carries orig_amount/orig_currency and converts.)
    private var currencyOptions: [String] {
        var set = Set(accounts.compactMap { $0.currency })
        set.formUnion(store.exchangeRates.map { $0.currency })
        set.insert(currency(of: accountId))
        return set.sorted()
    }

    /// Expense → expense categories; income → income categories.
    private var categories: [CategoryRow] {
        categories(for: kind)
    }
    private func categories(for k: Kind) -> [CategoryRow] {
        store.pickableCategories.filter { k == .income ? $0.kind == "income" : $0.kind != "income" }
    }

    private func currency(of accountId: String) -> String {
        accounts.first { $0.id == accountId }?.currency ?? store.displayCurrency
    }
    private var transferIsCrossCurrency: Bool {
        kind == .transfer && currency(of: fromAccountId) != currency(of: toAccountId)
    }

    var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                // Page-style TabView so a horizontal swipe interactively drags the
                // next type's form in with the finger. The type switcher's Liquid
                // Glass is the self-contained glass THUMB on TxTypeControl (not the
                // toolbar refracting scrolled content), so the pager doesn't affect
                // it — swipe and glass coexist.
                TabView(selection: $kind) {
                    ForEach(Kind.allCases) { k in
                        formPage(k).tag(k)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Color(uiColor: .systemGroupedBackground))
                #else
                formPage(kind)
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                // Transaction type — the shared glass control (sliding glass thumb).
                // Native segmented Picker — same control as the Theme toggle in
                // Settings › Appearance, so it gets the system's crystal Liquid
                // Glass selection (a custom View can't reproduce that).
                ToolbarItem(placement: .principal) {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { k in
                            Image(systemName: k.iconName).accessibilityLabel(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
                        // Anchored on ✓ — the save that raised it (iOS 26
                        // positions popouts at their source).
                        .confirmationDialog("Possible duplicate", isPresented: Binding(
                            get: { pendingDuplicate != nil }, set: { if !$0 { pendingDuplicate = nil } }),
                            presenting: pendingDuplicate) { _ in
                            Button("Add anyway") { dupConfirmed = true; pendingDuplicate = nil; save() }
                            Button("Cancel", role: .cancel) { pendingDuplicate = nil }
                        } message: { m in
                            Text("Looks like “\(m.merchant)” on \(m.date) already exists.")
                        }
                }
            }
            .onAppear(perform: seedDefaults)
            // Auto-categorize from the merchant's history (the user can still override).
            .onChange(of: merchant) { _, m in
                createCounterpartyOnSave = false
                guard kind != .transfer, !m.isEmpty else { return }
                if let s = Selectors.suggestCategory(store.txns, store.activeLedgerId, m),
                   categories.contains(where: { $0.id == s.categoryId }) {
                    categoryId = s.categoryId
                }
            }
            .onChange(of: amount) { _, _ in pendingSplits = nil }
            .sheet(isPresented: $showingSplit) {
                SplitEditorView(
                    total: abs(DecimalInput.parse(amount) ?? 0),
                    isIncome: kind == .income,
                    currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode,
                    initialSplits: pendingSplits ?? (categoryId.isEmpty ? nil : [(categoryId: categoryId, amount: abs(DecimalInput.parse(amount) ?? 0))]),
                    target: .draft(onSave: { pendingSplits = $0 }))
            }
            .sheet(isPresented: $showingRefundPicker) {
                RefundSourcePickerView { refundedTxId = $0 }
            }
            .onChange(of: kind) { _, k in if k != .refund { refundedTxId = nil } }
        }
    }


    @ViewBuilder private func formPage(_ k: Kind) -> some View {
            Form {
                Section {
                    Text(k.label)   // names the icon-only type control above
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                #if os(iOS)
                // Pull the label close to the nav bar and to the first section —
                // it's a caption for the type control above, not a section of its own.
                .listSectionSpacing(6)
                #endif
                if k == .transfer {
                    transferFields
                } else {
                    expenseIncomeFields(for: k)
                }

                Section {
                    Picker("Status", selection: $status) {
                        Text("Confirmed").tag(Entries.Status.confirmed)
                        Text("Pending").tag(Entries.Status.pending)
                    }
                }
                if !store.tags.isEmpty {
                    Section("Tags") { TagChipFlow(tags: store.tags, selected: $selectedTags) }
                }
                if k == .expense || k == .income || k == .refund {
                    Section("Receipt") {
                        #if os(macOS)
                        Button { showingFileImporter = true } label: {
                            Label(pickedFileURL == nil ? "Add receipt…" : "Receipt selected", systemImage: "paperclip")
                        }
                        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf]) { result in
                            if case .success(let url) = result { pickedFileURL = url }
                        }
                        #else
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(pickedPhoto == nil ? "Add receipt photo" : "Receipt photo selected", systemImage: "camera")
                        }
                        #endif
                    }
                }
                if k == .expense || k == .income || k == .refund {
                    detailsSection(for: k)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            #if os(iOS)
            .contentMargins(.top, 6, for: .scrollContent)
            #endif
    }

    @ViewBuilder private func expenseIncomeFields(for k: Kind) -> some View {
        Section {
            SearchablePickerRow(title: "Account",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
            amountField
            if pendingSplits == nil {
                SearchablePickerRow(title: "Category",
                    options: categories(for: k).map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
            }
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, AppDate.h24Locale)
            if k != .refund, DecimalInput.parse(amount) ?? 0 != 0 {
                Button {
                    showingSplit = true
                } label: {
                    HStack {
                        Text(pendingSplits == nil ? "Split…" : "Split across \(pendingSplits!.count) categories")
                        Spacer()
                        if pendingSplits != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if k == .refund {
                Button { showingRefundPicker = true } label: {
                    HStack {
                        Text("Refunds")
                        Spacer()
                        Text(refundedSummary).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Merchant/Source + Note — optional free-text, shown as the LAST section.
    @ViewBuilder private func detailsSection(for k: Kind) -> some View {
        Section("Details") {
            HStack {
                Text(k == .income ? "Source" : "Merchant"); Spacer()
                TextField("", text: $merchant).multilineTextAlignment(.trailing)
            }
            merchantSuggestionRows
            HStack {
                Text("Note"); Spacer()
                TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
            }
        }
    }

    /// Existing counterparties (active ledger) whose name contains the typed
    /// merchant text, minus an exact match (nothing to suggest there). Capped at 5.
    private var matchingCounterparties: [Counterparty] {
        let t = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        return Array(store.counterparties
            .filter { $0.name.localizedCaseInsensitiveContains(t)
                   && $0.name.caseInsensitiveCompare(t) != .orderedSame }
            .prefix(5))
    }

    /// Suggestion rows shown beneath the Merchant field: matching counterparties
    /// to pick (the engine links them by name on save), plus a "Create <name>" row
    /// for a brand-new name (flagged to create on save). Empty for non-expense/income
    /// or an empty/exact-match field.
    @ViewBuilder private var merchantSuggestionRows: some View {
        let t = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLineItem, !t.isEmpty {
            ForEach(matchingCounterparties) { cp in
                Button { pickCounterparty(cp.name) } label: {
                    Label(cp.name, systemImage: "building.2").font(.callout)
                }
            }
            if !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) {
                Button { createCounterpartyOnSave = true } label: {
                    Label("Create “\(t)”", systemImage: "plus.circle").font(.callout)
                }
            }
        }
    }

    private func pickCounterparty(_ name: String) {
        merchant = name
        createCounterpartyOnSave = false
    }

    @ViewBuilder private var transferFields: some View {
        Section {
            SearchablePickerRow(title: "From",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $fromAccountId)
            SearchablePickerRow(title: "To",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $toAccountId)
            // Always TWO amount rows, each in its account's own currency. Same
            // currency → the To row mirrors From (disabled); cross-currency →
            // the To row is the independent received amount.
            transferAmountRow("From amount", text: $amount, currency: currency(of: fromAccountId))
            if transferIsCrossCurrency {
                transferAmountRow("To amount", text: $received, currency: currency(of: toAccountId))
            } else {
                transferAmountRow("To amount", text: $amount, currency: currency(of: toAccountId), mirrored: true)
            }
        }
    }

    /// Line-item amount row: Amount + the currency menu inline (currency is
    /// ALWAYS visible, even when only one option exists).
    private var amountField: some View {
        HStack {
            Text("Amount")
            Spacer()
            TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            Picker("", selection: $currencyCode) {
                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
        }
    }

    /// Transfer amount row: fixed currency label from the leg's account (the
    /// account owns the currency — no picker). `mirrored` renders the
    /// same-currency To row: disabled, live-synced to the From field.
    private func transferAmountRow(_ label: String, text: Binding<String>, currency: String, mirrored: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.00", text: text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .disabled(mirrored)
                .foregroundStyle(mirrored ? Color.secondary : Color.primary)
            Text(currency).foregroundStyle(.secondary)
        }
    }

    private func toggleTag(_ id: String) {
        if selectedTags.contains(id) { selectedTags.remove(id) } else { selectedTags.insert(id) }
    }

    /// Default the pickers to the first valid option (and the first two distinct
    /// accounts for a transfer) once the projected store is available.
    private func seedDefaults() {
        // Duplicate flow: seed once from the source transaction, then let the
        // fallback logic below fill anything still empty.
        if let p = prefill, !prefillApplied {
            prefillApplied = true
            kind = p.kind == "income" ? .income : .expense
            amount = String(format: "%g", abs(p.nativeAmount ?? p.amount))
            merchant = p.merchant
            if let c = p.category { categoryId = c }
            accountId = p.account
            if let cur = p.currency { currencyCode = cur }
            if let tags = p.tags { selectedTags = Set(tags) }
        }
        if accountId.isEmpty {
            let preferred = defaultAccountId.flatMap { id in accounts.first { $0.id == id }?.id }
            accountId = preferred ?? accounts.first?.id ?? ""
        }
        if categoryId.isEmpty || !categories.contains(where: { $0.id == categoryId }) {
            let preferred = defaultCategoryId.flatMap { id in categories.first { $0.id == id }?.id }
            categoryId = preferred ?? categories.first?.id ?? ""
        }
        if fromAccountId.isEmpty { fromAccountId = accounts.first?.id ?? "" }
        if toAccountId.isEmpty { toAccountId = accounts.dropFirst().first?.id ?? accounts.first?.id ?? "" }
        if currencyCode.isEmpty { currencyCode = currency(of: accountId) }
    }

    private func save() {
        errorMessage = nil
        // Keep category valid when the type toggles between expense/income.
        if kind != .transfer, !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? ""
        }
        guard let value = DecimalInput.parse(amount), value != 0 else { errorMessage = "Enter an amount."; return }
        let ymd = Self.day(date)
        let hm = Self.time(date)
        // Soft duplicate nudge (expense/income only) — show once, before posting.
        if kind != .transfer, !dupConfirmed,
           let m = Selectors.findDuplicate(store.txns, store.activeLedgerId,
               DuplicateDraft(merchant: merchant, amount: abs(value), accountId: accountId, date: ymd, excludeId: nil)) {
            pendingDuplicate = m
            return
        }
        do {
            if kind == .transfer {
                guard fromAccountId != toAccountId else { errorMessage = "Pick two different accounts."; return }
                var args: [String: JSONValue] = [
                    "fromAccountId": .string(fromAccountId), "toAccountId": .string(toAccountId),
                    "fromAmount": .double(abs(value)), "date": .string(ymd), "time": .string(hm),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                if transferIsCrossCurrency {
                    guard let recv = DecimalInput.parse(received), recv > 0 else {
                        errorMessage = "Enter the received amount."; return
                    }
                    args["toAmount"] = .double(recv)
                }
                args["status"] = .string(status.rawValue)
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
                try store.apply(.createTransfer, Args(args))
            } else {
                let signed = (kind == .income || kind == .refund) ? abs(value) : -abs(value)
                let fallback = kind == .income ? "Income" : (kind == .refund ? "Refund" : "Untitled")
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "accountId": .string(accountId),
                    "amount": .double(signed), "merchant": .string(merchant.isEmpty ? fallback : merchant),
                    "categoryId": .string(categoryId), "date": .string(ymd), "time": .string(hm),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                // Foreign-currency entry: pass the chosen currency so the engine
                // carries orig_* + converts to the account/base currency.
                if !currencyCode.isEmpty, currencyCode != currency(of: accountId) {
                    args["currency"] = .string(currencyCode)
                }
                args["status"] = .string(status.rawValue)
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
                if createCounterpartyOnSave {
                    let cpName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cpName.isEmpty,
                       !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(cpName) == .orderedSame }) {
                        try store.apply(.createCounterparty, Args([
                            "ledgerId": .string(store.activeLedgerId), "name": .string(cpName)]))
                    }
                }
                if kind == .refund {
                    args["kind"] = .string("refund")
                    if let refundedTxId { args["refundedTransactionId"] = .string(refundedTxId) }
                }
                let eid = try store.applyReturningId(.addTransaction, Args(args))
                if let eid, let splits = pendingSplits {
                    let payload: [JSONValue] = splits.map { .object([
                        "categoryId": $0.categoryId.map(JSONValue.string) ?? .null, "amount": .double($0.amount)]) }
                    try store.apply(.setTransactionSplits, Args(["id": .string(eid), "splits": .array(payload)]))
                }
                if let eid, let photo = pickedPhoto {
                    Task { try? await AttachmentWriter.write(item: photo, entryId: eid, store: store) }
                }
                if let eid, let url = pickedFileURL {
                    Task { try? await AttachmentWriter.writeFile(url: url, entryId: eid, store: store) }
                }
            }
            dismiss()
        } catch {
            errorMessage = i18nMessage(error)   // localizes I18nError (incl. zh), like every other write screen
        }
    }

    // MARK: date/time formatting (local wall clock → stored columns)
    private static let dayFmt = AppDate.isoDay
    private static let timeFmt = AppDate.isoTime
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
}
