import SwiftUI
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
        }
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
