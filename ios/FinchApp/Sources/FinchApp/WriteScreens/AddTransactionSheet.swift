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
    /// Set when the prefill is a scheduled OCCURRENCE ("Post now" on the calendar):
    /// the saved transaction then carries the template link and the occurrence it
    /// fulfils, which is what flips the calendar badge.
    ///
    /// Not inferred from `prefill.sourceTemplateId` — DUPLICATING a scheduled
    /// posting hands over a Tx with that field already set, and a duplicate is an
    /// independent event: re-claiming the source's occurrence would flip that
    /// cell's badge and eat an installment slot.
    var postsScheduledOccurrence = false

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer, refund, adjust
        var id: String { rawValue }
        var label: String { self == .adjust ? "Adjust Balance" : rawValue.capitalized }
        /// SF Symbol for the segment (adjust reuses the engine's "adjustment" icon).
        var iconName: String { TxnKindIcon.icon(for: self == .adjust ? "adjustment" : rawValue) }
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
    @State private var prefillApplied = false             // duplicate-prefill runs once
    @State private var pendingSplits: [SplitEditorView.DraftSplit]? = nil
    @State private var showingSplit = false
    @State private var refundedTxId: String? = nil
    @State private var showingRefundPicker = false
    @State private var targetBalance = ""   // adjust-balance: the account's new balance
    /// Adjust Balance is an opt-in 5th type (Settings › Appearance); it's account
    /// maintenance, so it's hidden by default. Always reachable from an account's ⋯ menu.
    @AppStorage("finch.addSheet.showAdjustBalance") private var showAdjustInAddSheet = false

    private var accounts: [AccountRow] { store.accounts }

    /// Types shown in the segmented control — Adjust Balance only when opted in,
    /// so the default control stays four roomy segments.
    ///
    /// Exception: duplicating an adjustment forces the segment in regardless. The
    /// opt-in defaults OFF, so without this the picker would hold a selection that
    /// isn't among its options — a broken control on the default configuration.
    private var availableKinds: [Kind] {
        Self.availableKinds(postsScheduledOccurrence: postsScheduledOccurrence,
                            showAdjustInAddSheet: showAdjustInAddSheet, prefill: prefill)
    }

    /// Pure — pulled out of the computed property above so it's directly
    /// testable (see `AvailableKindsTests`).
    ///
    /// Posting a scheduled occurrence must never offer Adjust: save()'s .adjust
    /// branch returns early via adjustAccountBalance, which never receives
    /// sourceTemplateId/occurrenceDate — the transaction would post, the sheet
    /// would dismiss, and the calendar badge would silently never flip, with no
    /// feedback that the link was dropped. That check wins over everything else,
    /// including the Duplicate-an-adjustment exception below (moot in practice —
    /// a scheduled template's kind is never "adjustment" — but this keeps the
    /// precedence explicit rather than relying on that fact).
    static func availableKinds(postsScheduledOccurrence: Bool, showAdjustInAddSheet: Bool, prefill: Tx?) -> [Kind] {
        if postsScheduledOccurrence { return Kind.allCases.filter { $0 != .adjust } }
        let showAdjust = showAdjustInAddSheet || prefill.map { Self.prefillKind($0) == .adjust } ?? false
        return showAdjust ? Kind.allCases : Kind.allCases.filter { $0 != .adjust }
    }

    /// Map a source transaction's engine kind onto a sheet segment. Previously this
    /// collapsed everything non-income to `.expense`, which is why Duplicate had to
    /// be hidden on transfers/refunds/adjustments — it would silently have turned a
    /// transfer into an expense.
    static func prefillKind(_ p: Tx) -> Kind {
        switch p.kind {
        case "income":     return .income
        case "transfer":   return .transfer
        case "refund":     return .refund
        case "adjustment": return .adjust
        default:           return .expense
        }
    }

    /// The sourceTemplateId/occurrenceDate link args for a scheduled-occurrence
    /// prefill — empty unless `posts` is true. DUPLICATING a scheduled posting
    /// hands the sheet a real `Tx` that already carries these fields from ITS
    /// OWN template; without this gate, re-linking here would claim that Tx's
    /// occurrence — flipping its calendar badge and consuming an installment
    /// slot the duplicate never earned. A `static` pure function so that
    /// property is machine-checked (`ScheduledLinkArgsTests`), not just
    /// reasoned about in a comment.
    static func scheduledLinkArgs(prefill: Tx?, posts: Bool) -> [String: JSONValue] {
        guard posts, let tid = prefill?.sourceTemplateId else { return [:] }
        var args: [String: JSONValue] = ["sourceTemplateId": .string(tid)]
        if let occ = prefill?.occurrenceDate { args["occurrenceDate"] = .string(occ) }
        return args
    }

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
            // A plain Form (type switches on TAP of the toolbar segmented
            // control), exactly like the Edit sheet. The previous paged TabView
            // enabled finger-swipe between types but sat between the nav bar and
            // the scroll view, breaking the translucent scroll-edge header and
            // the bottom safe-area inset (masked the last row) — dropping it
            // restores the system's native header + bottom behavior for free.
            formPage(kind)
            .finchSheetForm()   // whole-form: every section follows the global gap
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                // Transaction type — the shared glass control (TxnTypeToolbar): a
                // native segmented Picker gets the system's crystal Liquid Glass
                // selection a custom View can't reproduce. `iconName` maps adjust →
                // the "adjustment" icon, so the sheet supplies its own icon closure.
                ToolbarItem(placement: .principal) {
                    TxnTypeToolbar.segmented(availableKinds, selection: $kind,
                        icon: { $0.iconName }, label: { $0.label })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
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
                Section { TxnTypeToolbar.caption(k.label) }   // names the icon-only type control above
                if k == .transfer {
                    transferFields
                } else if k == .adjust {
                    adjustFields
                } else {
                    expenseIncomeFields(for: k)
                }

                // Adjust Balance is account maintenance — no status/tags/receipt/merchant.
                if k != .adjust {
                    Section {
                        Picker("Status", selection: $status) {
                            Text("Confirmed").tag(Entries.Status.confirmed)
                            Text("Pending").tag(Entries.Status.pending)
                        }
                        // Tags is a single row here (wraps to hold all selected), not its own section.
                        if !store.tags.isEmpty {
                            TagField(tags: store.tags, selected: $selectedTags)
                        }
                    }
                }
                if k == .expense || k == .income || k == .refund {
                    Section {
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
                    } header: {
                        finchSectionHeader("Receipt")
                    }
                }
                if k == .expense || k == .income || k == .refund {
                    detailsSection(for: k)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
    }

    @ViewBuilder private func expenseIncomeFields(for k: Kind) -> some View {
        Section {
            SearchablePickerRow(title: "Account",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
            amountField
            CategoryPickerRow(title: "Category", categories: categories(for: k), selection: $categoryId,
                splitSummary: splitSummaryText(categoryNames: (pendingSplits ?? []).map { store.categoryName($0.categoryId) ?? "Uncategorized" }),
                splitEnabled: (DecimalInput.parse(amount) ?? 0) != 0,
                onSplit: k == .refund ? nil : { showingSplit = true })
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, AppDate.h24Locale)
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
        Section {
            MerchantPickerRow(title: k == .income ? "Source" : "Merchant",
                              counterparties: store.counterparties, merchant: $merchant)
            HStack {
                Text("Note"); Spacer()
                TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
            }
        } header: {
            finchSectionHeader("Details")
        }
    }




    /// Adjust Balance — the opt-in 5th type. Posts an `adjustment` for the
    /// difference to the account's target balance (same engine action as the
    /// account-detail sheet). Date-only — `adjustAccountBalance` takes no time.
    @ViewBuilder private var adjustFields: some View {
        Section {
            SearchablePickerRow(title: "Account",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
            HStack {
                Text("New balance"); Spacer()
                // numbersAndPunctuation allows a leading minus (e.g. a credit-card balance).
                TextField("0.00", text: $targetBalance)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .multilineTextAlignment(.trailing)
            }
        } footer: {
            Text("Posts an adjustment for the difference from the account's current balance.")
        }
        Section {
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, AppDate.h24Locale)
            HStack {
                Text("Note"); Spacer()
                TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
            }
        }
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
            // Transfer has no Merchant/category, so Date + Note live here (the
            // reorder moved the shared Date/Note section into the line-item path).
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, AppDate.h24Locale)
            HStack {
                Text("Note"); Spacer()
                TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
            }
        }
    }

    /// Line-item amount row: Amount + the currency menu inline (currency is
    /// ALWAYS visible, even when only one option exists).
    private var amountField: some View {
        HStack {
            Text("Amount")
            Spacer()
            TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).numericInput($amount)
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
            TextField("0.00", text: text).numericInput(text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .disabled(mirrored)
                .foregroundStyle(mirrored ? Color.secondary : Color.primary)
            Text(currency).foregroundStyle(.secondary)
        }
    }


    /// Default the pickers to the first valid option (and the first two distinct
    /// accounts for a transfer) once the projected store is available.
    private func seedDefaults() {
        // Duplicate flow: seed once from the source transaction, then let the
        // fallback logic below fill anything still empty.
        if let p = prefill, !prefillApplied {
            prefillApplied = true
            kind = Self.prefillKind(p)
            // 0 leaves the field EMPTY rather than showing a literal "0": that's
            // the variable-amount scheduled template, whose whole point is that
            // the user types the figure. (A zero-amount duplicate was never
            // savable either — `save()` rejects it.)
            let magnitude = abs(p.nativeAmount ?? p.amount)
            amount = magnitude == 0 ? "" : String(format: "%g", magnitude)
            merchant = p.merchant
            // A duplicate is a NEW event, so it keeps today's date — but a
            // scheduled-occurrence prefill must land on the occurrence it
            // fulfils, note included (a transfer has nowhere else to carry it).
            if postsScheduledOccurrence {
                // Seed the OCCURRENCE's calendar day but the CURRENT
                // time-of-day — the silent `postScheduled` path posts at
                // "now", so matching that keeps same-day activity-feed
                // ordering consistent between the two paths (stamping the
                // occurrence at local midnight would otherwise sink it to
                // the bottom of today's list).
                if let occDay = AppDate.isoDay.date(from: p.date) {
                    let now = AppDate.civil.dateComponents([.hour, .minute, .second], from: Date())
                    date = AppDate.civil.date(bySettingHour: now.hour ?? 0, minute: now.minute ?? 0,
                                               second: now.second ?? 0, of: occDay) ?? occDay
                }
                if let n = p.note { note = n }
            }
            if let c = p.category { categoryId = c }
            accountId = p.account
            if let cur = p.currency { currencyCode = cur }
            if let tags = p.tags { selectedTags = Set(tags) }
            switch kind {
            case .transfer:
                // A transfer spans two account legs; the projection is per-leg, so
                // either row can be the one swiped. Pair them by transferGroupId and
                // let the SIGN decide direction (from = the negative leg) — the same
                // rule EditTransactionSheet uses.
                if let gid = p.transferGroupId {
                    let legs = store.txns.filter { $0.transferGroupId == gid }
                    let from = legs.first { ($0.nativeAmount ?? $0.amount) < 0 }
                    let to = legs.first { ($0.nativeAmount ?? $0.amount) > 0 }
                    fromAccountId = from?.account ?? p.account
                    toAccountId = to?.account ?? ""
                    if let f = from { amount = String(format: "%g", abs(f.nativeAmount ?? f.amount)) }
                    // Cross-currency transfers carry a second, independent amount.
                    if let t = to, currency(of: fromAccountId) != currency(of: toAccountId) {
                        received = String(format: "%g", abs(t.nativeAmount ?? t.amount))
                    }
                } else if postsScheduledOccurrence,
                          let tpl = store.scheduled.first(where: { $0.id == p.sourceTemplateId }) {
                    // A scheduled-occurrence prefill has no posted legs to pair —
                    // read both accounts off the template instead. (Same direction
                    // the engine posts: from_account_id → account_id.) Gated on
                    // postsScheduledOccurrence so the safety property (a
                    // Duplicate's Tx never drives this branch) is visible here,
                    // not just three files away in Projection's transferGroupId
                    // invariant.
                    //
                    // A template with no from-account is malformed and never
                    // reaches here: ScheduledTab detects that before presenting
                    // this sheet at all (surfacing the engine's
                    // error.scheduled.missingAccount there), rather than this
                    // sheet quietly falling back to "the first two accounts" and
                    // failing on Save with no way to fix it.
                    if let from = tpl.fromAccountId {
                        fromAccountId = from
                        toAccountId = tpl.accountId
                    }
                }
            case .refund:
                // Kept, not dropped: the sheet shows it and nothing is written until
                // Save, so the user can re-point or clear it deliberately.
                refundedTxId = p.refundedTransactionId
            case .adjust:
                // The sheet asks for a TARGET balance but a Tx only carries the delta,
                // so reproduce the original's EFFECT: apply the same delta again from
                // wherever the balance sits now.
                // account.balance and the target field are both in the ACCOUNT's own
                // currency, so use the native delta rather than the base one.
                let current = store.accounts.first { $0.id == p.account }?.balance ?? 0
                targetBalance = String(format: "%g", current + (p.nativeAmount ?? p.amount))
            case .expense, .income:
                break
            }
        }
        if accountId.isEmpty {
            let preferred = defaultAccountId.flatMap { id in accounts.first { $0.id == id }?.id }
            accountId = preferred ?? accounts.first?.id ?? ""
        }
        // Only seed a category from a prefill/duplicate or an explicit
        // defaultCategoryId — a FRESH add starts uncategorized (no default),
        // so the user makes an intentional choice.
        if !categoryId.isEmpty, !categories.contains(where: { $0.id == categoryId }) {
            categoryId = ""
        }
        if categoryId.isEmpty, let id = defaultCategoryId, categories.contains(where: { $0.id == id }) {
            categoryId = id
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
                    "accountId": .string(accountId), "targetBalance": .double(target),
                    "date": .string(Self.day(date)), "time": .string(Self.time(date)),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                try store.apply(.adjustAccountBalance, Args(args))
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
            return
        }
        // Drop a category that isn't valid for the (possibly toggled) type;
        // stays empty otherwise (uncategorized is allowed).
        if kind != .transfer, !categoryId.isEmpty, !categories.contains(where: { $0.id == categoryId }) {
            categoryId = ""
        }
        guard let value = DecimalInput.parse(amount), value != 0 else { errorMessage = "Enter an amount."; return }
        let ymd = Self.day(date)
        let hm = Self.time(date)
        // Soft duplicate nudge (expense/income only) — show once, before posting.
        if kind != .transfer, !dupConfirmed,
           let m = Selectors.findDuplicate(store.txns, store.activeLedgerId,
               DuplicateDraft(merchant: merchant, amount: abs(value), accountId: accountId, date: ymd, excludeId: nil)) {
            Haptics.warning()
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
                for (k, v) in Self.scheduledLinkArgs(prefill: prefill, posts: postsScheduledOccurrence) { args[k] = v }
                try store.apply(.createTransfer, Args(args))
            } else {
                let signed = (kind == .income || kind == .refund) ? abs(value) : -abs(value)
                let fallback = kind == .income ? "Income" : (kind == .refund ? "Refund" : "Untitled")
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "accountId": .string(accountId),
                    "amount": .double(signed), "merchant": .string(merchant.isEmpty ? fallback : merchant),
                    "categoryId": categoryId.isEmpty ? .null : .string(categoryId), "date": .string(ymd), "time": .string(hm),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                // Foreign-currency entry: pass the chosen currency so the engine
                // carries orig_* + converts to the account/base currency.
                if !currencyCode.isEmpty, currencyCode != currency(of: accountId) {
                    args["currency"] = .string(currencyCode)
                }
                args["status"] = .string(status.rawValue)
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
                // Remember any unrecognized merchant name as a counterparty.
                let cpName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cpName.isEmpty,
                   !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(cpName) == .orderedSame }) {
                    try store.apply(.createCounterparty, Args(["name": .string(cpName)]))
                }
                if kind == .refund {
                    args["kind"] = .string("refund")
                    if let refundedTxId { args["refundedTransactionId"] = .string(refundedTxId) }
                }
                for (k, v) in Self.scheduledLinkArgs(prefill: prefill, posts: postsScheduledOccurrence) { args[k] = v }
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
            Haptics.success()
            dismiss()
        } catch {
            Haptics.warning()
            errorMessage = i18nMessage(error)   // localizes I18nError (incl. zh), like every other write screen
        }
    }

    // MARK: date/time formatting (local wall clock → stored columns)
    private static let dayFmt = AppDate.isoDay
    private static let timeFmt = AppDate.isoTime
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
}
