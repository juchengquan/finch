import Foundation
import GRDB

// Transactions domain handlers — port of lib/db/domain/transactions/mutations.ts.
// First batch: the actions that build on the posting engine + simple SQL.
// DEFERRED (need rebuildEntry/deleteEntry/postAdjustment or sub-queries):
// updateTransaction, setTransactionSplits, deleteTransaction, adjustAccountBalance,
// reconcileAccount, bulkRecategorize, removeAttachment, confirmTransaction,
// confirmPendingWithMerchant, setTransactionTags. Budget-rollover invalidation
// (invalidateRollover) and the dedup-message wrapping are also deferred.
public enum Transactions {

    /// The handlers this domain currently contributes to the chokepoint registry.
    public static let handlers: [ActionName: Apply.Handler] = [
        .addTransaction: addTransaction,
        .adjustAccountBalance: adjustAccountBalance,
        .deleteTransaction: deleteTransaction,
        .setCleared: setCleared,
        .setReviewed: setReviewed,
        .markAllReviewed: markAllReviewed,
        .confirmAllPending: confirmAllPending,
    ]

    // MARK: addTransaction (same-currency path → postSimple)

    struct AddInput: Decodable {
        let ledgerId: String
        let accountId: String
        let amount: Double
        let amountBase: Double?
        let currency: String?
        let merchant: String
        let categoryId: String?
        let date: String
        let time: String?
        let note: String?
        let status: String?
        let kind: String?
        let refundedTransactionId: String?
        let counterpartyId: String?
        let skipRules: Bool?
    }

    static func addTransaction(_ db: Database, _ args: Args) throws {
        let a = try args.to(AddInput.self)
        // Cross-ledger counterparty guard: drop a counterparty from another ledger.
        var counterpartyId = a.counterpartyId
        if let cp = counterpartyId {
            let cpLedger = try String.fetchOne(db, sql: "SELECT ledger_id FROM counterparties WHERE id = ?", arguments: [cp])
            if cpLedger != a.ledgerId { counterpartyId = nil }
        }
        let kind = a.kind.flatMap(Entries.Kind.init(rawValue:)) ?? (a.amount > 0 ? Entries.Kind.income : .expense)

        let acctCcy = try String.fetchOne(db, sql: "SELECT currency FROM accounts WHERE id = ?", arguments: [a.accountId]) ?? "USD"
        let inputCcy = a.currency ?? acctCcy
        if inputCcy != acctCcy {
            // DEFERRED: the foreign-currency path (orig_* fields + double conversion).
            throw I18nError("error.notImplemented.foreignCurrency", [:], "Foreign-currency entries are not supported on iOS yet")
        }

        try Entries.postSimple(db, .init(
            ledgerId: a.ledgerId, accountId: a.accountId, amount: a.amount, date: a.date,
            description: a.merchant, categoryId: a.categoryId, kind: kind, time: a.time,
            notes: (a.note?.isEmpty ?? true) ? nil : a.note,
            status: a.status.flatMap(Entries.Status.init(rawValue:)),
            counterpartyId: counterpartyId, skipRules: a.skipRules ?? false))
    }

    // MARK: adjustAccountBalance (→ postAdjustment)

    struct AdjustArgs: Decodable { let accountId: String; let targetBalance: Double; let date: String?; let note: String?; let source: String? }
    static func adjustAccountBalance(_ db: Database, _ args: Args) throws {
        let a = try args.to(AdjustArgs.self)
        guard a.targetBalance.isFinite else { throw I18nError("error.adjust.targetRequired", [:], "Enter a target balance") }
        guard let acct = try Row.fetchOne(db, sql: "SELECT ledger_id, current_balance FROM accounts WHERE id = ?", arguments: [a.accountId]) else {
            throw I18nError("error.notFound.account", [:], "Account not found")
        }
        let ledgerId: String = acct["ledger_id"]
        let current: Double = acct["current_balance"]
        let delta = Entries.r2(a.targetBalance - current)
        let date = a.date ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        try Entries.postAdjustment(db, ledgerId: ledgerId, accountId: a.accountId, delta: delta,
                                   date: date, note: a.note, source: a.source == "reconcile" ? "reconcile" : "manual")
    }

    // MARK: deleteTransaction (→ resolveEntryRef + deleteEntry)

    struct IdArg: Decodable { let id: String }
    static func deleteTransaction(_ db: Database, _ args: Args) throws {
        let a = try args.to(IdArg.self)
        guard let ref = try Entries.resolveEntryRef(db, a.id) else { return }
        try Entries.deleteEntry(db, ref.entryId)
        // DEFERRED: attachment-file cleanup + budget-rollover invalidation.
    }

    // MARK: setCleared / setReviewed / markAllReviewed

    struct IdCleared: Decodable { let id: String; let cleared: Bool }
    static func setCleared(_ db: Database, _ args: Args) throws {
        let a = try args.to(IdCleared.self)
        let postingId = try Entries.resolveEntryRef(db, a.id)?.postingId ?? a.id
        try db.execute(sql: a.cleared
            ? "UPDATE postings SET cleared_at = datetime('now') WHERE id = ?"
            : "UPDATE postings SET cleared_at = NULL WHERE id = ?", arguments: [postingId])
    }

    struct IdReviewed: Decodable { let id: String; let reviewed: Bool }
    static func setReviewed(_ db: Database, _ args: Args) throws {
        let a = try args.to(IdReviewed.self)
        let entryId = try Entries.resolveEntryRef(db, a.id)?.entryId ?? a.id
        try db.execute(sql: a.reviewed
            ? "UPDATE entries SET reviewed_at = datetime('now') WHERE id = ?"
            : "UPDATE entries SET reviewed_at = NULL WHERE id = ?", arguments: [entryId])
    }

    struct MarkAll: Decodable { let ledgerId: String?; let accountId: String? }
    static func markAllReviewed(_ db: Database, _ args: Args) throws {
        let a = try args.to(MarkAll.self)
        let ledgerId = a.ledgerId ?? "personal"
        if let accountId = a.accountId {
            try db.execute(sql: """
                UPDATE entries SET reviewed_at = datetime('now')
                 WHERE ledger_id = ? AND reviewed_at IS NULL
                   AND EXISTS (SELECT 1 FROM postings p WHERE p.entry_id = entries.id AND p.account_id = ?)
                """, arguments: [ledgerId, accountId])
        } else {
            try db.execute(sql: "UPDATE entries SET reviewed_at = datetime('now') WHERE ledger_id = ? AND reviewed_at IS NULL",
                           arguments: [ledgerId])
        }
    }

    // MARK: confirmAllPending

    static func confirmAllPending(_ db: Database, _ args: Args) throws {
        let accts = try String.fetchAll(db, sql: """
            SELECT DISTINCT p.account_id FROM postings p JOIN entries e ON e.id = p.entry_id
             WHERE e.status = 'pending' AND p.account_id IS NOT NULL
            """)
        try db.execute(sql: "UPDATE entries SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE status = 'pending'",
                       arguments: [ISO8601DateFormatter().string(from: Date())])
        // Pending postings weren't in the cached balance (the trigger only fires
        // on confirmed inserts) — recompute each touched account.
        for acct in accts { try Entries.recomputeAccountFromPostings(db, acct) }
    }
}
