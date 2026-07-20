import SwiftUI
import FinchCore

/// Settings › Currencies — the FX home. Auto-update controls on top (master
/// toggle, last-updated, manual refresh), then ALL ISO currencies (hub first,
/// tracked A–Z, rest A–Z, searchable): code + localized name (sign), latest
/// USD-per-unit rate, and a tracking toggle that drives what the daily
/// Frankfurter fetch requests. Tap → per-currency history. Writes stay on the
/// setExchangeRate / deleteExchangeRate / setTrackedCurrencies chokepoints.
struct CurrenciesView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var lastUpdated: Date?
    @State private var refreshNote: LocalizedStringKey?
    @State private var query = ""

    /// The user's explicit tracked set, or the seeded default before first toggle.
    private var effectiveTracked: [String] {
        fxEffectiveTracked(stored: store.trackedCurrencies,
                           fallback: RateAutoUpdater.currenciesInUse(store: store))
    }

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

            // Two groups: Active (the hub USD + tracked currencies) and Inactive
            // (the rest). USD is always Active and can't be toggled off (isHub).
            let rows = fxFilterRows(fxCurrencyRows(all: Currencies.iso, rates: store.exchangeRates, tracked: effectiveTracked), query: query)
            Section("Active") {
                ForEach(rows.filter { $0.isHub || $0.tracked }, id: \.code) { row in
                    NavigationLink {
                        ExchangeRateHistoryView(currency: row.code)
                    } label: {
                        currencyRow(row)
                    }
                }
            }
            let inactive = rows.filter { !$0.isHub && !$0.tracked }
            if !inactive.isEmpty {
                Section("Inactive") {
                    ForEach(inactive, id: \.code) { row in
                        NavigationLink {
                            ExchangeRateHistoryView(currency: row.code)
                        } label: {
                            currencyRow(row)
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Currencies")
        .errorAlert($errorMessage)
        .onAppear { lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date }
    }

    private func currencyRow(_ row: FxCurrencyRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.code).fontWeight(.medium)
                // String(localized:) so the hub suffix goes through the catalog
                // (a String ternary would render verbatim and skip localization).
                Text(row.isHub ? String(localized: "\(row.label) · hub") : row.label)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.rate.map { String(format: "%.4f", $0) } ?? "—")
                .foregroundStyle(row.rate == nil ? Color.secondary : Color.primary)
            if !row.isHub {
                Toggle("", isOn: Binding(get: { row.tracked }, set: { setTracked(row.code, $0) }))
                    .labelsHidden()
                    .accessibilityLabel(Text("Track \(row.code)"))
            }
        }
        .padding(.vertical, 2)
    }

    /// Tracking writes materialize the app_state key (seed ± code). Toggling ON a
    /// currency with no stored rate fetches immediately (manual-act semantics).
    private func setTracked(_ code: String, _ on: Bool) {
        var set = Set(effectiveTracked)
        if on { set.insert(code) } else { set.remove(code) }
        do {
            try store.apply(.setTrackedCurrencies, Args(["codes": .array(set.sorted().map { JSONValue.string($0) })]))
            if on && fxLatest(store.exchangeRates, code) == nil { refreshNow() }
        } catch { errorMessage = i18nMessage(error) }
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
