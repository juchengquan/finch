import SwiftUI
import FinchCore

/// Page 2's grid: a purchase split by card AND by category.
///
/// **Laid out as one section per card, not as a table.** A table needs a column
/// per category, and three cards by four categories does not fit a phone. Stacked
/// sections scroll, which is what a phone does well — and each section already
/// reads as what it becomes when saved: one transaction, on that card, divided
/// across categories.
///
/// **The cells are typed and the totals derive from them.** Two card amounts and
/// two category amounts do NOT determine the four cells — $60/$0/$10/$30 and
/// $42/$18/$28/$12 share the same margins — so the app has to ask rather than
/// guess, and guessing is wrong exactly when the pairing was deliberate.
///
/// One flat `SplitAllocation` keyed `"<accountId>|<categoryId>"` backs the whole
/// thing (Decision 11), reused unchanged: its pinned/floating model gives "type
/// the ones you know, the rest divide what is left" for free, and its early
/// return when everything is pinned IS the "unaccounted" state below.
struct PurchaseGridSection: View {
    @EnvironmentObject private var store: FinchStore
    @Binding var alloc: SplitAllocation
    let accountIds: [String]
    let categoryIds: [String?]
    let currency: String

    var body: some View {
        ForEach(accountIds, id: \.self) { accountId in
            Section {
                ForEach(Array(categoryIds.enumerated()), id: \.offset) { _, categoryId in
                    let key = PurchaseFlow.cellKey(account: accountId, category: categoryId)
                    if alloc.isTicked(key) {
                        HStack {
                            Text(categoryName(categoryId))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 2) {
                                Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                                TextField("0.00", text: amountBinding(key))
                                    .numericInput(amountBinding(key))
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                    .fixedSize()
                                    .accessibilityIdentifier("grid.cell.\(key)")
                            }
                            // Crossing out is `untick`, NOT zero: an absent cell
                            // produces no category leg, where a zero one would show
                            // as a $0 category and pollute category counts.
                            Button {
                                alloc.untick(key)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(categoryName(categoryId)) from \(accountName(accountId))")
                        }
                    } else {
                        Button {
                            alloc.tick(key)
                        } label: {
                            Label(categoryName(categoryId), systemImage: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("grid.add.\(key)")
                    }
                }
                LabeledContent(accountName(accountId)) {
                    Text(verbatim: store.displayNative(rowTotal(accountId), currency: currency))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text(accountName(accountId))
            }
        }

        Section {
            LabeledContent("Allocated") {
                Text(verbatim: "\(store.displayNative(alloc.allocated, currency: currency)) / \(store.displayNative(alloc.total, currency: currency))")
            }
            .accessibilityIdentifier("grid.allocated")
            // Only reachable when every cell is pinned: `redistribute` gives the
            // unpinned ones whatever is left, so a single floating cell silently
            // absorbs the difference and this never appears.
            if !PurchaseFlow.isBalanced(alloc) {
                Text("\(store.displayNative(abs(PurchaseFlow.unallocated(alloc)), currency: currency)) unaccounted")
                    .font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("grid.unaccounted")
            }
        } footer: {
            Text("Each card becomes its own transaction, linked as one purchase.")
        }
    }

    private func rowTotal(_ accountId: String) -> Double {
        alloc.rows
            .filter { PurchaseFlow.splitCellKey($0.id).account == accountId }
            .reduce(0) { $0 + $1.amount }
    }
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
                guard let row = alloc.rows.first(where: { $0.id == key }), row.amount != 0 else { return "" }
                return String(format: "%.2f", abs(row.amount))
            },
            set: { text in
                if text.isEmpty { alloc.setAmount(key, nil) }
                else if let parsed = DecimalInput.parse(text) { alloc.setAmount(key, parsed) }
            })
    }
}
