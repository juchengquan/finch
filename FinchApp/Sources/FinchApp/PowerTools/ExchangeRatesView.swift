import SwiftUI
import FinchCore

/// Phase 4 (FX tools) — the FX home. Auto-update controls (moved here from
/// Settings › Advanced in the page redesign), manual "Refresh now", and rates
/// grouped one-row-per-currency (latest rate, both directions); history and
/// deletes live in ExchangeRateHistoryView. Writes stay on the
/// setExchangeRate / deleteExchangeRate chokepoints.
struct ExchangeRatesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var lastUpdated: Date?
    @State private var refreshNote: LocalizedStringKey?

    var body: some View {
        List {
            Section {
                Toggle("Auto-update exchange rates", isOn: autoUpdateBinding)
                if let lastUpdated {
                    LabeledContent("Last updated", value: lastUpdated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale)))
                }
                Button { refreshNow() } label: {
                    HStack {
                        Text("Refresh now")
                        Spacer()
                        if refreshing {
                            ProgressView()
                        } else if let refreshNote {
                            Text(refreshNote).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(refreshing)
            } footer: {
                Text("Fetches daily reference rates for your currencies from Frankfurter (frankfurter.dev, central-bank data). Only currency codes are sent.")
            }

            Section("Rates") {
                if store.exchangeRates.isEmpty {
                    Text("No exchange rates. USD is the hub (rate 1).").foregroundStyle(.secondary)
                }
                ForEach(fxCurrencies(store.exchangeRates), id: \.self) { code in
                    if let latest = fxLatest(store.exchangeRates, code) {
                        NavigationLink {
                            ExchangeRateHistoryView(currency: code)
                        } label: {
                            currencyRow(code: code, latest: latest)
                        }
                    }
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
        .onAppear { lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date }
    }

    /// Latest rate both ways: primary = stored USD-per-unit, caption = inverse.
    private func currencyRow(code: String, latest: ExchangeRate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(code).fontWeight(.medium)
                SourceBadge(source: latest.source)
            }
            Text("1 \(code) = \(String(format: "%.4f", latest.rate)) USD")
            Text("1 USD = \(inverseText(latest.rate)) \(code) · \(fxDisplayDay(latest.date))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func inverseText(_ rate: Double) -> String {
        rate > 0 ? String(format: "%.4f", 1.0 / rate) : "—"
    }

    /// A deliberate manual act — bypasses toggle + throttle (RateAutoUpdater.refresh).
    private func refreshNow() {
        refreshing = true
        refreshNote = nil
        Task {
            let outcome = await RateAutoUpdater.refresh(store: store)
            refreshing = false
            lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date
            switch outcome {
            case .updated(let n): refreshNote = "Updated \(n) rates"
            case .skipped: refreshNote = "Nothing to update"
            case .failed: errorMessage = String(localized: "Couldn't reach frankfurter.dev. Check your connection and try again.")
            }
        }
    }

    /// Absent key == ON (default-ON semantics shared with RateAutoUpdater).
    private var autoUpdateBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: RateAutoUpdater.toggleKey) == nil
                   || UserDefaults.standard.bool(forKey: RateAutoUpdater.toggleKey) },
            set: { UserDefaults.standard.set($0, forKey: RateAutoUpdater.toggleKey) })
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
