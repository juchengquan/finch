import SwiftUI
import FinchCore

/// One currency's full rate history: trend sparkline (shown at ≥3 points) above
/// date-descending rows. Per-row delete + "Delete all" go through the
/// deleteExchangeRate chokepoint; when the last row goes, pop back. "+" adds a
/// rate by hand; a hand-entered row opens for editing (`ManualRateSheet`).
struct ExchangeRateHistoryView: View {
    let currency: String
    @EnvironmentObject private var store: FinchStore
    @State private var pendingDelete: ExchangeRate?   // rate row awaiting delete confirmation
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAll = false
    @State private var errorMessage: String?
    @State private var addingRate = false
    @State private var editingRate: ExchangeRate?   // a hand-entered row being edited

    private var rows: [ExchangeRate] {
        store.exchangeRates.filter { $0.currency == currency }.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            let series = fxDisplaySeries(store.exchangeRates, currency)
            // One direction for the whole history, set by the latest rate (FxRateDisplay).
            let inverted = fxReadsInverted(latest: rows.first?.rate)
            if series.count >= 3 {
                Section {
                    Sparkline(values: series)
                        .frame(height: 48)
                }
            }
            Section {
                if rows.isEmpty {
                    Text("No rates yet.").foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.self) { rate in
                    HStack {
                        Text(fxDisplayDay(rate.date, withYear: true))
                        Spacer()
                        Text(verbatim: fxRateDisplay(rate.rate, currency: currency, inverted: inverted) ?? "")
                            .font(.subheadline).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                        SourceBadge(source: rate.source)
                    }
                    // Only a hand-entered rate opens for editing; a fetched one is
                    // the provider's figure.
                    .contentShape(Rectangle())
                    .onTapGesture { if fxIsManual(rate) { editingRate = rate } }
                    .swipeActions(edge: .trailing) {
                        // Not role: .destructive — fake removal animation pre-confirm.
                        Button { pendingDelete = rate } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                    }
                    .contextMenu {
                        if fxIsManual(rate) {
                            Button { editingRate = rate } label: { Label("Edit", systemImage: "pencil") }
                        }
                        Button(role: .destructive) { pendingDelete = rate } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle(currency)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingRate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add rate")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !rows.isEmpty {
                        Button(role: .destructive) { showDeleteAll = true } label: {
                            Label("Delete all \(currency) rates", systemImage: "trash")
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
                // Anchored on the ⋯ menu (iOS 26 positions popouts at their source).
                .confirmationDialog("Delete all \(currency) rates", isPresented: $showDeleteAll, titleVisibility: .visible) {
                    Button("Delete \(rows.count) rates", role: .destructive) { deleteAll() }
                }
            }
        }
        // Centered ALERT (window-level) — see ActivityTab's delete alert.
        .alert("Delete rate?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { r in
            Button("Delete", role: .destructive) { delete(r) }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text("\(currency) · \(r.date)")
        }
        .errorAlert($errorMessage)
        .sheet(isPresented: $addingRate) { ManualRateSheet(currency: currency) }
        .sheet(isPresented: Binding(get: { editingRate != nil }, set: { if !$0 { editingRate = nil } })) {
            if let editingRate { ManualRateSheet(editing: editingRate) }
        }
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
