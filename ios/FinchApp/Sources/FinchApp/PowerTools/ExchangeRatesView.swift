import SwiftUI
import FinchCore

/// Phase 4 (FX tools) — view/add/delete exchange rates (units per USD hub).
/// setExchangeRate / deleteExchangeRate through the chokepoint.
struct ExchangeRatesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.exchangeRates.isEmpty {
                Text("No exchange rates. USD is the hub (rate 1).").foregroundStyle(.secondary)
            }
            ForEach(store.exchangeRates, id: \.self) { rate in
                HStack {
                    Text(rate.currency).fontWeight(.medium)
                    SourceBadge(source: rate.source)
                    Spacer()
                    Text(String(format: "%.4f", rate.rate))
                    Text(rate.date).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
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
        .errorAlert($errorMessage)
    }

    private func delete(_ r: ExchangeRate) {
        do { try store.apply(.deleteExchangeRate, Args(["date": .string(r.date), "currency": .string(r.currency)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Color-coded provenance badge (mirrors the web's SOURCE_STYLE). nil → "manual".
struct SourceBadge: View {
    let source: String?
    private var label: String { source ?? "manual" }
    private var color: Color {
        switch source {
        case "ECB": return .green
        case "Yahoo": return .blue
        default: return .orange   // manual / derived / nil
        }
    }
    var body: some View {
        Text(label)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("source \(label)")
    }
}

private let fxSources = ["ECB", "Yahoo", "manual"]

struct AddExchangeRateSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var currency = ""
    @State private var rate = ""
    @State private var date = Date()
    @State private var source = "manual"
    @State private var errorMessage: String?

    private var currencyOptions: [PickerOption] {
        Currencies.iso.filter { $0 != "USD" }.map { PickerOption(id: $0, name: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                SearchablePickerRow(title: "Currency", options: currencyOptions, selection: $currency)
                HStack { Text("Rate (per USD)"); Spacer(); TextField("0.0000", text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                DatePicker("As of", selection: $date, displayedComponents: .date)
                Picker("Source", selection: $source) { ForEach(fxSources, id: \.self) { Text($0).tag($0) } }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Add Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").bold()
                }
            }
            .onAppear { if currency.isEmpty { currency = currencyOptions.first?.id ?? "" } }
        }
    }

    private func save() {
        errorMessage = nil
        guard !currency.isEmpty else { errorMessage = "Pick a currency."; return }
        guard let r = DecimalInput.parse(rate), r > 0 else { errorMessage = "Enter a rate > 0."; return }
        do {
            try store.apply(.setExchangeRate, Args([
                "date": .string(AppDate.isoDay.string(from: date)),
                "currency": .string(currency),
                "rate": .double(r),
                "source": .string(source)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
