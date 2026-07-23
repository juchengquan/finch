import SwiftUI
import FinchCore

/// The ledger **base currency** field as a tap-to-open row + bottom sheet,
/// consistent with the Merchant/Category/Account pickers.
///
/// The sheet lists every ISO code with the ACTIVATED ones (the global tracked
/// set, plus the USD hub) pinned on top — the same ordering the Settings ›
/// Shared › Currencies page uses, because both are built from `fxCurrencyRows`.
/// Search reaches the rest; picking a non-activated code stages it for
/// activation, which the CALLER commits on save (see `fxTrackedAfterActivating`)
/// so cancelling the ledger sheet leaves nothing behind.
struct CurrencyPickerRow: View {
    let title: LocalizedStringKey            // "Base currency"
    var glyph: FieldGlyph = .name
    @Binding var code: String
    /// The effective tracked set — drives both the pinned ordering and the
    /// "will be activated" hint. Passed in so the row stays free of store access.
    let activated: [String]
    @State private var presented = false

    /// A staged pick that isn't activated yet gets flagged, so the pending
    /// tracked-set write is visible before the user commits the ledger.
    private var willActivate: Bool {
        fxTrackedAfterActivating(code, tracked: activated) != nil
    }

    var body: some View {
        Button { presented = true } label: {
            FieldRow(glyph: glyph, title: title, isEmpty: code.isEmpty) {
                // String(localized:) so the suffix goes through the catalog (a
                // String ternary would render verbatim and skip localization).
                Text(willActivate ? String(localized: "\(code) · will be activated") : code)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            CurrencyPickerSheet(title: title, code: $code, activated: activated)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// Search-driven single-select. COMMITS ON TAP (tap = select + dismiss) rather
/// than staging behind a Confirm — same reason as `MerchantPickerSheet`: iOS
/// collapses the navigation bar while a `.searchable` field is active, which
/// would hide a `.confirmationAction` exactly when the user has searched for the
/// code they want.
private struct CurrencyPickerSheet: View {
    let title: LocalizedStringKey
    @Binding var code: String
    let activated: [String]
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [FxCurrencyRow] {
        fxFilterRows(fxCurrencyRows(all: Currencies.iso, rates: store.exchangeRates,
                                    tracked: activated), query: query)
    }

    private func pick(_ picked: String) {
        code = picked
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                // Same Active/Inactive split as the Currencies page, but HEADED
                // here: that page can drop the titles because its per-row toggle
                // shows the state: this sheet has no toggle (tapping selects), so
                // the headers are what tell the two groups apart.
                let active = rows.filter { $0.isHub || $0.tracked }
                if !active.isEmpty {
                    Section("Active") {
                        ForEach(active, id: \.code) { row in
                            Button { pick(row.code) } label: { rowLabel(row) }.buttonStyle(.plain)
                        }
                    }
                }
                let inactive = rows.filter { !$0.isHub && !$0.tracked }
                if !inactive.isEmpty {
                    Section {
                        ForEach(inactive, id: \.code) { row in
                            Button { pick(row.code) } label: { rowLabel(row) }.buttonStyle(.plain)
                        }
                    } header: {
                        Text("Inactive")
                    } footer: {
                        Text("Picking one of these activates it when you save.")
                    }
                }
            }
            .searchable(text: $query, prompt: "Search or activate")
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
            }
        }
    }

    /// Mirrors the Currencies page row — first line "EUR (€)" (code + symbol),
    /// second line the name — minus the tracking toggle: here tapping selects,
    /// and activation rides along on save.
    private func rowLabel(_ row: FxCurrencyRow) -> some View {
        let name = FxCurrencyInfo.name(row.code)
        let codeLabel = FxCurrencyInfo.symbol(row.code).map { "\(row.code) (\($0))" } ?? row.code
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(codeLabel).fontWeight(.medium)
                // String(localized:) so the hub suffix goes through the catalog
                // (a String ternary would render verbatim and skip localization).
                Text(row.isHub ? String(localized: "\(name) · hub") : name)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.rate.map { String(format: "%.4f", $0) } ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
            if row.code.caseInsensitiveCompare(code) == .orderedSame {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
