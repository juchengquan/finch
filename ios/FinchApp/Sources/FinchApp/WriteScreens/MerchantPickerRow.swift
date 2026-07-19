import SwiftUI
import FinchCore

/// The Merchant/Source field as a tap-to-open row + bottom sheet, consistent
/// with the Category/Account pickers. Merchant is free text, so the sheet's
/// search box doubles as new-merchant entry: typing a name with no exact match
/// surfaces a "Use ‹text›" row. The chosen name is staged and applied on
/// Confirm; a name that isn't an existing counterparty is created on save (the
/// caller's save path already does this for any unrecognized merchant).
struct MerchantPickerRow: View {
    let title: String                     // "Merchant" or "Source"
    let counterparties: [Counterparty]
    @Binding var merchant: String
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(merchant.isEmpty ? "None" : merchant).foregroundStyle(.secondary)
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

private struct MerchantPickerSheet: View {
    let title: String
    let counterparties: [Counterparty]
    @Binding var merchant: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: String

    init(title: String, counterparties: [Counterparty], merchant: Binding<String>) {
        self.title = title
        self.counterparties = counterparties
        self._merchant = merchant
        self._staged = State(initialValue: merchant.wrappedValue)
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

    var body: some View {
        NavigationStack {
            List {
                Button { staged = "" } label: {
                    HStack {
                        Text("None").foregroundStyle(.secondary)
                        Spacer()
                        if staged.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)

                if showUseNew {
                    Button { staged = trimmedQuery } label: {
                        Label("Use “\(trimmedQuery)”", systemImage: "plus.circle").foregroundStyle(.tint)
                    }
                }

                ForEach(filtered) { cp in
                    Button { staged = cp.name } label: {
                        HStack {
                            Text(cp.name).foregroundStyle(.primary)
                            Spacer()
                            if cp.name.caseInsensitiveCompare(staged) == .orderedSame {
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { merchant = staged; dismiss() }.bold()
                }
            }
        }
    }
}
