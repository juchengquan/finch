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
        case expense, income, transfer, refund, adjust
        var id: String { rawValue }
        var label: String { self == .adjust ? "Adjust Balance" : rawValue.capitalized }
        /// SF Symbol for the segment (adjust reuses the engine's "adjustment" icon).
        var iconName: String { TxnKindIcon.icon(for: self == .adjust ? "adjustment" : rawValue) }
    }

    @State private var kind: Kind = .expense
    /// Width of the icon segmented type control in the nav bar — shared by its
    /// frame and the scrub gesture's per-segment math.
    private static let typeControlWidth: CGFloat = 190
    @State private var amount = ""
    @State private var merchant = ""
    @State private var categoryId = ""
    @State private var accountId = ""
    @State private var fromAccountId = ""
    @State private var toAccountId = ""
    @State private var received = ""
    @State private var targetBalance = ""   // adjust-balance: the account's new balance
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

    /// The pre-26 (and macOS) type control: a system segmented Picker, with the
    /// scrub-anywhere drag on iOS (a native control only drags from the
    /// SELECTED thumb — this picks whichever segment is under the finger).
    private var legacyTypeControl: some View {
        Picker("Type", selection: $kind) {
            ForEach(Kind.allCases) { kind in
                Image(systemName: kind.iconName)
                    .accessibilityLabel(kind.label)
                    .tag(kind)
            }
        }
        .pickerStyle(.segmented)
        // .principal sizes to the item's intrinsic width, so maxWidth: .infinity
        // collapses back to content size. An explicit width is the only lever
        // that sets the segment size (~near-square segments).
        .frame(width: Self.typeControlWidth)
        #if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let all = Kind.allCases
                    let seg = Self.typeControlWidth / CGFloat(all.count)
                    let idx = max(0, min(all.count - 1, Int(v.location.x / seg)))
                    if all[idx] != kind { kind = all[idx] }
                }
        )
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                // Page-style TabView so a horizontal swipe INTERACTIVELY drags the
                // next type's form in with the finger (a .transition can only
                // animate after the state flips). Selection is the same `kind` the
                // toolbar's segmented control drives, so they stay in sync. Each
                // page renders for its own `k` (neighbors pre-render mid-swipe).
                TabView(selection: $kind) {
                    ForEach(Kind.allCases) { k in
                        formPage(k).tag(k)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // The pager's own background shows wherever a page's Form doesn't
                // cover it (behind the bars at rest, page bounce) — paint it the
                // same grouped color so the sheet reads as one surface.
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
                // Transaction type sits in the title slot as an icon segmented control.
                ToolbarItem(placement: .principal) {
                    #if os(iOS)
                    if #available(iOS 26.0, *) {
                        // Liquid Glass variant: the sliding thumb is a glass pill.
                        GlassTypeControl(kind: $kind, width: Self.typeControlWidth)
                    } else {
                        legacyTypeControl
                    }
                    #else
                    legacyTypeControl
                    #endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
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
                } else if k == .adjust {
                    adjustFields
                } else {
                    expenseIncomeFields(for: k)
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, AppDate.h24Locale)   // 24-hour time wheel regardless of device setting
                    HStack {
                        Text("Note"); Spacer()
                        TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                    }
                }

                if k != .adjust {
                    Section {
                        Picker("Status", selection: $status) {
                            Text("Confirmed").tag(Entries.Status.confirmed)
                            Text("Pending").tag(Entries.Status.pending)
                        }
                    }
                    if !store.tags.isEmpty {
                        Section("Tags") {
                            ForEach(store.tags) { tag in
                                Button { toggleTag(tag.id) } label: {
                                    HStack {
                                        Text(tag.name).foregroundStyle(.primary)
                                        Spacer()
                                        if selectedTags.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    }
                                }
                            }
                        }
                    }
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
            amountField
            HStack {
                Text(k == .income ? "Source" : "Merchant"); Spacer()
                TextField("", text: $merchant).multilineTextAlignment(.trailing)
            }
            merchantSuggestionRows
            if pendingSplits == nil {
                SearchablePickerRow(title: "Category",
                    options: categories(for: k).map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
            }
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
            SearchablePickerRow(title: "Account",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
            if currencyOptions.count > 1 {
                Picker("Currency", selection: $currencyCode) {
                    ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
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
            amountField
            SearchablePickerRow(title: "From",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $fromAccountId)
            SearchablePickerRow(title: "To",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $toAccountId)
            if transferIsCrossCurrency {
                HStack {
                    Text("Received (\(currency(of: toAccountId)))")
                    Spacer()
                    TextField("0.00", text: $received).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var amountField: some View {
        HStack {
            Text("Amount")
            Spacer()
            TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var adjustFields: some View {
        Section {
            SearchablePickerRow(title: "Account",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
            HStack {
                Text("New balance"); Spacer()
                // numbersAndPunctuation allows a leading minus (e.g. a credit-card balance).
                TextField("0.00", text: $targetBalance).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
            }
        } footer: {
            Text("Posts an adjustment for the difference from the account's current balance.")
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
        if kind == .adjust {
            guard let target = DecimalInput.parse(targetBalance) else { errorMessage = "Enter a new balance."; return }
            do {
                var args: [String: JSONValue] = [
                    "accountId": .string(accountId), "targetBalance": .double(target), "date": .string(Self.day(date)),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                try store.apply(.adjustAccountBalance, Args(args))
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
            return
        }
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

#if os(iOS)
/// The OS 26 type control: icon segments with a **Liquid Glass** sliding
/// thumb. Touch-down anywhere selects the segment under the finger and the
/// glass pill glides with the scrub (and with page swipes / taps).
@available(iOS 26.0, *)
private struct GlassTypeControl: View {
    @Binding var kind: AddTransactionSheet.Kind
    let width: CGFloat
    private let height: CGFloat = 40

    var body: some View {
        let all = AddTransactionSheet.Kind.allCases
        let seg = width / CGFloat(all.count)
        let idx = CGFloat(all.firstIndex(of: kind) ?? 0)
        ZStack(alignment: .leading) {
            // The island: one frosted glass capsule for the whole bar — this is
            // what makes the control read as Liquid Glass even over the flat
            // toolbar (an isolated small pane has nothing to refract).
            Color.clear
                .glassEffect(.regular, in: Capsule())
                .frame(width: width, height: height)
            // The sliding thumb: a soft NEUTRAL pill, like the bottom tab bar's
            // selected-tab pill — the accent color lives on the icon, not the pill.
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: seg - 6, height: height - 8)
                .offset(x: seg * idx + 3)
            HStack(spacing: 0) {
                ForEach(all) { k in
                    Image(systemName: k.iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(k == kind ? Color.accentColor : Color.secondary)
                        .frame(width: seg, height: height)
                        .contentShape(Rectangle())
                        .accessibilityLabel(k.label)
                        .accessibilityAddTraits(k == kind ? .isSelected : [])
                }
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let i = max(0, min(all.count - 1, Int(v.location.x / seg)))
                    if all[i] != kind { kind = all[i] }
                }
        )
        .animation(.snappy(duration: 0.25), value: kind)
    }
}
#endif
