import SwiftUI
import PhotosUI
import CryptoKit
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

    /// The original native (account-currency) amount, the basis for the edit.
    private var originalNative: Double { txn.nativeAmount ?? txn.amount }
    /// A split transaction owns its categories via legs — hide amount/category here.
    private var isSplit: Bool { (txn.splits?.count ?? 0) >= 2 }

    init(txn: Tx) {
        self.txn = txn
        _merchant = State(initialValue: txn.merchant)
        _note = State(initialValue: txn.note ?? "")
        _date = State(initialValue: Self.parse(txn.date, txn.time) ?? Date())
        _categoryId = State(initialValue: txn.category ?? "")
        _amountText = State(initialValue: String(format: "%g", abs(txn.nativeAmount ?? txn.amount)))
        _selectedTags = State(initialValue: Set(txn.tags ?? []))
    }

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { txn.amount > 0 ? $0.kind == "income" : $0.kind != "income" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Merchant", text: $merchant)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
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
                        Picker("Category", selection: $categoryId) {
                            ForEach(categories) { Text($0.name).tag($0.id) }
                        }
                        Button("Split across categories…") { showingSplit = true }
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
                        HStack {
                            Image(systemName: att.kind == "pdf" ? "doc.richtext" : "photo")
                                .foregroundStyle(.secondary)
                            Text(att.originalFilename ?? att.kind.capitalized)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removeAttachment(att) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Add receipt photo", systemImage: "camera")
                    }
                }

                Section {
                    if txn.pending == true {
                        Button("Confirm transaction") { run(.confirmTransaction, ["id": .string(txn.id)]) }
                    }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do { try store.deleteTransaction(txn.id); dismiss() }   // also unlinks receipt files
                    catch { errorMessage = i18nMessage(error) }
                }
            }
            .sheet(isPresented: $showingSplit) { SplitEditorView(txn: txn) }
            .onAppear { attachments = store.attachments(for: txn.id) }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await addReceipt(item) }
            }
        }
    }

    /// Save a picked photo into the live attachments tree + record it via the
    /// chokepoint (the in-app counterpart to the Share Extension flow).
    private func addReceipt(_ item: PhotosPickerItem) async {
        errorMessage = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let attId = "att-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = store.attachmentsRoot.appendingPathComponent(txn.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rel = "attachments/\(txn.id)/\(attId).jpg"
        try? data.write(to: store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        do {
            try store.apply(.setEntryAttachment, Args([
                "entryId": .string(txn.id), "kind": .string("image"), "relPath": .string(rel),
                "mimeType": .string("image/jpeg"), "byteSize": .double(Double(data.count)), "sha256": .string(sha)]))
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
        // Amount edit (keep the original sign; the field is the magnitude).
        if let parsed = DecimalInput.parse(amountText), parsed > 0 {
            let signed = (originalNative < 0 ? -1.0 : 1.0) * parsed
            if abs(signed - originalNative) > 0.001 { patch["amount"] = .double(signed) }
        }
        // Category edit — updateTransaction now rebuilds the category leg too.
        // (Skip amount/category on a split tx — its legs are owned by the split.)
        if isSplit { patch["amount"] = nil }
        if !isSplit, !categoryId.isEmpty, categoryId != txn.category { patch["category"] = .string(categoryId) }
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
