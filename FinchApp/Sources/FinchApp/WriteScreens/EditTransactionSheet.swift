import SwiftUI
import PhotosUI
import CryptoKit
import FinchCore

/// Edit Transaction (port of the web edit-transaction-form, scoped to what the
/// iOS engine supports). Editable: merchant, note, date/time. Amount/category/
/// account edits are DEFERRED in the chokepoint (notImplemented.txMoneyEdit), so
/// they're shown read-only. Also exposes the lifecycle actions: confirm a pending
/// entry, toggle reviewed, and delete. All writes go through FinchStore.apply.
struct EditTransactionSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let txn: Tx

    @State private var merchant: String
    @State private var note: String
    @State private var date: Date
    @State private var categoryId: String
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var attachments: [AttachmentRow] = []
    @State private var pickedPhoto: PhotosPickerItem?

    init(txn: Tx) {
        self.txn = txn
        _merchant = State(initialValue: txn.merchant)
        _note = State(initialValue: txn.note ?? "")
        _date = State(initialValue: Self.parse(txn.date, txn.time) ?? Date())
        _categoryId = State(initialValue: txn.category ?? "")
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
                Section {
                    LabeledContent("Amount", value: store.displayMoneyBase(txn.amount))
                    Picker("Category", selection: $categoryId) {
                        ForEach(categories) { Text($0.name).tag($0.id) }
                    }
                } header: {
                    Text("Amount & category")
                } footer: {
                    Text("Amount can't be edited — delete and re-add to change it.")
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
                Button("Delete", role: .destructive) { run(.deleteTransaction, ["id": .string(txn.id)]) }
            }
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
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }

    private func removeAttachment(_ att: AttachmentRow) {
        do {
            try store.apply(.removeAttachment, Args(["id": .string(att.id)]))
            attachments = store.attachments(for: txn.id)
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }

    private func save() {
        errorMessage = nil
        let patch: [String: JSONValue] = [
            "merchant": .string(merchant.isEmpty ? "Untitled" : merchant),
            "note": note.isEmpty ? .null : .string(note),
            "date": .string(Self.day(date)),
            "time": .string(Self.time(date)),
        ]
        do {
            try store.apply(.updateTransaction, Args(["id": .string(txn.id), "patch": .object(patch)]))
            // Category edits go through bulkRecategorize (rebuilds the category leg).
            if !categoryId.isEmpty, categoryId != txn.category {
                try store.apply(.bulkRecategorize, Args(["ids": .array([.string(txn.id)]), "categoryId": .string(categoryId)]))
            }
            dismiss()
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }

    /// Run a lifecycle action then dismiss (these don't re-edit the open form).
    private func run(_ action: ActionName, _ args: [String: JSONValue]) {
        do { try store.apply(action, Args(args)); dismiss() }
        catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }

    // MARK: date/time helpers
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
    }()
    private static let dtFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
    private static func parse(_ ymd: String, _ hm: String?) -> Date? {
        dtFmt.date(from: "\(ymd) \(hm ?? "00:00")") ?? dayFmt.date(from: ymd)
    }
}
