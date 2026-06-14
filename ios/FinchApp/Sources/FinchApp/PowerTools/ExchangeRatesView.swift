import SwiftUI
import FinchCore

/// Phase 4 (FX tools) — view/add/delete exchange rates (units per USD hub).
/// setExchangeRate / deleteExchangeRate through the chokepoint.
struct ExchangeRatesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false

    var body: some View {
        List {
            if store.exchangeRates.isEmpty {
                Text("No exchange rates. USD is the hub (rate 1).").foregroundStyle(.secondary)
            }
            ForEach(store.exchangeRates, id: \.self) { rate in
                HStack {
                    Text(rate.currency).fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.4f", rate.rate))
                    Text(rate.date).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Exchange rates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rate")
            }
        }
        .sheet(isPresented: $showingAdd) { AddExchangeRateSheet() }
    }

    private func delete(_ r: ExchangeRate) {
        try? store.apply(.deleteExchangeRate, Args(["date": .string(r.date), "currency": .string(r.currency)]))
    }
}

struct AddExchangeRateSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var currency = ""
    @State private var rate = ""
    @State private var date = Date()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Currency (e.g. EUR)", text: $currency)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                HStack { Text("Rate (per USD)"); Spacer(); TextField("0.0000", text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                DatePicker("As of", selection: $date, displayedComponents: .date)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Add Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard let r = DecimalInput.parse(rate), r > 0 else { errorMessage = "Enter a rate > 0."; return }
        do {
            try store.apply(.setExchangeRate, Args([
                "date": .string(AppDate.isoDay.string(from: date)),
                "currency": .string(currency.trimmingCharacters(in: .whitespaces).uppercased()),
                "rate": .double(r)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
