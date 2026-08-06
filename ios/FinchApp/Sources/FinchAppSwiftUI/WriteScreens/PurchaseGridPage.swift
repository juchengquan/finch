import SwiftUI
import FinchCore

/// Page 2 of the entry flow: divide the money.
///
/// Page 1 asks WHICH cards and WHICH categories; this asks how much of each.
///
/// **A pushed page, not more sections on page 1.** A 3×4 grid is twelve fields
/// and three headers; sitting below the date, note, tags and receipt rows it was
/// effectively invisible — the grid shipped working and went unnoticed.
///
/// **✓ lives here**, because this is where the numbers that get saved are, and
/// it is disabled until they add up. The footer already said "N unaccounted"
/// while letting the save through.
struct PurchaseGridPage: View {
    @EnvironmentObject private var store: FinchStore
    @Binding var alloc: SplitAllocation
    let accountIds: [String]
    let categoryIds: [String?]
    let currency: String
    let onSave: () -> Void

    var body: some View {
        Form {
            PurchaseGridSection(alloc: $alloc, accountIds: accountIds,
                                categoryIds: categoryIds, currency: currency)
        }
        .finchSheetForm()
        // The purchase total, which is the only context this page needs. Rendered
        // verbatim so it is not extracted as a localisable string — it is a
        // number, already formatted for the locale by `displayNative`.
        .navigationTitle(Text(verbatim: store.displayNative(alloc.total, currency: currency)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSave) { Image(systemName: "checkmark") }
                    .accessibilityLabel("Save")
                    .confirmCheckmarkStyle()
                    .disabled(!PurchaseFlow.isBalanced(alloc))
                    .accessibilityIdentifier("grid.save")
            }
        }
    }
}
