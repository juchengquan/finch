import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FinchCore

/// Add Transaction — the flagship write screen (port of the web add-expense-form).
/// Expense/income post one account leg + an auto-balanced category leg through
/// `saveTransaction`; a transfer is the same one write, sending two account cells.
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
        var label: String { KindLabel.label(rawValue) }
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
    /// Set once the user picks a Status BY HAND, after which the date stops driving it.
    ///
    /// Without it the sheet argues with the person using it: choose Confirmed on a
    /// future date (recording something paid in advance), nudge the date, and the app
    /// silently undoes the choice.
    @State private var statusTouched = false
    @State private var selectedTags: Set<String> = []
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var pickedFileURL: URL?
    @State private var prefillApplied = false             // duplicate-prefill runs once
    @State private var splitAlloc = SplitAllocation(total: 0)
    /// Split tender: the same purchase paid from several accounts. Same
    /// `SplitAllocation` model as `splitAlloc`, one axis over — rides
    /// `SearchablePickerRow`'s `splitting:` parameter, the account-picker twin of
    /// `CategoryPickerRow`'s.
    @State private var accountAlloc = SplitAllocation(total: 0)
    /// The grid: one flat allocation over the CELLS, keyed "<accountId>|<categoryId>"
    /// (Decision 11). Used only when both axes are split — the two allocations above
    /// each divide one axis, and two sets of margins do not determine the cells
    /// between them.
    @State private var gridAlloc = SplitAllocation(total: 0)
    /// Page 2 is pushed, not presented: it is the same purchase being described,
    /// not a separate decision, and Back must return to page 1 with everything
    /// still typed.
    @State private var showingGrid = false
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

    /// The `accounts`/`currency` args for a split-tender purchase — several
    /// accounts paying for one line item. Empty unless 2+ rows are funded (one
    /// funded row is not a split; the plain `accountId` above already carries it).
    ///
    /// Two things this MUST get right, both missed the first time round because
    /// they only showed up once real args were built and sent to the engine —
    /// not in `SplitAllocation`'s own tests, which never touch a sign or a
    /// currency key:
    /// - SIGNED to match `signed` (the same amount already in `args["amount"]`).
    ///   `SplitAllocation`'s rows are always positive magnitudes (`funded` is
    ///   `amount > 0`), so an unsigned share sent alongside a NEGATIVE expense
    ///   amount makes the engine's `totalBase` vs `statedBase` compare a positive
    ///   sum against a negative total and reject every expense split outright.
    ///   The engine's own tests (`MultiAccountAddTests.swift:20-26`) use negative
    ///   shares for an expense; match that here rather than in `SplitAllocation`,
    ///   since the sign is a property of THIS call, not of the allocation.
    /// - `currency` sent EXPLICITLY whenever `accounts` is present. Every row in
    ///   the split section is shown, and typed, in `currency` (the transaction's
    ///   own currency — the split assumes one currency across every row; see
    ///   `SearchablePickerRow.currencyMismatchedAccountIds`, which keeps that
    ///   assumption true rather than just asserted). Without this key the engine
    ///   defaults an omitted `currency` to the LEDGER BASE (`Transactions.swift`),
    ///   which is wrong the moment the transaction's own currency differs from
    ///   base — e.g. two EUR accounts paying a EUR-denominated purchase in a
    ///   USD-base ledger.
    static func accountSplitArgs(accountAlloc: SplitAllocation, signed: Double, currency: String) -> [String: JSONValue] {
        let payload = accountAlloc.payload
        guard payload.count >= 2 else { return [:] }
        let sign: Double = signed < 0 ? -1 : 1
        return [
            "accounts": .array(payload.map { .object([
                "accountId": .string($0.id ?? ""), "amount": .double(sign * $0.amount)]) }),
            "currency": .string(currency),
        ]
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
        (accounts.first { $0.id == accountId } ?? foreignAccounts.first { $0.id == accountId })?
            .currency ?? store.displayCurrency
    }

    // MARK: Cross-ledger transfers (2026-08-12 design, D6)

    /// Accounts in OTHER books, with the ledger they belong to. The store projects
    /// only the active ledger, so this is the one place the app deliberately reads
    /// outside it — and only to populate a transfer's To picker.
    private var foreignLedgers: [Ledger] { store.ledgers.filter { $0.id != store.activeLedgerId } }
    private var foreignAccounts: [AccountRow] {
        foreignLedgers.flatMap { store.accounts(forLedger: $0.id) }
    }
    private func ledgerName(of accountId: String) -> String? {
        guard let a = foreignAccounts.first(where: { $0.id == accountId }) else { return nil }
        return foreignLedgers.first { $0.id == a.ledgerId }?.name
    }
    /// The last received amount WE suggested. The suggestion is only ever
    /// overwritten while the field still holds it — the moment you type your
    /// bank's real figure it is yours, and no later rate refresh or amount edit
    /// takes it back (D5: prefilled, always editable).
    @State private var suggestedReceived = ""

    /// Fill the received amount from finch's stored rates. Nothing can verify
    /// either number across two books, so this is a convenience, not a source of
    /// truth — which is exactly why it must never overwrite a typed value.
    private func refreshReceivedSuggestion() {
        guard kind == .transfer, transferIsCrossCurrency,
              let value = DecimalInput.parse(amount), value > 0 else { return }
        guard received.isEmpty || received == suggestedReceived else { return }
        let from = currency(of: fromAccountId), to = currency(of: toAccountId)
        guard let converted = Money.convert(abs(value), from: from, to: to, rates: store.rateMap) else { return }
        let text = DecimalInput.text(converted, fractionDigits: Currencies.minorUnits(for: to))
        received = text
        suggestedReceived = text
    }

    /// True once the chosen destination lives in another book — which is what
    /// turns this from one balanced entry into a linked PAIR, one per ledger.
    private var isCrossLedger: Bool {
        kind == .transfer && !toAccountId.isEmpty && ledgerName(of: toAccountId) != nil
    }
    /// This ledger's accounts first, then each other book under its own heading.
    private var transferToOptions: (accounts: [AccountRow], titles: [String: String], order: [String]) {
        var titles: [String: String] = [:]
        var order: [String] = []
        let mine = store.ledgers.first { $0.id == store.activeLedgerId }?.name ?? String(localized: "This ledger")
        for a in accounts { titles[a.id] = mine }
        order.append(mine)
        for l in foreignLedgers {
            let named = store.accounts(forLedger: l.id)
            guard !named.isEmpty else { continue }
            for a in named { titles[a.id] = l.name }
            order.append(l.name)
        }
        return (accounts + foreignAccounts, titles, order)
    }
    private var transferIsCrossCurrency: Bool {
        kind == .transfer && currency(of: fromAccountId) != currency(of: toAccountId)
    }

    /// The two splits (category, account) are mutually exclusive: the engine
    /// refuses an entry that's split both ways at once (`error.split.multiAccount`,
    /// Task 4b added it deliberately) — `addTransaction` commits its own
    /// transaction before `setTransactionSplits` ever runs, so letting the UI
    /// offer both would post the purchase, throw on the second call, and leave
    /// the user's category split silently dropped. Disabling each toggle while
    /// the OTHER already has 2+ funded rows keeps that combination unreachable.
    // The two splits were mutually exclusive because the ENGINE could not store a
    // purchase split both ways: the projection copies an entry's splits onto every
    // account-leg row, so it would double-count. It can now — as one transaction
    // per card — so the combination routes to the grid instead of being blocked.
    private var categorySplitBlocked: Bool { false }
    private var accountSplitBlocked: Bool { false }

    /// Whether the money is divided on page 2 — for ANY split, one axis or two.
    ///
    /// Counts TICKED rows, not `payload`: the pickers no longer collect amounts,
    /// so every row is zero until page 2 and `payload` would be empty.
    private var usesPage2: Bool {
        PurchaseFlow.page2(accounts: accountAlloc.rows.count,
                           categories: splitAlloc.rows.count) != .notNeeded
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
            // A transaction dated after today starts PENDING — it has not happened, and
            // pending is exactly what the engine means by "has not counted yet"
            // (excluded from spend, budgets and the running balance).
            //
            // Day-granular on purpose: dinner tonight at 19:00 entered at 15:00 is
            // TODAY, and confirming it is right. Comparing timestamps would flip the
            // status on a five-minute nudge of a field that defaults to now.
            //
            // Here rather than at the two `DatePicker`s (the kind branches each carry
            // one) so the rule cannot drift between them.
            .onChange(of: date) { _, newDate in
                guard !statusTouched else { return }
                status = FinchStore.isoDay(newDate) > store.wallToday ? .pending : .confirmed
            }
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
                    // A grid is described on page 2, so page 1 offers the way there
                    // instead of a save. Everything else still saves from here.
                    Button(action: { usesPage2 ? openGrid() : save() }) {
                        if usesPage2 { Text("Next") } else { Image(systemName: "checkmark") }
                    }
                        .accessibilityLabel(usesPage2 ? Text("Next") : Text("Save"))
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
            .navigationDestination(isPresented: $showingGrid) {
                PurchaseGridPage(
                    alloc: $gridAlloc,
                    accountIds: accountAlloc.rows.isEmpty ? [accountId] : accountAlloc.rows.map(\.id),
                    categoryIds: splitAlloc.rows.isEmpty
                        ? [categoryId.isEmpty ? nil : categoryId]
                        : splitAlloc.rows.map { $0.id.isEmpty ? nil : $0.id },
                    currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode,
                    onSave: save)
            }
            // Auto-categorize from the merchant's history (the user can still override).
            .onChange(of: merchant) { _, m in
                guard kind != .transfer, !m.isEmpty else { return }
                if let s = Selectors.suggestCategory(store.txns, store.activeLedgerId, m),
                   categories.contains(where: { $0.id == s.categoryId }) {
                    categoryId = s.categoryId
                }
            }
            .onChange(of: amount) { _, newValue in
                // Re-divide rather than discard: this used to null the split outright,
                // so correcting a typo in the amount silently threw the split away.
                let total = abs(DecimalInput.parse(newValue) ?? 0)
                splitAlloc.setTotal(total)
                accountAlloc.setTotal(total)
                gridAlloc.setTotal(total)
            }
            .sheet(isPresented: $showingRefundPicker) {
                RefundSourcePickerView { refundedTxId = $0 }
            }
            .onChange(of: kind) { _, k in if k != .refund { refundedTxId = nil } }
        }
    }


    @ViewBuilder private func formPage(_ k: Kind) -> some View {
            Form {
                Section { TxnTypeToolbar.caption(k.label) }.finchCaptionSection()   // names the icon-only type control above
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
                        // Status keeps its name on the left and the selection on the
                        // right (not the placeholder→value treatment of other rows).
                        FieldRow(glyph: .status, title: "Status", trailing: {
                            // A Binding rather than `$status`, and NOT
                            // `.onChange(of: status)`: the rule above assigns `status`
                            // itself, so an onChange would latch on the first automatic
                            // change and freeze the rule after one use. This setter runs
                            // only when the Picker writes through it — a real pick.
                            Picker("Status", selection: Binding(
                                get: { status },
                                set: { statusTouched = true; status = $0 })) {
                                Text("Confirmed").tag(Entries.Status.confirmed)
                                Text("Pending").tag(Entries.Status.pending)
                            }
                            .labelsHidden()
                        }) {
                            Text("Status")
                        }
                        // Tags is a single row here (wraps to hold all selected), not its own section.
                        if !store.tags.isEmpty {
                            TagField(tags: store.tags, selected: $selectedTags, glyph: .tags)
                        }
                    }
                }
                if k == .expense || k == .income || k == .refund {
                    Section {
                        #if os(macOS)
                        Button { showingFileImporter = true } label: {
                            FieldRow(glyph: .receipt, title: "Add receipt", isEmpty: pickedFileURL == nil) {
                                Text(pickedFileURL == nil ? "Add receipt…" : "Receipt selected")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf]) { result in
                            if case .success(let url) = result { pickedFileURL = url }
                        }
                        #else
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            FieldRow(glyph: .receipt, title: "Add receipt", isEmpty: pickedPhoto == nil) {
                                Text(pickedPhoto == nil ? "Add receipt photo" : "Receipt photo selected")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        #endif
                        FieldRow(glyph: .note, title: "Note") {
                            TextField("Note (optional)", text: $note, axis: .vertical)
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
    }

    @ViewBuilder private func expenseIncomeFields(for k: Kind) -> some View {
        Section {
            SearchablePickerRow(title: "Account", glyph: .account,
                accounts: accounts, selection: $accountId,
                splitting: $accountAlloc,
                currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode)
                // A UI test reads this row to prove the FAB seeded the sheet. Without an
                // identifier the query also matches the "Accounts" tab-bar button and the
                // budget detail's own Account row sitting behind the sheet.
                .accessibilityIdentifier("addtx.account")
            amountField
            FieldRow(glyph: .date, title: "Date", showsDefaultTrailing: false) {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            CategoryPickerRow(title: "Category", glyph: .category, categories: categories(for: k), selection: $categoryId,
                // A transaction may legitimately have no category — the engine stores a
                // nil category leg — so the picker offers it rather than making the
                // field impossible to clear once set.
                noneLabel: String(localized: "Uncategorized"),
                splitSummary: splitSummaryText(names: splitAlloc.selection.map { store.categoryName($0.id) ?? "Uncategorized" }),
                splitting: k == .refund ? nil : $splitAlloc,
                currency: currencyCode.isEmpty ? currency(of: accountId) : currencyCode)
                .accessibilityIdentifier("addtx.category")
            MerchantPickerRow(title: "Merchant", glyph: .merchant,
                              counterparties: store.counterparties, merchant: $merchant)
            // Both axes split: the per-axis editors above each divide ONE axis, and
            // two sets of margins do not determine the cells between them — $60/$0/
            // $10/$30 and $42/$18/$28/$12 give the same card and category totals.
            // So the cells are typed on page 2, and the totals derive from them.
            if k == .refund {
                Button { showingRefundPicker = true } label: {
                    FieldRow(glyph: .refund, title: "Refunds", isEmpty: refundedTxId == nil) {
                        Text(refundedSummary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Merchant lives in the primary section and Note in the receipt section —
    // the old "Details" basement (and its header) is gone (2026-08-08 reorg).




    /// Adjust Balance — the opt-in 5th type. Posts an `adjustment` for the
    /// difference to the account's target balance (same engine action as the
    /// account-detail sheet). Date-only — `adjustAccountBalance` takes no time.
    @ViewBuilder private var adjustFields: some View {
        Section {
            SearchablePickerRow(title: "Account", glyph: .account,
                accounts: accounts, selection: $accountId)
                // A UI test reads this row to prove the FAB seeded the sheet. Without an
                // identifier the query also matches the "Accounts" tab-bar button and the
                // budget detail's own Account row sitting behind the sheet.
                .accessibilityIdentifier("addtx.account")
            // numbersAndPunctuation allows a leading minus (e.g. a credit-card balance).
            FieldRow(glyph: .amount, title: "New balance") {
                // setsKeyboard: false keeps numbersAndPunctuation — decimalPad has
                // no minus key, and a credit-card balance is negative.
                TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: currency(of: accountId))),
                          text: $targetBalance)
                    .moneyInput($targetBalance, currency: currency(of: accountId), setsKeyboard: false)
            }
        } footer: {
            Text("Posts an adjustment for the difference from the account's current balance.")
        }
        Section {
            FieldRow(glyph: .date, title: "Date", showsDefaultTrailing: false) {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            FieldRow(glyph: .note, title: "Note") {
                TextField("Note (optional)", text: $note, axis: .vertical)
            }
        }
    }

    @ViewBuilder private var transferFields: some View {
        Section {
            SearchablePickerRow(title: "From", glyph: .fromAccount,
                accounts: accounts, selection: $fromAccountId)
            SearchablePickerRow(title: "To", glyph: .toAccount,
                accounts: transferToOptions.accounts, selection: $toAccountId,
                sectionTitles: transferToOptions.titles, sectionOrder: transferToOptions.order)
                .onChange(of: toAccountId) { _, _ in refreshReceivedSuggestion() }
                .onChange(of: amount) { _, _ in refreshReceivedSuggestion() }
            // Same currency → one amount row; cross-currency → From + To, the To
            // row being the independent received amount in the destination's money.
            if transferIsCrossCurrency {
                transferAmountRow("From amount", text: $amount, currency: currency(of: fromAccountId))
                transferAmountRow("To amount", text: $received, currency: currency(of: toAccountId))
            } else {
                transferAmountRow("Amount", text: $amount, currency: currency(of: fromAccountId))
            }
            // Transfer has no Merchant/category, so Date + Note live here (the
            // reorder moved the shared Date/Note section into the line-item path).
            FieldRow(glyph: .date, title: "Date", showsDefaultTrailing: false) {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            FieldRow(glyph: .note, title: "Note") {
                TextField("Note (optional)", text: $note, axis: .vertical)
            }
        }
    }

    /// Line-item amount row: Amount + the currency menu inline (currency is
    /// ALWAYS visible, even when only one option exists).
    /// The currency the typed amount is denominated in — the picker's choice,
    /// falling back to the selected account's own currency (same precedence the
    /// save path uses).
    private var amountCurrency: String {
        currencyCode.isEmpty ? currency(of: accountId) : currencyCode
    }

    private var amountField: some View {
        FieldRow(glyph: .amount, title: "Amount", trailing: {
            Picker("", selection: $currencyCode) {
                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
        }) {
            TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: amountCurrency)),
                      text: $amount)
                .moneyInput($amount, currency: amountCurrency)
                .accessibilityIdentifier("addtx.amount")
        }
    }

    /// Transfer amount row: fixed currency label from the leg's account (the
    /// account owns the currency — no picker).
    private func transferAmountRow(_ label: String, text: Binding<String>, currency: String) -> some View {
        FieldRow(glyph: .amount, title: LocalizedStringKey(label), trailing: {
            Text(currency).foregroundStyle(.secondary)
        }) {
            TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: currency)),
                      text: text)
                .moneyInput(text, currency: currency)
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
            amount = magnitude == 0 ? "" : DecimalInput.text(magnitude, currency: p.currency ?? currency(of: p.account))
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
                    // Each leg in ITS OWN currency, matching what transferAmountRow
                    // passes for typing.
                    if let f = from {
                        amount = DecimalInput.text(abs(f.nativeAmount ?? f.amount),
                                                   currency: currency(of: fromAccountId))
                    }
                    // Cross-currency transfers carry a second, independent amount.
                    if let t = to, currency(of: fromAccountId) != currency(of: toAccountId) {
                        received = DecimalInput.text(abs(t.nativeAmount ?? t.amount),
                                                     currency: currency(of: toAccountId))
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
                targetBalance = DecimalInput.text(current + (p.nativeAmount ?? p.amount),
                                                  currency: currency(of: p.account))
            case .expense, .income:
                break
            }
        }
        // Only prefill an account when we can actually deduce one: a duplicate /
        // scheduled source already set it above, else a `defaultAccountId` handed in
        // when opened from an account's detail. A generic Add (the global +) leaves
        // the account empty so the user picks it — same for a transfer's From/To.
        let preferredAccount = defaultAccountId.flatMap { id in accounts.first { $0.id == id }?.id }
        if accountId.isEmpty { accountId = preferredAccount ?? "" }
        // Only seed a category from a prefill/duplicate or an explicit
        // defaultCategoryId — a FRESH add starts uncategorized (no default),
        // so the user makes an intentional choice.
        if !categoryId.isEmpty, !categories.contains(where: { $0.id == categoryId }) {
            categoryId = ""
        }
        if categoryId.isEmpty, let id = defaultCategoryId, categories.contains(where: { $0.id == id }) {
            categoryId = id
        }
        // Transfer From follows the same deduce-or-empty rule; To can't be deduced
        // from a single source account, so it stays empty until the user picks it.
        if fromAccountId.isEmpty { fromAccountId = preferredAccount ?? "" }
        if currencyCode.isEmpty { currencyCode = currency(of: accountId) }
    }

    /// Open page 2, rebuilding the cells for whatever is selected now.
    ///
    /// `reseedGrid` keeps every cell the user already typed and floats the new
    /// ones, so going back to add a card does not disturb the figures already
    /// set — it just gives the new card whatever is left.
    private func openGrid() {
        let total = abs(DecimalInput.parse(amount) ?? 0)
        gridAlloc = PurchaseFlow.reseedGrid(gridAlloc,
                                            accounts: accountAlloc.selection,
                                            categories: splitAlloc.selection,
                                            total: total)
        showingGrid = true
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
        // Same rule as the Edit sheet: the amount is the target, the cells must
        // reach it. The grid is the case that could silently under-post — its
        // footer already SAYS "N unaccounted", and nothing stopped the save.
        // Page 2 owns every split now, so its cells are the only thing that can
        // fail to add up. The margin allocations are selection state — they carry
        // no amounts at all until page 2 fills them.
        if usesPage2, gridAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total."); return
        }
        let ymd = Self.day(date)
        let hm = Self.time(date)
        // Soft duplicate nudge (expense/income only) — show once, before posting.
        if kind != .transfer, !dupConfirmed,
           let m = Selectors.findDuplicate(store.txns, store.activeLedgerId,
               DuplicateDraft(merchant: merchant, amount: abs(value), accountId: accountId, date: ymd, excludeId: nil)) {
            pendingDuplicate = m
            Haptics.warning()
            return
        }
        do {
            if kind == .transfer {
                guard fromAccountId != toAccountId else { errorMessage = "Pick two different accounts."; return }
                var receivedAmount = abs(value)
                if transferIsCrossCurrency {
                    guard let recv = DecimalInput.parse(received), recv > 0 else {
                        errorMessage = "Enter the received amount."; return
                    }
                    receivedAmount = recv
                }
                // Another book ⇒ a PAIR of entries, one per ledger, each balanced
                // in its own base currency. A single entry cannot span two ledgers
                // (see the 2026-08-12 design), so this is a different write, not a
                // variant of the one below.
                if isCrossLedger {
                    var xargs: [String: JSONValue] = [
                        "fromAccountId": .string(fromAccountId),
                        "toAccountId": .string(toAccountId),
                        "fromAmount": .double(abs(value)),
                        "toAmount": .double(receivedAmount),
                        "date": .string(ymd), "time": .string(hm),
                        "status": .string(status.rawValue),
                    ]
                    if !note.isEmpty { xargs["note"] = .string(note) }
                    try store.apply(.createInterledgerTransfer, Args(xargs))
                    dismiss()
                    return
                }
                // The same one write every other kind uses. A transfer's cells are
                // each in their OWN card's currency — there is no single purchase
                // currency when 110 USD leaves one card and 100 EUR arrives at
                // another, and the user types both numbers — so no `currency` is
                // sent and the engine takes each amount as given.
                //
                // The description and both leg memos are engine-authored, so the
                // sheet sends an empty merchant rather than inventing feed text.
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "merchant": .string(""),
                    "date": .string(ymd), "time": .string(hm),
                    "kind": .string("transfer"), "status": .string(status.rawValue),
                    "cells": .array([
                        .object(["accountId": .string(fromAccountId), "categoryId": .null,
                                 "amount": .double(-abs(value))]),
                        .object(["accountId": .string(toAccountId), "categoryId": .null,
                                 "amount": .double(receivedAmount)]),
                    ]),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
                for (k, v) in Self.scheduledLinkArgs(prefill: prefill, posts: postsScheduledOccurrence) { args[k] = v }
                try store.apply(.saveTransaction, Args(args))
            } else {
                let signed = (kind == .income || kind == .refund) ? abs(value) : -abs(value)
                let sign: Double = signed < 0 ? -1 : 1
                let fallback = kind == .income ? "Income" : (kind == .refund ? "Refund" : "Untitled")

                // ONE write, replacing the three this path used to fire
                // (createCounterparty, addTransaction, setTransactionSplits). A
                // part-way failure used to leave the ledger half-updated — the
                // merchant created without its transaction, or the transaction
                // posted without its category split.
                //
                // The cells ARE the purchase: one per (card, category) pair that
                // has money against it. The engine derives the shape from the
                // category count, so the sheet does not decide whether this is one
                // transaction or several.
                let purchaseCcy = currencyCode.isEmpty ? currency(of: accountId) : currencyCode
                var cells: [JSONValue] = []
                let cat: JSONValue = categoryId.isEmpty ? .null : .string(categoryId)
                if usesPage2 {
                    // Sent as CELLS, not pre-grouped by card: the engine derives the
                    // shape from the category count (Decision 15), so the sheet does
                    // not decide whether this is one transaction or several.
                    cells = PurchaseFlow.cells(from: gridAlloc,
                                               kind: AddTxKind(rawValue: kind.rawValue) ?? .expense)
                } else if accountAlloc.payload.count >= 2 {
                    for share in accountAlloc.payload {
                        cells.append(.object([
                            "accountId": .string(share.id ?? accountId),
                            "categoryId": cat,
                            "amount": .double(sign * abs(share.amount)),
                        ]))
                    }
                } else if splitAlloc.payload.count >= 2 {
                    for share in splitAlloc.payload {
                        cells.append(.object([
                            "accountId": .string(accountId),
                            "categoryId": share.id.map(JSONValue.string) ?? .null,
                            "amount": .double(sign * abs(share.amount)),
                        ]))
                    }
                } else {
                    cells.append(.object([
                        "accountId": .string(accountId), "categoryId": cat, "amount": .double(signed),
                    ]))
                }

                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId),
                    "merchant": .string(merchant.isEmpty ? fallback : merchant),
                    "date": .string(ymd), "time": .string(hm),
                    "currency": .string(purchaseCcy),
                    "kind": .string(kind == .refund ? "refund" : (kind == .income ? "income" : "expense")),
                    "status": .string(status.rawValue),
                    "cells": .array(cells),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                // The user was shown the possible-duplicate prompt and chose "Add
                // anyway". Without this the engine's double-submit backstop refuses
                // the write regardless — the prompt asked and the answer was
                // ignored, which is the bug this fixes.
                if dupConfirmed { args["allowDuplicate"] = .bool(true) }
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
                if kind == .refund, let refundedTxId { args["refundedTransactionId"] = .string(refundedTxId) }
                for (k, v) in Self.scheduledLinkArgs(prefill: prefill, posts: postsScheduledOccurrence) { args[k] = v }

                // The merchant is resolve-or-created inside the same write, so the
                // separate createCounterparty call is gone — with it goes the
                // orphan counterparty a failed save used to leave behind.
                let eid = try store.applyReturningId(.saveTransaction, Args(args))
                if let eid, let photo = pickedPhoto {
                    Task { try? await AttachmentWriter.write(item: photo, entryId: eid, store: store) }
                }
                if let eid, let url = pickedFileURL {
                    Task { try? await AttachmentWriter.writeFile(url: url, entryId: eid, store: store) }
                }
            }
            dismiss()
            Haptics.success()
        } catch {
            errorMessage = i18nMessage(error)   // localizes I18nError (incl. zh), like every other write screen
            Haptics.warning()
        }
    }

    // MARK: date/time formatting (local wall clock → stored columns)
    private static let dayFmt = AppDate.isoDay
    private static let timeFmt = AppDate.isoTime
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
}
