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
    @State private var createCounterpartyOnSave = false   // set by the "Create <name>" row
    @State private var selectedKind: EditKind
    @State private var fromAmountText = ""   // transfer editor: from-leg native amount
    @State private var toAmountText = ""     // transfer editor: to-leg native amount (cross-currency)

    /// The original native (account-currency) amount, the basis for the edit.
    private var originalNative: Double { txn.nativeAmount ?? txn.amount }
    /// A split transaction owns its categories via legs — hide amount/category here.
    private var isSplit: Bool { (txn.splits?.count ?? 0) >= 2 }
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
    @ViewBuilder private var merchantSuggestionRows: some View {
        let t = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if txn.kind != "transfer", !t.isEmpty {
            ForEach(matchingCounterparties) { cp in
                Button { pickCounterparty(cp.name) } label: {
                    Label(cp.name, systemImage: "building.2").font(.callout)
                }
            }
            if !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) {
                Button { createCounterpartyOnSave = true } label: {
                    Label("Create \"\(t)\"", systemImage: "plus.circle").font(.callout)
                }
            }
        }
    }
    private func pickCounterparty(_ name: String) {
        merchant = name
        createCounterpartyOnSave = false
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

    /// Top control state: nil hides the control (adjustment/opening rows).
    private var typeControlKind: EditTypeControl.Kind? {
        switch txn.kind {
        case "transfer": return .transfer
        case "adjustment", "opening": return nil
        default: return EditTypeControl.Kind(rawValue: effectiveKind) ?? .expense
        }
    }
    /// Line items reclassify across expense/income/refund; everything else locks.
    private var typeControlEnabled: Set<EditTypeControl.Kind> {
        canReclassify ? [.expense, .income, .refund] : []
    }

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
            TextField("0.00", text: text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .disabled(mirrored)
                .foregroundStyle(mirrored ? Color.secondary : Color.primary)
            Text(currency).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Merchant"); Spacer()
                        TextField("", text: $merchant).multilineTextAlignment(.trailing)
                    }
                    merchantSuggestionRows
                    HStack {
                        Text("Note"); Spacer()
                        TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, AppDate.h24Locale)   // 24-hour time wheel regardless of device setting
                }
                if isSplit {
                    Section("Split") {
                        Button { showingSplit = true } label: {
                            HStack {
                                Text("Split across \(txn.splits?.count ?? 0) categories")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else if let legs = transferLegs {
                    // Transfer legs: a real transfer editor (spec §2). Accounts are
                    // immutable in updateTransfer → read-only; no Category row for
                    // transfers.
                    Section("Transfer") {
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
                    }
                } else {
                    Section("Amount & category") {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            // Currency lives inline with the amount, always visible.
                            Picker("", selection: $currencyCode) {
                                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden().fixedSize()
                        }
                        SearchablePickerRow(title: "Category",
                            options: categories.map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
                        Button("Split across categories…") { showingSplit = true }
                    }
                }

                if txn.kind != "transfer" {
                    Section("Account") {
                        SearchablePickerRow(title: "Account",
                            options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
                    }
                }
                if effectiveKind == "refund" {
                    Section("Refund") {
                        Button { showingRefundPicker = true } label: {
                            HStack {
                                Text("Refunds"); Spacer()
                                Text(refundedSummary).foregroundStyle(.secondary)
                            }
                        }
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

                Section("Receipts") {
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
                }

                Section {
                    Picker("Status", selection: $status) {
                        Text("Confirmed").tag(Entries.Status.confirmed)
                        Text("Pending").tag(Entries.Status.pending)
                    }
                }
                Section {
                    Button(txn.reviewedAt == nil ? "Mark reviewed" : "Unmark reviewed") {
                        run(.setReviewed, ["id": .string(txn.id), "reviewed": .bool(txn.reviewedAt == nil)])
                    }
                    Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                        // Anchored on the button (iOS 26 positions popouts at their source).
                        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                do { try store.deleteTransaction(txn.id); dismiss() }   // also unlinks receipt files
                                catch { errorMessage = i18nMessage(error) }
                            }
                        }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .principal) {
                    if let kind = typeControlKind {
                        EditTypeControl(selected: kind, enabled: typeControlEnabled) { k in
                            if let ek = EditKind(rawValue: k.rawValue) { selectedKind = ek }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
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
            .sheet(isPresented: $showingSplit) { SplitEditorView(txn: txn) }
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
            .onChange(of: merchant) { _, _ in createCounterpartyOnSave = false }
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
            if createCounterpartyOnSave {
                let cpName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cpName.isEmpty,
                   !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(cpName) == .orderedSame }) {
                    try store.apply(.createCounterparty, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(cpName)]))
                }
            }
            try store.apply(.updateTransaction, Args(["id": .string(txn.id), "patch": .object(patch)]))
            if selectedTags != Set(txn.tags ?? []) {
                try store.apply(.setTransactionTags, Args(["id": .string(txn.id),
                    "tagIds": .array(selectedTags.sorted().map { .string($0) })]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
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
                if merchant != txn.merchant { legPatch["merchant"] = .string(merchant.isEmpty ? "Untitled" : merchant) }
                if status != (txn.pending == true ? .pending : .confirmed) { legPatch["status"] = .string(status.rawValue) }
                if !legPatch.isEmpty {
                    try store.apply(.updateTransaction, Args(["id": .string(txn.id), "patch": .object(legPatch)]))
                }
                if selectedTags != Set(txn.tags ?? []) {
                    try store.apply(.setTransactionTags, Args(["id": .string(txn.id),
                        "tagIds": .array(selectedTags.sorted().map { .string($0) })]))
                }
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
        }
    }

    private func toggleTag(_ id: String) {
        if selectedTags.contains(id) { selectedTags.remove(id) } else { selectedTags.insert(id) }
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
