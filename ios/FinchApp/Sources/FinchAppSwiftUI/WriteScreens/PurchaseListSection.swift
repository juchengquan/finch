import SwiftUI
import FinchCore

/// Page 2 for a ONE-axis split: divide a total across N things.
///
/// A flat section, not `PurchaseGridSection`. That renders one section per card
/// with a row per category, which is right for a grid and wrong here: three
/// cards against a single category would become three sections of one row each,
/// reading as a grid that is not one.
///
/// The cells are the same `SplitAllocation` either way — keyed
/// `"<account>|<category>"` — so the payload the sheet builds does not care
/// which of the two rendered it.
struct PurchaseListSection: View {
    @EnvironmentObject private var store: FinchStore
    @Binding var alloc: SplitAllocation
    /// One of these has a single member; the other is what is being divided.
    let accountIds: [String]
    let categoryIds: [String?]
    let currency: String

    var body: some View {
        Section {
            ForEach(rows, id: \.key) { row in
                HStack {
                    Text(row.label).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 2) {
                        Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                        TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: currency)),
                                  text: amountBinding(row.key))
                            .moneyInput(amountBinding(row.key), currency: currency)
                            .fixedSize()
                            .accessibilityIdentifier("split.amount.\(row.key)")
                    }
                }
            }
            LabeledContent("Allocated") {
                Text(verbatim: "\(store.displayNative(alloc.allocated, currency: currency)) / \(store.displayNative(alloc.total, currency: currency))")
            }
            .accessibilityIdentifier("split.allocated")
        }
    }

    private var rows: [(key: String, label: String)] {
        accountIds.flatMap { account in
            categoryIds.map { category in
                (PurchaseFlow.cellKey(account: account, category: category),
                 accountIds.count > 1 ? accountName(account) : categoryName(category))
            }
        }
    }

    // Resolved here from the store, exactly as `PurchaseGridSection` does — the
    // page does not need to know which kind of id it is holding.
    private func accountName(_ id: String) -> String {
        store.accounts.first { $0.id == id }?.name ?? id
    }
    private func categoryName(_ id: String?) -> String {
        guard let id else { return String(localized: "Uncategorized") }
        return store.categoryName(id) ?? String(localized: "Uncategorized")
    }

    private func amountBinding(_ key: String) -> Binding<String> {
        Binding(
            get: {
                guard let row = alloc.rows.first(where: { $0.id == key }) else { return "" }
                return row.amount == 0 ? "" : DecimalInput.text(row.amount, currency: currency)
            },
            set: { alloc.setAmount(key, DecimalInput.parse($0)) })
    }
}
