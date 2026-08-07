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

    /// Which axis a split divides. Page 2 lays a one-axis split out as a flat
    /// list; three cards against a single category would otherwise render as
    /// three sections of one row each, which reads as a grid that is not one.
    enum SplitAxis: Equatable { case none, accounts, categories, both }

    static func splitAxis(accounts: Int, categories: Int) -> SplitAxis {
        switch (accounts > 1, categories > 1) {
        case (true, true):   return .both
        case (true, false):  return .accounts
        case (false, true):  return .categories
        case (false, false): return .none
        }
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

    // MARK: - Seeding page 2

    /// Page 2's starting point: every cell filled from both margins,
    /// `cell(card, category) = card's share × category's share ÷ total`.
    ///
    /// **This does not contradict the reason the grid exists.** Two sets of
    /// margins genuinely do NOT determine the cells — 60/0/10/30 and
    /// 42/18/28/12 share the same margins — which is why every cell here stays
    /// editable and any of them can be crossed out. What the margins DO give is
    /// a starting point that is balanced on arrival, so ✓ is live immediately
    /// and the numbers already typed on page 1 are honoured rather than thrown
    /// away. Opening empty would demand four more entries for a 2×2 and twelve
    /// for a 3×4.
    static func seedGrid(accounts: [(id: String?, amount: Double)],
                         categories: [(id: String?, amount: Double)],
                         total: Double) -> SplitAllocation {
        var out = SplitAllocation(total: total)
        guard total > 0, !accounts.isEmpty, !categories.isEmpty else { return out }

        var cells: [(key: String, amount: Double)] = []
        for a in accounts {
            for c in categories {
                cells.append((cellKey(account: a.id ?? "", category: c.id),
                              SplitAllocation.round2(a.amount * c.amount / total)))
            }
        }
        // N independent roundings will not generally sum to the total, so the
        // last cell absorbs the residue — the same trick `redistribute` uses on
        // its final floating row, and the engine on its final leg.
        if let last = cells.indices.last {
            let others = cells.dropLast().reduce(0) { $0 + $1.amount }
            cells[last].amount = SplitAllocation.round2(total - others)
        }
        for cell in cells {
            out.tick(cell.key)
            out.setAmount(cell.key, cell.amount)
        }
        return out
    }

    /// Coming back to page 2 after changing the selection on page 1.
    ///
    /// Cells that survive keep exactly what the user typed. Cells that are new
    /// arrive UNPINNED, so `redistribute` hands them whatever is left instead of
    /// them fighting the figures already set. Cells whose card or category left
    /// the selection simply are not rebuilt.
    static func reseedGrid(_ current: SplitAllocation,
                           accounts: [(id: String?, amount: Double)],
                           categories: [(id: String?, amount: Double)],
                           total: Double) -> SplitAllocation {
        guard !current.rows.isEmpty else {
            return seedGrid(accounts: accounts, categories: categories, total: total)
        }
        var out = SplitAllocation(total: total)
        for a in accounts {
            for c in categories {
                let key = cellKey(account: a.id ?? "", category: c.id)
                out.tick(key)                                   // unpinned — floats
                if let prior = current.rows.first(where: { $0.id == key }) {
                    out.setAmount(key, prior.amount)            // typed before — hold it
                }
            }
        }
        return out
    }

    // MARK: - Reopening a saved grid

    /// Everything page 1 and page 2 need to reopen a saved grid.
    struct GridSeed {
        var alloc: SplitAllocation
        var accountIds: [String]
        var categoryIds: [String?]
        /// The currency the purchase was ENTERED in, when that was not the
        /// ledger base. `nil` means it was.
        var currency: String?
    }

    /// Rebuild the grid a saved group came from.
    ///
    /// A grid purchase is several transactions linked by `groupId` — one per
    /// card, each carrying its own category legs — so reopening means turning
    /// them back into one flat cell allocation.
    ///
    /// **Amounts come back in the PURCHASE's currency**, from the per-cell
    /// `origAmount` the engine records. Falling back to the base figures would
    /// reopen a foreign purchase showing back-converted amounts, which drift by
    /// a cent on awkward rates — and re-saving would bake the drift in as the
    /// new truth.
    ///
    /// Rows arrive PINNED: they are figures the user set before and must not be
    /// re-divided just by opening the sheet.
    static func seedGrid(from rows: [Tx]) -> GridSeed {
        var accountIds: [String] = []
        var categoryIds: [String?] = []
        var cells: [(key: String, amount: Double)] = []
        var currency: String?

        for row in rows {
            if !accountIds.contains(row.account) { accountIds.append(row.account) }
            for leg in categoryLegs(of: row) {
                if !categoryIds.contains(where: { $0 == leg.categoryId }) {
                    categoryIds.append(leg.categoryId)
                }
                cells.append((cellKey(account: row.account, category: leg.categoryId),
                              abs(leg.amount)))
                if currency == nil { currency = leg.currency }
            }
        }

        var alloc = SplitAllocation(total: SplitAllocation.round2(cells.reduce(0) { $0 + $1.amount }))
        for cell in cells {
            alloc.tick(cell.key)
            alloc.setAmount(cell.key, cell.amount)
        }
        return GridSeed(alloc: alloc, accountIds: accountIds,
                        categoryIds: categoryIds, currency: currency)
    }

    /// One card's category legs. A card with several categories carries them in
    /// `splits`; a card with exactly one has no `splits` array at all, because
    /// the projection puts that category on the row itself.
    private static func categoryLegs(of row: Tx) -> [(categoryId: String?, amount: Double, currency: String?)] {
        if let splits = row.splits, !splits.isEmpty {
            return splits.map { ($0.categoryId, $0.origAmount ?? $0.amountBase, $0.origCurrency) }
        }
        return [(row.category, row.nativeAmount ?? row.amount, row.currency)]
    }
}

/// The kinds the Add sheet offers. Mirrors the sheet's own `Kind` so the pure
/// helpers above do not depend on a view type.
enum AddTxKind: String, Equatable {
    case expense, income, transfer, refund
}
