import SwiftUI
import PhotosUI
import CryptoKit
import QuickLook
import UniformTypeIdentifiers
import FinchCore

/// Edit Transaction (port of the web edit-transaction-form). Editable: merchant,
/// note, date/time, amount, category, tags, receipt attachments, and splitting
/// across categories (a split tx hides amount/category since its legs own them).
/// (Account change is supported by the engine but not surfaced here.) Also
/// exposes confirm / toggle-reviewed / delete. All writes go through
/// FinchStore.apply.
struct EditTransactionSheet: View {
    @EnvironmentObject private var store: FinchStore
    @State private var pendingAttachmentDelete: AttachmentRow?   // receipt awaiting delete confirmation
    @Environment(\.dismiss) private var dismiss

    let txn: Tx

    enum EditKind: String, CaseIterable, Identifiable {
        case expense, income, refund
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @State private var merchant: String
    @State private var note: String
    @State private var date: Date
    @State private var categoryId: String
    @State private var amountText: String
    @State private var selectedTags: Set<String>
    @State private var showingSplit = false
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var attachments: [AttachmentRow] = []
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var previewURL: URL?
    @State private var status: Entries.Status
    @State private var accountId: String
    @State private var refundedTxId: String?
    @State private var showingRefundPicker = false
    @State private var currencyCode: String
    @State private var selectedKind: EditKind
    @State private var fromAmountText = ""   // transfer editor: from-leg native amount
    @State private var toAmountText = ""     // transfer editor: to-leg native amount (cross-currency)

    /// The original native (account-currency) amount, the basis for the edit.
    private var originalNative: Double { txn.nativeAmount ?? txn.amount }
    /// A split transaction owns its categories via legs — hide amount/category here.
    /// `txn` re-read from the LIVE store projection (not the init-time snapshot), so a
    /// split applied in-session via SplitEditorView reflects here immediately instead of
    /// leaving the sheet on the stale single-category view.
    private var liveTxn: Tx { store.txns.first(where: { $0.id == txn.id }) ?? txn }
    private var isSplit: Bool { (liveTxn.splits?.count ?? 0) >= 2 }
    private var refundedSummary: String {
        guard let id = refundedTxId, let t = store.txns.first(where: { $0.id == id }) else { return "Optional" }
        return t.merchant.isEmpty ? t.date : t.merchant
    }
    private var accountCurrency: String {
        store.accounts.first { $0.id == accountId }?.currency ?? store.displayCurrency
    }
    private var currencyOptions: [String] {
        var set = Set(store.accounts.compactMap { $0.currency })
        set.formUnion(store.exchangeRates.map { $0.currency })
        set.insert(accountCurrency)
        return set.sorted()
    }

    init(txn: Tx) {
        self.txn = txn
        _merchant = State(initialValue: txn.merchant)
        _note = State(initialValue: txn.note ?? "")
        _date = State(initialValue: Self.parse(txn.date, txn.time) ?? Date())
        _categoryId = State(initialValue: txn.category ?? "")
        _amountText = State(initialValue: String(format: "%g", abs(txn.nativeAmount ?? txn.amount)))
        _selectedTags = State(initialValue: Set(txn.tags ?? []))
        _status = State(initialValue: txn.pending == true ? .pending : .confirmed)
        _accountId = State(initialValue: txn.account)
        _refundedTxId = State(initialValue: txn.refundedTransactionId)
        _currencyCode = State(initialValue: txn.currency ?? "")
        _selectedKind = State(initialValue: EditKind(rawValue: txn.kind ?? "") ?? (txn.amount > 0 ? .income : .expense))
    }

    /// Simple single-account entries can be re-typed expense/income/refund.
    private var canReclassify: Bool {
        !isSplit && txn.kind != "transfer" && txn.kind != "adjustment" && txn.kind != "opening"
    }
    private var effectiveKind: String { canReclassify ? selectedKind.rawValue : (txn.kind ?? "expense") }

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { effectiveKind == "income" ? $0.kind == "income" : $0.kind != "income" }
    }

