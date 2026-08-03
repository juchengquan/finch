import Foundation
import FinchCore

/// The two-page entry flow's pure decisions, kept out of the sheet so they can be
/// tested without a view.
///
/// Page 1 asks *which* cards and *which* categories; page 2 divides the money.
/// Whether page 2 is needed — and whether it is a list or a grid — follows from
/// the selection alone.
enum PurchaseFlow {

    /// What page 2 shows, if anything.
    enum Page2: Equatable {
        /// One card, one category: nothing to divide, so ✓ saves from page 1.
        case notNeeded
        /// One axis split — divide a total across N things, the shape the existing
        /// split list already handles.
        case list
        /// Both axes split. The cells are typed and the totals derive from them:
        /// two card amounts and two category amounts do NOT determine the four
        /// cells (60/0/10/30 and 42/18/28/12 share the same margins), so the app
        /// must ask rather than guess — and guessing is wrong exactly when the
        /// pairing was deliberate.
        case grid
    }

    static func page2(accounts: Int, categories: Int) -> Page2 {
        if accounts > 1 && categories > 1 { return .grid }
        if accounts > 1 || categories > 1 { return .list }
        return .notNeeded
    }

    /// The key one cell of the grid is allocated under. `SplitAllocation` is reused
    /// UNCHANGED for the grid — one flat allocation over the cells rather than a
    /// two-dimensional widget or one instance per card — and `Row.id` is a plain
    /// `String`, so a composite key needs no change to the type.
    static func cellKey(account: String, category: String?) -> String {
        "\(account)|\(category ?? "")"
    }

    static func splitCellKey(_ key: String) -> (account: String, category: String?) {
        guard let i = key.firstIndex(of: "|") else { return (key, nil) }
        let account = String(key[key.startIndex..<i])
        let category = String(key[key.index(after: i)...])
        return (account, category.isEmpty ? nil : category)
    }

    /// Turn the allocation into `saveTransaction`'s `cells`.
    ///
    /// **Signed by the caller.** The predecessor plan shipped a version where every
    /// expense split was rejected because the shares were unsigned, and 407 green
    /// tests missed it — all of them exercised the allocation model, which was
    /// already correct. So this is where the sign is applied, and where the test
    /// belongs.
    ///
    /// A cell the user crossed out is absent from the allocation entirely, and an
    /// absent cell produces no category leg — not a zero-amount one, which would
    /// show as a $0 category on that transaction and pollute category counts.
    static func cells(from alloc: SplitAllocation, kind: AddTxKind) -> [JSONValue] {
        let sign: Double = (kind == .income || kind == .refund) ? 1 : -1
        return alloc.rows.map { row in
            let parts = splitCellKey(row.id)
            var o: [String: JSONValue] = [
                "accountId": .string(parts.account),
                "amount": .double(sign * abs(row.amount)),
            ]
            o["categoryId"] = parts.category.map(JSONValue.string) ?? .null
            return .object(o)
        }
    }

    /// Saving is refused while the cells do not reach the purchase amount.
    ///
    /// Only reachable when EVERY cell is pinned: `redistribute` gives the unpinned
    /// ones whatever is left, so a single floating cell silently absorbs the
    /// difference and this never fires. That is the behaviour, not a bug — but it
    /// means a test asserting the block must pin everything.
    static func unallocated(_ alloc: SplitAllocation) -> Double {
        alloc.total - alloc.allocated
    }
    static func isBalanced(_ alloc: SplitAllocation) -> Bool {
        abs(unallocated(alloc)) < 0.005
    }
}

/// The kinds the Add sheet offers. Mirrors the sheet's own `Kind` so the pure
/// helpers above do not depend on a view type.
enum AddTxKind: String, Equatable {
    case expense, income, transfer, refund
}
