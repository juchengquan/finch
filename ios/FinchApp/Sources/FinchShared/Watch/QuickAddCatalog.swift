import Foundation
import FinchCore

/// CP3 composer — builds the watch entry catalog (spec §1). Pure and testable;
/// lives in the app target (not Shared) because it consumes FinchCore row types.
enum QuickAddCatalogBuilder {
    /// Default account = the account most used by confirmed expenses since
    /// `since` (fallback: the ledger's first active account). Categories = the
    /// top ≤ 6 expense categories by confirmed-expense count since `since`
    /// (zero counts degrade naturally to the ledger's first 6 expense
    /// categories). Nil when the ledger has no active accounts.
    static func build(ledgerId: String, accounts: [AccountRow], txns: [Tx],
                      categories: [CategoryRow], since: String) -> WatchQuickAddCatalog? {
        let ledgerAccounts = accounts.filter { ($0.ledgerId ?? "personal") == ledgerId && ($0.isActive ?? true) }
        guard !ledgerAccounts.isEmpty else { return nil }

        var accountUse: [String: Int] = [:]
        var categoryUse: [String: Int] = [:]
        var seenForCategory = Set<String>()
        for t in txns {
            if (t.ledgerId ?? "personal") != ledgerId { continue }
            if (t.pending ?? false) { continue }
            // kindOf mirror (Selectors' helper is FinchCore-internal).
            let kind = t.kind ?? (t.transferGroupId != nil ? "transfer" : (t.amount > 0 ? "income" : "expense"))
            guard kind == "expense" else { continue }
            if t.date < since { continue }
            // accountUse counts PAYMENTS deliberately: a purchase paid on two cards
            // genuinely did use both, so each should count towards its own card's
            // ranking. categoryUse counts PURCHASES — the category belongs to the
            // entry, so both legs carry it and a split purchase would otherwise get
            // double weight in the shortcut ranking.
            accountUse[t.account, default: 0] += 1
            if let c = t.category, seenForCategory.insert("\(t.purchaseKey)|\(c)").inserted {
                categoryUse[c, default: 0] += 1
            }
        }

        // Highest use count wins; ties keep the projection's account order.
        let defaultAccount = ledgerAccounts.enumerated().min { a, b in
            let ca = accountUse[a.element.id] ?? 0, cb = accountUse[b.element.id] ?? 0
            return ca != cb ? ca > cb : a.offset < b.offset
        }!.element

        let expenseCats = categories.filter { $0.ledgerId == ledgerId && ($0.kind ?? "expense") == "expense" }
        let ranked = expenseCats.enumerated().sorted { a, b in
            let ca = categoryUse[a.element.id] ?? 0, cb = categoryUse[b.element.id] ?? 0
            return ca != cb ? ca > cb : a.offset < b.offset
        }
        .prefix(6)
        .map { WatchQuickAddCatalog.Item(id: $0.element.id, name: $0.element.name) }

        return WatchQuickAddCatalog(ledgerId: ledgerId,
                                    accountId: defaultAccount.id,
                                    accountName: defaultAccount.name ?? "Account",
                                    categories: ranked)
    }

    /// "YYYY-MM-DD" for `days` before now — the builder's `since` cutoff.
    static func sinceDate(daysBack days: Int, from now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now.addingTimeInterval(-Double(days) * 86_400))
    }
}
