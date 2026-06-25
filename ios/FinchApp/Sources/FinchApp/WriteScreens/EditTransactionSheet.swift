import SwiftUI
import PhotosUI
import CryptoKit
import QuickLook
import FinchCore

/// Edit Transaction (port of the web edit-transaction-form). Editable: merchant,
/// note, date/time, amount, category, tags, receipt attachments, and splitting
/// across categories (a split tx hides amount/category since its legs own them).
/// (Account change is supported by the engine but not surfaced here.) Also
/// exposes confirm / toggle-reviewed / delete. All writes go through
/// FinchStore.apply.
struct EditTransactionSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let txn: Tx

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
    @State private var previewURL: URL?
    @State private var status: Entries.Status
    @State private var accountId: String
    @State private var refundedTxId: String?
    @State private var showingRefundPicker = false

    /// The original native (account-currency) amount, the basis for the edit.
    private var originalNative: Double { txn.nativeAmount ?? txn.amount }
    /// A split transaction owns its categories via legs — hide amount/category here.
    private var isSplit: Bool { (txn.splits?.count ?? 0) >= 2 }
    private var refundedSummary: String {
        guard let id = refundedTxId, let t = store.txns.first(where: { $0.id == id }) else { return "Optional" }
        return t.merchant.isEmpty ? t.date : t.merchant
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
    }

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { txn.amount > 0 ? $0.kind == "income" : $0.kind != "income" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Merchant"); Spacer()
                        TextField("", text: $merchant).multilineTextAlignment(.trailing)
                    }
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
                } else {
                    Section("Amount & category") {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
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
                if txn.kind == "refund" {
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
                                Image(systemName: att.kind == "pdf" ? "doc.richtext" : "photo")
                                    .foregroundStyle(.secondary)
                                Text(att.originalFilename ?? att.kind.capitalized).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "eye").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removeAttachment(att) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Add receipt photo", systemImage: "camera")
                    }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
                }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do { try store.deleteTransaction(txn.id); dismiss() }   // also unlinks receipt files
                    catch { errorMessage = i18nMessage(error) }
                }
            }
            .sheet(isPresented: $showingSplit) { SplitEditorView(txn: txn) }
            .quickLookPreview($previewURL)
            .sheet(isPresented: $showingRefundPicker) { RefundSourcePickerView { refundedTxId = $0 } }
            .onAppear { attachments = store.attachments(for: txn.id) }
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

    private func removeAttachment(_ att: AttachmentRow) {
        do {
            try store.removeAttachment(id: att.id, relPath: att.relPath)   // also unlinks the file
            attachments = store.attachments(for: txn.id)
        } catch { errorMessage = i18nMessage(error) }
    }

    private func save() {
        errorMessage = nil
        var patch: [String: JSONValue] = [
            "merchant": .string(merchant.isEmpty ? "Untitled" : merchant),
            "note": note.isEmpty ? .null : .string(note),
            "date": .string(Self.day(date)),
            "time": .string(Self.time(date)),
        ]
        // Amount + category edit (keep the original sign; the field is the magnitude).
        // Skip both on a split tx — its legs are owned by the split.
        // A non-split must have a valid amount; web blocks an empty/≤0 amount rather
        // than silently keeping the old value, so match that instead of skipping.
        if !isSplit {
            guard let parsed = DecimalInput.parse(amountText), parsed > 0 else {
                errorMessage = "Enter an amount greater than 0."; return
            }
            let signed = (originalNative < 0 ? -1.0 : 1.0) * parsed
            if abs(signed - originalNative) > 0.001 { patch["amount"] = .double(signed) }
            if !categoryId.isEmpty, categoryId != txn.category { patch["category"] = .string(categoryId) }
        }
        if status != (txn.pending == true ? .pending : .confirmed) { patch["status"] = .string(status.rawValue) }
        if txn.kind != "transfer", !accountId.isEmpty, accountId != txn.account { patch["account"] = .string(accountId) }
        if txn.kind == "refund", refundedTxId != txn.refundedTransactionId {
            patch["refundedTransactionId"] = refundedTxId.map(JSONValue.string) ?? .null
        }
        do {
            try store.apply(.updateTransaction, Args(["id": .string(txn.id), "patch": .object(patch)]))
            if selectedTags != Set(txn.tags ?? []) {
                try store.apply(.setTransactionTags, Args(["id": .string(txn.id),
                    "tagIds": .array(selectedTags.sorted().map { .string($0) })]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
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