    /// The transfer's two legs — this row plus its counterpart, resolved via
    /// transferGroupId. From = the negative-amount leg.
    private var transferLegs: (from: Tx, to: Tx)? {
        guard txn.kind == "transfer", let gid = txn.transferGroupId else { return nil }
        let legs = store.txns.filter { $0.transferGroupId == gid }
        guard let from = legs.first(where: { $0.amount < 0 }),
              let to = legs.first(where: { $0.amount > 0 }), from.id != to.id else { return nil }
        return (from, to)
    }
    private var transferSameCurrency: Bool {
        guard let legs = transferLegs else { return true }
        return (legs.from.currency ?? "") == (legs.to.currency ?? "")
    }
    private func accountName(_ id: String) -> String {
        store.accounts.first { $0.id == id }?.name ?? "—"
    }
    /// Transfer amount row: fixed currency label from the leg (accounts own
    /// their currency — no picker). `mirrored` = same-currency To row: disabled,
    /// live-synced to the From field.
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

    var body: some View {
        NavigationStack {
            Form {
                // Line items build their own primary section (Account/Amount/
                // Category/Date) below; split & transfer keep Date here.
                if isSplit || transferLegs != nil {
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, AppDate.h24Locale)   // 24-hour time wheel regardless of device setting
                        // Transfers have no Merchant field (design), but previously
                        // exposed Note via this shared top section — keep that.
                        if transferLegs != nil {
                            HStack {
                                Text("Note"); Spacer()
                                TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                if isSplit {
                    // Still the Category row (not a "Split" abstraction) — its value is the
                    // split's category names; tapping it reopens the split editor.
                    Section {
                        CategoryPickerRow(title: "Category", categories: categories, selection: .constant(""),
                            splitSummary: splitSummaryText(categoryNames: (liveTxn.splits ?? []).map { store.categoryName($0.categoryId) ?? "Uncategorized" }),
                            splitEnabled: true,
                            onSplit: { showingSplit = true })
                    }
                } else if let legs = transferLegs {
                    // Transfer legs: a real transfer editor (spec §2). Accounts are
                    // immutable in updateTransfer → read-only; no Category row for
                    // transfers.
                    Section {
                        LabeledContent("From", value: accountName(legs.from.account))
                        LabeledContent("To", value: accountName(legs.to.account))
                        // Always TWO amount rows, each in its leg's own currency.
                        // Same currency → the To row mirrors From (disabled);
                        // cross-currency → independent To amount.
                        transferAmountRow("From amount", text: $fromAmountText,
                                          currency: legs.from.currency ?? "")
                        if transferSameCurrency {
                            transferAmountRow("To amount", text: $fromAmountText,
                                              currency: legs.to.currency ?? "", mirrored: true)
                        } else {
                            transferAmountRow("To amount", text: $toAmountText,
                                              currency: legs.to.currency ?? "")
                        }
                    } header: {
                        finchSectionHeader("Transfer")
                    }
                } else {
                    Section {
                        SearchablePickerRow(title: "Account",
                            options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("0.00", text: $amountText).numericInput($amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            // Currency lives inline with the amount, always visible.
                            Picker("", selection: $currencyCode) {
                                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden().fixedSize()
                        }
                        CategoryPickerRow(title: "Category", categories: categories, selection: $categoryId,
                            splitEnabled: (DecimalInput.parse(amountText) ?? 0) != 0,
                            onSplit: effectiveKind == "refund" ? nil : { showingSplit = true })
                        DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, AppDate.h24Locale)
                        // Refund link inline in the primary section (matches the Add sheet).
                        if effectiveKind == "refund" {
                            Button { showingRefundPicker = true } label: {
                                HStack {
                                    Text("Refunds"); Spacer()
                                    Text(refundedSummary).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Split still needs an Account row (line items have it above; transfer doesn't).
                if isSplit {
                    Section {
                        SearchablePickerRow(title: "Account",
                            options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
                    } header: {
                        finchSectionHeader("Account")
                    }
                }
                // Status directly after the primary/split rows (matches the Add sheet).
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

                Section {
                    ForEach(attachments) { att in
                        Button { previewURL = store.attachmentURL(for: att) } label: {
                            HStack {
                                ReceiptThumbnail(url: store.attachmentURL(for: att), kind: att.kind)
                                Text(att.originalFilename ?? att.kind.capitalized).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "eye").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            // Not role: .destructive — fake removal animation pre-confirm.
                            Button { pendingAttachmentDelete = att } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                        }
                        .contextMenu {
                            Button(role: .destructive) { pendingAttachmentDelete = att } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    #if os(macOS)
                    Button { showingFileImporter = true } label: { Label("Add receipt…", systemImage: "paperclip") }
                        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf]) { result in
                            if case .success(let url) = result { Task { await addReceiptFile(url) } }
                        }
                    #else
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Add receipt photo", systemImage: "camera")
                    }
                    #endif
                } header: {
                    finchSectionHeader("Receipt")
                }

                if txn.kind != "transfer", txn.kind != "adjustment", txn.kind != "opening" {
                    Section {
                        MerchantPickerRow(title: effectiveKind == "income" ? "Source" : "Merchant",
                                          counterparties: store.counterparties, merchant: $merchant)
                        HStack {
                            Text("Note"); Spacer()
                            TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                        }
                    } header: {
                        finchSectionHeader("Details")
                    }
                }
                // Adjustment/opening entries have no payee, so no Merchant row —
                // but keep an editable Note (e.g. "year-end reconciliation").
                if txn.kind == "adjustment" || txn.kind == "opening" {
                    Section {
                        HStack {
                            Text("Note"); Spacer()
                            TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                        }
                    } header: {
                        finchSectionHeader("Details")
                    }
                }

                // Edit-only meta actions at the very bottom.
                Section {
                    Button(txn.reviewedAt == nil ? "Mark reviewed" : "Unmark reviewed") {
                        run(.setReviewed, ["id": .string(txn.id), "reviewed": .bool(txn.reviewedAt == nil)])
                    }
                    Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                        // Anchored on the button (iOS 26 positions popouts at their source).
                        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                do { try store.deleteTransaction(txn.id); Haptics.warning(); dismiss() }   // also unlinks receipt files
                                catch { errorMessage = i18nMessage(error) }
                            }
                        }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Edit Transaction")
            .finchSheetForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                // Shared glass type control (TxnTypeToolbar). Line items reclassify
                // across the 3 kinds; a transfer shows a locked single segment;
                // adjustment/opening show none.
                ToolbarItem(placement: .principal) {
                    if canReclassify {
                        TxnTypeToolbar.segmented(EditKind.allCases, selection: $selectedKind,
                            icon: { TxnKindIcon.icon(for: $0.rawValue) }, label: { $0.label })
                    } else if txn.kind == "transfer" {
                        TxnTypeToolbar.locked(icon: TxnKindIcon.icon(for: "transfer"), label: "Transfer")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
            // Centered ALERT (window-level) — see ActivityTab's delete alert.
            .alert("Delete receipt?", isPresented: Binding(
                get: { pendingAttachmentDelete != nil }, set: { if !$0 { pendingAttachmentDelete = nil } }),
                presenting: pendingAttachmentDelete) { att in
                Button("Delete", role: .destructive) { removeAttachment(att) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The file is deleted permanently.")
            }
            .sheet(isPresented: $showingSplit) { SplitEditorView(txn: liveTxn) }
            .quickLookPreview($previewURL)
            .sheet(isPresented: $showingRefundPicker) { RefundSourcePickerView { refundedTxId = $0 } }
            .onAppear {
                attachments = store.attachments(for: txn.id)
                if currencyCode.isEmpty { currencyCode = accountCurrency }
                if let legs = transferLegs {
                    fromAmountText = String(format: "%g", abs(legs.from.nativeAmount ?? legs.from.amount))
                    toAmountText = String(format: "%g", abs(legs.to.nativeAmount ?? legs.to.amount))
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await addReceipt(item) }
            }
        }
    }

    private func addReceipt(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            try await AttachmentWriter.write(item: item, entryId: txn.id, store: store)
            attachments = store.attachments(for: txn.id)
            pickedPhoto = nil
        } catch { errorMessage = i18nMessage(error) }
    }

    private func addReceiptFile(_ url: URL) async {
        errorMessage = nil
        do {
            try await AttachmentWriter.writeFile(url: url, entryId: txn.id, store: store)
            attachments = store.attachments(for: txn.id)
        } catch { errorMessage = i18nMessage(error) }
    }

    private func removeAttachment(_ att: AttachmentRow) {
        do {
            try store.removeAttachment(id: att.id, relPath: att.relPath)   // also unlinks the file
            attachments = store.attachments(for: txn.id)
        } catch { errorMessage = i18nMessage(error) }
    }

    private func save() {
        if txn.kind == "transfer" { saveTransfer(); return }
        errorMessage = nil
        var patch: [String: JSONValue] = [
            "merchant": .string(merchant.isEmpty ? "Untitled" : merchant),
            "note": note.isEmpty ? .null : .string(note),
            "date": .string(Self.day(date)),
            "time": .string(Self.time(date)),
        ]
        let kindChanged = canReclassify && selectedKind.rawValue != txn.kind
        if !isSplit {
            guard let parsed = DecimalInput.parse(amountText), parsed > 0 else {
                errorMessage = "Enter an amount greater than 0."; return
            }
            // Sign by the (possibly new) kind: expense negative; income/refund positive.
            let sign: Double = canReclassify ? (selectedKind == .expense ? -1.0 : 1.0) : (originalNative < 0 ? -1.0 : 1.0)
            let signed = sign * parsed
            if abs(signed - originalNative) > 0.001 || kindChanged { patch["amount"] = .double(signed) }
            if !categoryId.isEmpty, categoryId != txn.category { patch["category"] = .string(categoryId) }
        }
        if kindChanged { patch["kind"] = .string(selectedKind.rawValue) }
        if status != (txn.pending == true ? .pending : .confirmed) { patch["status"] = .string(status.rawValue) }
        if txn.kind != "transfer", !accountId.isEmpty, accountId != txn.account { patch["account"] = .string(accountId) }
        if txn.kind != "transfer", !currencyCode.isEmpty, currencyCode != (txn.currency ?? accountCurrency) {
            patch["currency"] = .string(currencyCode)
        }
        // Refund link: set/update when (now) a refund; clear when leaving refund.
        if effectiveKind == "refund" {
            if refundedTxId != txn.refundedTransactionId || kindChanged {
                patch["refundedTransactionId"] = refundedTxId.map(JSONValue.string) ?? .null
            }
        } else if txn.kind == "refund" {
            patch["refundedTransactionId"] = .null
        }
        do {
            // Remember any unrecognized merchant name as a counterparty.
            let cpName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cpName.isEmpty,
               !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(cpName) == .orderedSame }) {
                try store.apply(.createCounterparty, Args(["name": .string(cpName)]))
            }
            try store.apply(.updateTransaction, Args(["id": .string(txn.id), "patch": .object(patch)]))
            if selectedTags != Set(txn.tags ?? []) {
                try store.apply(.setTransactionTags, Args(["id": .string(txn.id),
                    "tagIds": .array(selectedTags.sorted().map { .string($0) })]))
            }
            Haptics.success()
            dismiss()
        } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
    }

    /// Transfer legs save through the engine's updateTransfer (entry-level:
    /// amounts/date/time/note — keeps BOTH legs consistent; the old single-leg
    /// patch path could diverge them). Merchant/status go through the plain
    /// updateTransaction patch (entry-level on a transfer); tags via
    /// setTransactionTags.
    private func saveTransfer() {
        errorMessage = nil
        guard let legs = transferLegs else { errorMessage = "Transfer legs not found."; return }
        let result = TransferEditPatch.build(.init(
            sameCurrency: transferSameCurrency,
            originalFrom: abs(legs.from.nativeAmount ?? legs.from.amount),
            originalTo: abs(legs.to.nativeAmount ?? legs.to.amount),
            editedFrom: fromAmountText,
            editedTo: transferSameCurrency ? nil : toAmountText,
            originalDate: txn.date, originalTime: txn.time, originalNote: txn.note,
            newDate: Self.day(date), newTime: Self.time(date), newNote: note))
        switch result {
        case .failure:
            errorMessage = "Enter an amount greater than 0."
        case .success(let patch):
            do {
                if !patch.isEmpty {
                    try store.apply(.updateTransfer, Args(["id": .string(txn.id), "patch": .object(patch)]))
                }
                var legPatch: [String: JSONValue] = [:]
                // (Transfers have no Merchant field in the UI — merchant can't change here.)
                if status != (txn.pending == true ? .pending : .confirmed) { legPatch["status"] = .string(status.rawValue) }
                if !legPatch.isEmpty {
                    try store.apply(.updateTransaction, Args(["id": .string(txn.id), "patch": .object(legPatch)]))
                }
                if selectedTags != Set(txn.tags ?? []) {
                    try store.apply(.setTransactionTags, Args(["id": .string(txn.id),
                        "tagIds": .array(selectedTags.sorted().map { .string($0) })]))
                }
                Haptics.success()
                dismiss()
            } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
        }
    }

    /// Run a lifecycle action then dismiss (these don't re-edit the open form).
    private func run(_ action: ActionName, _ args: [String: JSONValue]) {
        do { try store.apply(action, Args(args)); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }

    // MARK: date/time helpers
    private static let dayFmt = AppDate.isoDay
    private static let timeFmt = AppDate.isoTime
    private static let dtFmt = AppDate.isoDateTime
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
    private static func parse(_ ymd: String, _ hm: String?) -> Date? {
        dtFmt.date(from: "\(ymd) \(hm ?? "00:00")") ?? dayFmt.date(from: ymd)
    }
}
