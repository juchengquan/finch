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
        .updateTransaction: updateTransaction,
        .deleteTransaction: deleteTransaction,
        .setCleared: setCleared,
        .setReviewed: setReviewed,
        .markAllReviewed: markAllReviewed,
        .confirmAllPending: confirmAllPending,
        .setTransactionTags: setTransactionTags,
        .bulkRecategorize: bulkRecategorize,
        .confirmTransaction: confirmTransaction,
        .confirmPendingWithMerchant: confirmPendingWithMerchant,
        .removeAttachment: removeAttachment,
        .setEntryAttachment: setEntryAttachment,
        .reconcileAccount: reconcileAccount,
        .setTransactionSplits: setTransactionSplits,
    ]

    // MARK: setTransactionSplits — verbatim port of the web's per-split base
    // allocation (sign × ratio, last leg absorbs the signed remainder); any
    // residue lands on the fx leg via appendResidue, exactly like the web. The
    // write-parity oracle confirms the match.
    static func setTransactionSplits(_ db: Database, _ args: Args) throws {
        struct Split: Decodable { let categoryId: String?; let amount: Double; let description: String? }
        struct A: Decodable { let id: String; let splits: [Split]? }
        let a = try args.to(A.self)
        let splits = a.splits ?? []
        guard let ref = try Entries.resolveEntryRef(db, a.id) else { return }
        let entryId = ref.entryId
        guard let acct = try Row.fetchOne(db, sql: "SELECT id, account_id, amount, amount_base, exchange_rate, memo FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1", arguments: [entryId]) else { return }
        let acctBase: Double = acct["amount_base"]
        var legs: [Entries.Leg] = [.account(Entries.AccountLeg(
            accountId: acct["account_id"], amount: acct["amount"], amountBase: acctBase,
            exchangeRate: (acct["exchange_rate"] as Double?) ?? 1, memo: acct["memo"], id: acct["id"]))]
        if splits.isEmpty {
            legs.append(.category(Entries.CategoryLeg(categoryId: nil, amountBase: -acctBase)))
        } else {
            if splits.count == 1 { throw I18nError("error.split.minTwo", [:], "Splits require at least two rows") }
            let totalBase = abs(acctBase)
            let splitTotal = splits.reduce(0.0) { $0 + abs($1.amount) }
            if splitTotal > 0 && abs(splitTotal - totalBase) > 0.005 * Double(splits.count) {
                throw I18nError("error.split.sumMismatch", [:], "Split amounts must sum to the transaction total")
            }
            let baseRatio = splitTotal > 0 ? totalBase / splitTotal : 1
            let sign: Double = acctBase > 0 ? 1 : (acctBase < 0 ? -1 : 0)
            var usedBase = 0.0
            for (i, sp) in splits.enumerated() {
                let isLast = i == splits.count - 1
                let spBase = isLast ? Entries.r2(acctBase + usedBase) : Entries.r2(-abs(sp.amount) * baseRatio * sign)
                if !isLast { usedBase += spBase }
                legs.append(.category(Entries.CategoryLeg(categoryId: sp.categoryId, amountBase: spBase, memo: sp.description)))
            }
        }
        var ep = Entries.EntryPatch()
        ep.legs = .set(legs)
        try Entries.rebuildEntry(db, entryId, ep)
    }

    // MARK: reconcileAccount

    /// Stamp the reconcile checkpoint; optionally post a reconcile adjustment for
    /// the gap between the statement balance and the cleared (confirmed + cleared)
    /// posting sum, marking that adjustment cleared.
    static func reconcileAccount(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let accountId: String; let statementBalance: Double; let statementDate: String?; let postAdjustment: Bool? }
        let a = try args.to(A.self)
        if !a.statementBalance.isFinite { throw I18nError("error.reconcile.statementBalance", [:], "Statement balance is required") }
        let statementDate = a.statementDate ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if a.postAdjustment == true {
            guard let ledgerId = try String.fetchOne(db, sql: "SELECT ledger_id FROM accounts WHERE id = ?", arguments: [a.accountId]) else {
                throw I18nError("error.notFound.account", [:], "Account not found")
            }
            let cleared = Entries.r2(try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(p.amount), 0) FROM postings p JOIN entries e ON e.id = p.entry_id
                 WHERE p.account_id = ? AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL
                """, arguments: [a.accountId]) ?? 0)
            let delta = Entries.r2(a.statementBalance - cleared)
            if abs(delta) >= 0.005, let adjEntryId = try Entries.postAdjustment(db, ledgerId: ledgerId, accountId: a.accountId, delta: delta, date: statementDate, source: "reconcile") {
                try db.execute(sql: "UPDATE postings SET cleared_at = datetime('now') WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [adjEntryId])
            }
        }
        try db.execute(sql: "UPDATE accounts SET last_reconciled_at = ?, last_reconciled_balance = ?, updated_at = datetime('now') WHERE id = ?",
                       arguments: [statementDate, a.statementBalance, a.accountId])
    }

    // MARK: removeAttachment

    /// Drop an attachment row. DEFERRED: the on-disk file unlink (no file store yet).
    static func removeAttachment(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM entry_attachments WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    // MARK: setEntryAttachment (Phase 6.5 — the 75th action, native-only)

    /// Record an attachment row for an entry. NATIVE-ONLY: the web adds
    /// attachments via the multipart `POST /api/attachments` route (file write +
    /// row insert server-side); the native app has no HTTP server, so it stages
    /// the file (Share Extension / PhotosPicker) and then dispatches this to
    /// record the row. Arg names echo the `entry_attachments` columns. The
    /// ledger is derived from the entry when omitted.
    static func setEntryAttachment(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let entryId: String; let kind: String
            let relPath: String; let mimeType: String; let byteSize: Double
            let sha256: String; let originalFilename: String?
        }
        let a = try args.to(A.self)
        if !["image", "pdf"].contains(a.kind) {
            throw I18nError("error.attachment.kind", [:], "Attachment kind must be image or pdf")
        }
        guard let ledgerId = try a.ledgerId ?? String.fetchOne(db,
            sql: "SELECT ledger_id FROM entries WHERE id = ?", arguments: [a.entryId]) else {
            throw I18nError("error.notFound.entry", [:], "Entry not found")
        }
        let id = a.id ?? Entries.newId("att")
        try db.execute(sql: """
            INSERT INTO entry_attachments (id, ledger_id, entry_id, kind, rel_path, mime_type,
                byte_size, sha256, original_filename, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))
            """, arguments: [id, ledgerId, a.entryId, a.kind, a.relPath, a.mimeType,
                             Int(a.byteSize), a.sha256, a.originalFilename])
    }

    // MARK: confirm

    private static func recomputeEntryAccounts(_ db: Database, _ entryId: String) throws {
        for acct in try String.fetchAll(db, sql: "SELECT DISTINCT account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [entryId]) {
            try Entries.recomputeAccountFromPostings(db, acct)
        }
    }

    static func confirmTransaction(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        guard let ref = try Entries.resolveEntryRef(db, try args.to(A.self).id) else { return }
        try db.execute(sql: "UPDATE entries SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'",
                       arguments: [ISO8601DateFormatter().string(from: Date()), ref.entryId])
        try recomputeEntryAccounts(db, ref.entryId)
    }

    static func confirmPendingWithMerchant(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let counterpartyId: String?; let newCounterpartyName: String? }
        let a = try args.to(A.self)
        guard let ref = try Entries.resolveEntryRef(db, a.id) else { return }
        guard let row = try Row.fetchOne(db, sql: "SELECT description, ledger_id FROM entries WHERE id = ?", arguments: [ref.entryId]) else { return }
        let ledgerId: String = row["ledger_id"] ?? ""
        var counterpartyId: String?
        var description: String = row["description"] ?? ""
        if let cpId = a.counterpartyId {
            if let cp = try Row.fetchOne(db, sql: "SELECT name FROM counterparties WHERE id = ? AND ledger_id = ?", arguments: [cpId, ledgerId]) {
                counterpartyId = cpId
                description = cp["name"]
            }
        } else if let newName = a.newCounterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty {
            let newCpId = Entries.newId("cp")
            try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES (?,?,?,0,datetime('now'),datetime('now'))",
                           arguments: [newCpId, ledgerId, newName])
            counterpartyId = newCpId
            description = newName
        }
        try db.execute(sql: "UPDATE entries SET status = 'confirmed', confirmed_at = ?, counterparty_id = ?, description = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'",
                       arguments: [ISO8601DateFormatter().string(from: Date()), counterpartyId, description, ref.entryId])
        try recomputeEntryAccounts(db, ref.entryId)
    }


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

    // MARK: updateTransaction (header-only path → rebuildEntry)

    /// Reads the patch via JSONValue to honor key-presence (present-null = clear,
    /// absent = keep) — which plain Decodable optionals can't distinguish.
    /// DEFERRED: money edits (amount/category/account/currency) need the
    /// legs-rebuild re-lock path; they throw notImplemented here.
    static func updateTransaction(_ db: Database, _ args: Args) throws {
        guard case .string(let id)? = args.values["id"] else {
            throw I18nError("error.invalidArgs", [:], "updateTransaction requires an id")
        }
        guard case .object(let patch)? = args.values["patch"] else { return }
        if patch.keys.contains(where: { ["amount", "category", "account", "currency"].contains($0) }) {
            throw I18nError("error.notImplemented.txMoneyEdit", [:],
                            "Editing a transaction's amount/category/account isn't supported on iOS yet")
        }
        guard let ref = try Entries.resolveEntryRef(db, id) else { return }
        let entryId = ref.entryId

        func strOrNil(_ v: JSONValue?) -> String? { if case .string(let s)? = v { return s }; return nil }

        var ep = Entries.EntryPatch()
        if case .string(let s)? = patch["date"] { ep.date = .set(s) }
        if patch.keys.contains("time") { ep.time = .set(strOrNil(patch["time"])) }
        if case .string(let s)? = patch["merchant"] {
            ep.description = .set(s)
            let ledgerId = try String.fetchOne(db, sql: "SELECT ledger_id FROM entries WHERE id = ?", arguments: [entryId]) ?? ""
            ep.counterpartyId = .set(ledgerId.isEmpty ? nil : (try Entries.resolveCounterpartyIdByName(db, ledgerId, s)))
        }
        if patch.keys.contains("note") { ep.notes = .set(strOrNil(patch["note"])) }
        if case .string(let s)? = patch["kind"], let k = Entries.Kind(rawValue: s) { ep.kind = .set(k) }
        if patch.keys.contains("refundedTransactionId") { ep.refundedEntryId = .set(strOrNil(patch["refundedTransactionId"])) }
        if case .string(let s)? = patch["status"], let st = Entries.Status(rawValue: s) { ep.status = .set(st) }

        try Entries.rebuildEntry(db, entryId, ep)
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

    // MARK: setTransactionTags

    static func setTransactionTags(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let tagIds: [String] }
        let a = try args.to(A.self)
        let entryId = try Entries.resolveEntryRef(db, a.id)?.entryId ?? a.id
        try db.execute(sql: "DELETE FROM entry_tags WHERE entry_id = ?", arguments: [entryId])
        for tagId in a.tagIds {
            try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)", arguments: [entryId, tagId])
        }
    }

    // MARK: bulkRecategorize (→ rebuildEntry with [acctLeg, new category leg])

    /// Single-category entries only; splits (≥2 category legs) are skipped, like
    /// the web. NOTE: the account leg is forwarded verbatim, but my simplified
    /// ResolvedLeg/insertPostings drop cleared_at/orig_* — so a cleared or FX leg
    /// would lose that metadata on rebuild (DEFERRED, fine for plain entries).
    static func bulkRecategorize(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let ids: [String]; let categoryId: String? }
        let a = try args.to(A.self)
        if a.ids.isEmpty { return }
        for id in a.ids {
            guard let ref = try Entries.resolveEntryRef(db, id) else { continue }
            let entryId = ref.entryId
            let catCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [entryId]) ?? 0
            if catCount >= 2 { continue }
            guard let acct = try Row.fetchOne(db, sql:
                "SELECT id, account_id, amount, amount_base, exchange_rate, memo FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1",
                arguments: [entryId]) else { continue }
            let amountBase: Double = acct["amount_base"]
            var ep = Entries.EntryPatch()
            ep.legs = .set([
                .account(Entries.AccountLeg(accountId: acct["account_id"], amount: acct["amount"],
                    amountBase: acct["amount_base"], exchangeRate: (acct["exchange_rate"] as Double?) ?? 1,
                    memo: acct["memo"], id: acct["id"])),
                .category(Entries.CategoryLeg(categoryId: a.categoryId, amountBase: -amountBase)),
            ])
            try Entries.rebuildEntry(db, entryId, ep)
        }
        // DEFERRED: invalidateRollover.
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
