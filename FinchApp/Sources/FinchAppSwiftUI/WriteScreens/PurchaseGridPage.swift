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
            if axis == .both {
                PurchaseGridSection(alloc: $alloc, accountIds: accountIds,
                                    categoryIds: categoryIds, currency: currency)
            } else {
                PurchaseListSection(alloc: $alloc, accountIds: accountIds,
                                    categoryIds: categoryIds, currency: currency)
            }
            if let problem = alloc.problem {
                // The reason ✓ is blocked, in the words the pickers used before
                // this page took the job over — already written, already
                // translated. Do not invent a new one.
                Section { Text(Self.message(for: problem, axis: axis)).font(.footnote).foregroundStyle(.red) }
            }
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
                    .disabled(alloc.problem != nil)
                    .accessibilityIdentifier("grid.save")
            }
        }
    }

    private var axis: PurchaseFlow.SplitAxis {
        PurchaseFlow.splitAxis(accounts: accountIds.count, categories: categoryIds.count)
    }

    /// Both `needsTwo` wordings already exist in the catalog, one per axis —
    /// picking blind would tell someone splitting by category to give two
    /// ACCOUNTS an amount. A grid takes the category wording: `needsTwo` there
    /// means fewer than two funded cells, and the cells are the categories.
    private static func message(for problem: SplitAllocation.Problem,
                                axis: PurchaseFlow.SplitAxis) -> LocalizedStringKey {
        switch problem {
        case .needsAmount: return "Enter an amount to split."
        case .needsTwo:
            return axis == .accounts ? "Give at least two accounts an amount."
                                     : "Give at least two categories an amount."
        case .sumMismatch: return "Splits must add up to the transaction total."
        }
    }
}
