import SwiftUI
import UniformTypeIdentifiers
import FinchCore

/// Phase 4 — import a bank-statement CSV for an account: parse, match against
/// existing transactions, then Apply — matched rows are marked cleared
/// (setCleared), unmatched rows are added (addTransaction). Routes FinchStore.apply.
struct ImportStatementView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var accountId = ""
    @State private var results: [StatementMatcher.Result] = []
    @State private var importing = false
    @State private var errorMessage: String?

    private var matchedCount: Int { results.filter { $0.matchedTxId != nil }.count }
    private var newCount: Int { results.filter { $0.matchedTxId == nil }.count }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Account", selection: $accountId) {
                    ForEach(store.accounts) { Text($0.name ?? "—").tag($0.id) }
                }
                Section {
                    Button {
                        importing = true
                    } label: { Label("Choose CSV file…", systemImage: "doc.badge.plus") }
                        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .text],
                                      allowsMultipleSelection: false) { handlePick($0) }
                }
                if !results.isEmpty {
                    Section("\(matchedCount) matched · \(newCount) new") {
                        ForEach(results, id: \.row.id) { r in
                            HStack {
                                Image(systemName: r.matchedTxId != nil ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(r.matchedTxId != nil ? .green : .blue)
                                VStack(alignment: .leading) {
                                    Text(r.row.description.isEmpty ? "—" : r.row.description)
                                    Text(r.row.date).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(store.displayMoney(r.row.amount, from: account(accountId)?.currency)).font(.callout)
                            }
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Import statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: apply) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Apply").disabled(results.isEmpty)
                        .confirmCheckmarkStyle()
                }
            }
            .onAppear { if accountId.isEmpty { accountId = store.accounts.first?.id ?? "" } }
        }
    }

    private func account(_ id: String) -> AccountRow? { store.accounts.first { $0.id == id } }

    private func handlePick(_ result: Result<[URL], Error>) {
        errorMessage = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { errorMessage = "Couldn't read the file."; return }
        let rows = StatementCSV.parse(text)
        if rows.isEmpty { errorMessage = "No rows found (expects date, description, amount)."; return }
        results = StatementMatcher.match(rows, txns: store.txns, accountId: accountId)
    }

    private func apply() {
        errorMessage = nil
        do {
            for r in results {
                if let txId = r.matchedTxId {
                    try store.apply(.setCleared, Args(["id": .string(txId), "cleared": .bool(true)]))
                } else {
                    try store.apply(.addTransaction, Args([
                        "ledgerId": .string(store.activeLedgerId), "accountId": .string(accountId),
                        "amount": .double(r.row.amount),
                        "merchant": .string(r.row.description.isEmpty ? "Imported" : r.row.description),
                        "categoryId": .string(store.pickableCategories.first?.id ?? ""),
                        "date": .string(r.row.date), "skipRules": .bool(false)]))
                }
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
