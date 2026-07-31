import SwiftUI
import FinchCore

/// The Merchant/Source field as a tap-to-open row + bottom sheet, consistent
/// with the Category/Account pickers. Merchant is free text, so the sheet's
/// search box doubles as new-merchant entry: typing a name with no exact match
/// surfaces a "Use ‹text›" row. A name that isn't an existing counterparty is
/// created on save (the caller's save path already does this for any
/// unrecognized merchant).
struct MerchantPickerRow: View {
    let title: String                     // "Merchant" or "Source"
    let glyph: FieldGlyph
    let counterparties: [Counterparty]
    @Binding var merchant: String
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            FieldRow(glyph: glyph, title: LocalizedStringKey(title), isEmpty: merchant.isEmpty) {
                Text(merchant)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            MerchantPickerSheet(title: title, counterparties: counterparties, merchant: $merchant)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// Search-driven single-select. Unlike the staged Category/Account sheet, this
/// one COMMITS ON TAP (tap = select + dismiss) rather than staging behind a
/// Confirm button. Reason: searching is the primary interaction here (the field
/// doubles as new-merchant entry), and iOS collapses the navigation bar while a
/// `.searchable` field is active — which hides a `.confirmationAction` Confirm
/// exactly when the user has typed a name to "Use". Commit-on-tap keeps the
/// interaction reachable and gives immediate feedback (the sheet closes).
private struct MerchantPickerSheet: View {
    let title: String
    let counterparties: [Counterparty]
    @Binding var merchant: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    init(title: String, counterparties: [Counterparty], merchant: Binding<String>) {
        self.title = title
        self.counterparties = counterparties
        self._merchant = merchant
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [Counterparty] {
        trimmedQuery.isEmpty ? counterparties
            : counterparties.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }
    /// Show "Use ‹query›" only when the typed text isn't already an exact name.
    private var showUseNew: Bool {
        !trimmedQuery.isEmpty
            && !counterparties.contains { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    private func pick(_ name: String) {
        merchant = name
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                Button { pick("") } label: {
                    HStack {
                        Text("None").foregroundStyle(.secondary)
                        Spacer()
                        if merchant.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)

                if showUseNew {
                    Button { pick(trimmedQuery) } label: {
                        Label("Use “\(trimmedQuery)”", systemImage: "plus.circle").foregroundStyle(.tint)
                    }
                }

                ForEach(filtered) { cp in
                    Button { pick(cp.name) } label: {
                        HStack {
                            MerchantLabel(name: cp.name, isVerified: cp.isVerified)
                            Spacer()
                            if cp.name.caseInsensitiveCompare(merchant) == .orderedSame {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search or add")
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") }
            }
        }
    }
}
