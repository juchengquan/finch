import SwiftUI
import FinchCore

/// One currency's full rate history: trend sparkline (shown at ≥3 points) above
/// date-descending rows. Per-row delete + "Delete all" go through the
/// deleteExchangeRate chokepoint; when the last row goes, pop back.
struct ExchangeRateHistoryView: View {
    let currency: String
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAll = false
    @State private var errorMessage: String?

    private var rows: [ExchangeRate] {
        store.exchangeRates.filter { $0.currency == currency }.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            let series = fxSeries(store.exchangeRates, currency)
            if series.count >= 3 {
                Section {
                    Sparkline(values: series)
                        .frame(height: 48)
                }
            }
            Section {
                ForEach(rows, id: \.self) { rate in
                    HStack {
                        Text(fxDisplayDay(rate.date, withYear: true))
                        Spacer()
                        Text(String(format: "%.4f", rate.rate))
                        SourceBadge(source: rate.source)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle(currency)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) { showDeleteAll = true } label: {
                        Label("Delete all \(currency) rates", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
            }
        }
        .confirmationDialog("Delete all \(currency) rates", isPresented: $showDeleteAll, titleVisibility: .visible) {
            Button("Delete \(rows.count) rates", role: .destructive) { deleteAll() }
        }
        .errorAlert($errorMessage)
    }

    private func delete(_ r: ExchangeRate) {
        do {
            try store.apply(.deleteExchangeRate, Args(["date": .string(r.date), "currency": .string(r.currency)]))
            if rows.isEmpty { dismiss() }
        } catch { errorMessage = i18nMessage(error) }
    }

    private func deleteAll() {
        do {
            for r in rows {
                try store.apply(.deleteExchangeRate, Args(["date": .string(r.date), "currency": .string(r.currency)]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
