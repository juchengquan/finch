import SwiftUI
import FinchCore

/// Add or edit an exchange rate by hand — the way out of `error.fx.noRate` for a
/// user who cannot fetch rates (offline, or a currency no free service carries).
///
/// The question is asked as a sentence, "1 KRW = ___ EUR", against the ledger's base,
/// and the ⇅ button flips it to "1 EUR = ___ KRW" for a figure quoted the other way
/// round. The footer always reads the answer back in the opposite direction, so a
/// rate typed upside down shows up as an absurd number before it is saved.
/// `FxManualQuote` does the arithmetic into the engine's USD-per-unit figure.
///
/// Saved through `setExchangeRate` with source "manual" — the same action and tag
/// as the web's FX dialog — so the row carries the orange "manual" badge and is
/// the only kind the history screen offers to edit.
struct ManualRateSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    /// The row being edited, or nil to add one.
    private let editing: ExchangeRate?
    @State private var code: String
    @State private var date: Date
    @State private var rateText = ""
    @State private var inverted = false
    /// What the user typed before the last flip, and the rounded reciprocal the flip
    /// put in the field. While the field still shows that reciprocal, the typed
    /// figure is what counts: 0.00073 flipped reads "1369.86", and saving that
    /// rounded figure would store 0.000730002 instead.
    @State private var beforeFlip: (shown: String, typed: String)?
    @State private var seeded = false
    /// The text an edit opened with — six significant digits of the stored figure.
    /// Saved untouched, the stored figure is kept rather than its rounding.
    @State private var seedText: String?
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    /// `currency` pre-fills the add form (from a currency's history, or from a
    /// refused save); `editing` opens an existing manual row.
    init(currency: String? = nil, editing: ExchangeRate? = nil) {
        self.editing = editing
        _code = State(initialValue: editing?.currency ?? currency ?? "")
        _date = State(initialValue: editing.flatMap { AppDate.isoDay.date(from: $0.date) } ?? Date())
    }

    private var day: String { AppDate.isoDay.string(from: date) }

    private var quote: FxManualQuote {
        FxManualQuote.make(currency: code, base: store.baseCurrency, date: day, rates: store.exchangeRates)
    }

    /// The effective tracked set — a currency picked from the inactive group is
    /// activated on save, as `CurrencyPickerRow` promises.
    private var activated: [String] {
        fxEffectiveTracked(stored: store.trackedCurrencies,
                           fallback: RateAutoUpdater.currenciesInUse(store: store))
    }

    /// Another row already saved for this currency and day — saving replaces it.
    private var replaced: ExchangeRate? {
        store.exchangeRates.first { $0.currency == code && $0.date == day && $0 != editing }
    }

    /// USD is the hub every rate is measured against; it has no rate of its own.
    private var needsRate: Bool { !code.isEmpty && code != "USD" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if editing == nil {
                        CurrencyPickerRow(title: "Currency", glyph: .currency, code: $code, activated: activated)
                            .accessibilityIdentifier("manualRate.currency")
                    } else {
                        FieldRow(glyph: .currency, title: "Currency") { Text(verbatim: code) }
                    }
                    if needsRate {
                        rateRow
                        FieldRow(glyph: .date, title: "Date") {
                            DatePicker("Date", selection: $date, displayedComponents: [.date])
                                .labelsHidden()
                        }
                    }
                } footer: {
                    footer
                }
                if editing != nil {
                    Section {
                        Button("Delete Rate", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .finchSheetForm()
            .navigationTitle(editing == nil ? "Add Rate" : "Edit Rate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
            .alert("Delete rate?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(verbatim: "\(code) · \(editing?.date ?? "")")
            }
            .onAppear(perform: seed)
        }
    }

    /// "1 KRW = [ 0.00073 ] USD  ⇅" — the codes on either side of the field are the
    /// whole label, so the row reads as one unambiguous sentence.
    private var rateRow: some View {
        let terms = quote.terms(inverted: inverted)
        return FieldRow(glyph: .rate, title: "Rate", trailing: {
            Button(action: flip) {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Swap direction")
        }, content: {
            HStack(spacing: 6) {
                Text(verbatim: "1 \(terms.one) =").foregroundStyle(.secondary)
                TextField("0", text: $rateText)
                    .numericInput($rateText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(Text(verbatim: "1 \(terms.one) = ? \(terms.other)"))
                    .accessibilityIdentifier("manualRate.rate")
                Text(verbatim: terms.other)
            }
        })
    }

    @ViewBuilder private var footer: some View {
        if code == "USD" {
            Text("USD is the hub every rate is measured against, so it needs none.")
        } else if needsRate {
            VStack(alignment: .leading, spacing: 4) {
                // The same rate read the other way round: a figure typed upside
                // down is off by a factor of a million here, and plainly so.
                if let typed = DecimalInput.parse(rateText), typed > 0 {
                    let terms = quote.terms(inverted: !inverted)
                    let other = flipStillShown.map { $0.typed } ?? fxRateText(1 / typed)
                    Text(verbatim: "1 \(terms.one) = \(other) \(terms.other)")
                        .accessibilityIdentifier("manualRate.inverse")
                }
                if quote.quote != store.baseCurrency && store.baseCurrency != code {
                    Text("\(store.baseCurrency) has no exchange rate yet, so this one is against USD.")
                }
                if replaced != nil {
                    Text("Replaces the rate already saved for this day.")
                }
            }
        }
    }

    /// Editing opens on the stored figure, read in the form's direction. Runs once:
    /// the store is not reachable from `init`.
    private func seed() {
        guard !seeded else { return }
        seeded = true
        if let editing {
            rateText = fxRateText(quote.entered(usdPerUnit: editing.rate, inverted: inverted))
            seedText = rateText
        }
    }

    /// `beforeFlip`, while the field has not been edited since the flip.
    private var flipStillShown: (shown: String, typed: String)? {
        beforeFlip.flatMap { $0.shown == rateText ? $0 : nil }
    }

    /// Flip the sentence and keep its meaning: the typed figure becomes its
    /// reciprocal, and flipping straight back restores exactly what was typed.
    private func flip() {
        if let b = flipStillShown {
            rateText = b.typed
            beforeFlip = nil
        } else if let typed = DecimalInput.parse(rateText), typed > 0 {
            let shown = fxRateText(1 / typed)
            beforeFlip = (shown, rateText)
            rateText = shown
        }
        inverted.toggle()
    }

    /// The stored USD-per-unit figure for what is on the form, nil unless > 0.
    private var usdPerUnit: Double? {
        if let editing, !inverted, rateText == seedText { return editing.rate }
        if let b = flipStillShown, let typed = DecimalInput.parse(b.typed) {
            return quote.usdPerUnit(entered: typed, inverted: !inverted)
        }
        return DecimalInput.parse(rateText).flatMap { quote.usdPerUnit(entered: $0, inverted: inverted) }
    }

    private func save() {
        errorMessage = nil
        guard !code.isEmpty else { errorMessage = String(localized: "Pick a currency."); return }
        guard let usdPerUnit else {
            errorMessage = String(localized: "Enter a rate greater than 0."); return
        }
        // Snapshot before the write, which reprojects (see AddLedgerSheet).
        let activation = editing == nil ? fxTrackedAfterActivating(code, tracked: activated) : nil
        do {
            try store.apply(.setExchangeRate, Args([
                "date": .string(day), "currency": .string(code),
                "rate": .double(usdPerUnit), "source": .string(fxManualSource)]))
            // A moved date is a new key: the new row is written first, so a refusal
            // leaves the old one in place.
            if let editing, editing.date != day {
                try store.apply(.deleteExchangeRate, Args(["date": .string(editing.date),
                                                           "currency": .string(editing.currency)]))
            }
            if let codes = activation {
                try? store.apply(.setTrackedCurrencies, Args(["codes": .array(codes.map { .string($0) })]))
            }
            dismiss()
            Haptics.success()
        } catch { errorMessage = i18nMessage(error); Haptics.warning() }
    }

    private func delete() {
        guard let editing else { return }
        do {
            try store.apply(.deleteExchangeRate, Args(["date": .string(editing.date),
                                                       "currency": .string(editing.currency)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}

/// The way out offered under a save refused for want of a rate: "Enter a KRW rate"
/// opens `ManualRateSheet` on that currency. Once a rate for it exists, `onResolved`
/// clears the refusal, so the next ✓ simply saves.
struct NoRateFixButton: View {
    @EnvironmentObject private var store: FinchStore
    let currency: String
    let onResolved: () -> Void
    @State private var presented = false

    var body: some View {
        Button("Enter a \(currency) rate") { presented = true }
            .font(.footnote)
            // Cleared on DISMISS, not on save: clearing removes this row, and the
            // sheet hangs off it.
            .sheet(isPresented: $presented, onDismiss: {
                if fxLatest(store.exchangeRates, currency) != nil { onResolved() }
            }) {
                ManualRateSheet(currency: currency)
            }
    }
}
