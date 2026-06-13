import SwiftUI
import FinchCore

/// Holdings (investment positions) — the 7th write screen, reached from the
/// Accounts tab. Lists each position with shares, market value, and unrealized
/// gain/loss; add a position, update its price, or delete it. createHolding /
/// setHoldingPrice / deleteHolding through FinchStore.apply.
struct HoldingsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var pricing: Holding?

    private var investmentAccounts: [AccountRow] {
        store.accounts.filter { $0.type == "investment" }
    }

    var body: some View {
        Group {
            if store.holdings.isEmpty {
                ContentUnavailableView {
                    Label("No holdings", systemImage: "chart.bar")
                } description: {
                    Text(investmentAccounts.isEmpty
                         ? "Add an investment account first (import a pack with one)."
                         : "Tap + to add a position.")
                }
            } else {
                List {
                    ForEach(store.holdings, id: \.id) { h in
                        Button { pricing = h } label: { HoldingRow(holding: h) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(h) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
        }
        .navigationTitle("Holdings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Holding")
                    .disabled(investmentAccounts.isEmpty)
            }
        }
        .sheet(isPresented: $showingAdd) { AddHoldingSheet(accounts: investmentAccounts) }
        .sheet(item: $pricing) { SetHoldingPriceSheet(holding: $0) }
    }

    private func delete(_ h: Holding) { try? store.apply(.deleteHolding, Args(["id": .string(h.id)])) }
}

struct HoldingRow: View {
    @EnvironmentObject private var store: FinchStore
    let holding: Holding
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol).fontWeight(.medium)
                Text("\(holding.shares.formatted()) shares").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let v = Selectors.holdingValue(holding) {
                    Text(store.displayMoney(v, from: holding.currency)).fontWeight(.semibold)
                } else {
                    Text("No price").font(.caption).foregroundStyle(.secondary)
                }
                if let gl = Selectors.holdingGainLoss(holding) {
                    Text(store.displayMoney(gl, from: holding.currency))
                        .font(.caption2).foregroundStyle(gl < 0 ? .red : .green)
                }
            }
        }
    }
}

/// Add a position to an investment account.
struct AddHoldingSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let accounts: [AccountRow]
    @State private var accountId = ""
    @State private var symbol = ""
    @State private var shares = ""
    @State private var costBasis = ""
    @State private var lastPrice = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Account", selection: $accountId) { ForEach(accounts) { Text($0.name ?? "—").tag($0.id) } }
                TextField("Symbol (e.g. AAPL)", text: $symbol)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                HStack { Text("Shares"); Spacer(); TextField("0", text: $shares).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Cost basis"); Spacer(); TextField("0.00", text: $costBasis).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Last price (optional)"); Spacer(); TextField("0.00", text: $lastPrice).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Add Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onAppear { if accountId.isEmpty { accountId = accounts.first?.id ?? "" } }
        }
    }

    private func save() {
        errorMessage = nil
        guard !symbol.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a symbol."; return }
        guard let sh = Double(shares), sh > 0 else { errorMessage = "Enter share count."; return }
        guard let cb = Double(costBasis), cb >= 0 else { errorMessage = "Enter the cost basis."; return }
        var args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(accountId),
            "symbol": .string(symbol), "shares": .double(sh), "costBasis": .double(cb),
        ]
        if let p = Double(lastPrice), p >= 0 { args["lastPrice"] = .double(p) }
        do {
            try store.apply(.createHolding, Args(args))
            dismiss()
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }
}

/// Update the latest price for a position.
struct SetHoldingPriceSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let holding: Holding
    @State private var price: String
    @State private var errorMessage: String?

    init(holding: Holding) {
        self.holding = holding
        _price = State(initialValue: holding.lastPrice.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Symbol", value: holding.symbol)
                HStack { Text("Price"); Spacer(); TextField("0.00", text: $price).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Set Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard let p = Double(price), p >= 0 else { errorMessage = "Enter a price."; return }
        do {
            try store.apply(.setHoldingPrice, Args([
                "id": .string(holding.id), "price": .double(p), "date": .string(Self.today()),
            ]))
            dismiss()
        } catch let e as I18nError { errorMessage = e.message } catch { errorMessage = "\(error)" }
    }

    private static func today() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
