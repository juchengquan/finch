import Foundation
import GRDB

/// One command carrying a whole purchase.
///
/// **Why this exists.** Saving a transaction is one intent, but the sheets send
/// three to five commands to do it — so the screen owns the ordering and the
/// dependencies, every new screen must re-learn them, and a part-way failure
/// leaves the ledger half-updated. That has already shipped as a bug.
///
/// The screen states what the user wants; this decides the mechanics, in one
/// write. No `id` creates; an `id` replaces that transaction's contents wholesale,
/// so Add and Edit send the same shape and cannot drift apart.
///
/// **The ledger is atomic; files are best-effort.** Receipts do NOT ride along:
/// both attachment writes are detached, error-swallowing `Task { try? await … }`
/// (`AddTransactionSheet.swift:696-701`), and rolling the database back would not
/// unwrite a file. The next reader will assume otherwise, so it is said here.
///
/// **Not the same as `addTransaction`.** That one takes amounts in each card's
/// own currency and writes a single transaction; it stays, for the ten
/// programmatic callers and the cross-stack parity sequence.
enum SaveTransaction {

    static let handlers: [ActionName: Apply.Handler] = [
        .saveTransaction: { db, args in _ = try run(db, args) },
    ]

    /// One cell of the purchase: what a card paid towards a category. A single
    /// card and category is one cell; a split is several.
    struct Cell: Decodable {
        let accountId: String
        let categoryId: String?
        /// In the PURCHASE's currency (Decision 16), not the card's — so a grid's
        /// columns add up even when the cards hold different currencies. Converted
        /// to each card's own currency on the way in, because that is what reaches
        /// that card's statement.
        let amount: Double
    }

    struct Input: Decodable {
        let id: String?                 // absent = create
        let ledgerId: String
        let date: String
        let time: String?
        let merchant: String
        let note: String?
        let status: String?
        let kind: String?
        let currency: String?           // the purchase's currency; defaults to ledger base
        let cells: [Cell]
        let tagIds: [String]?
        let refundedTransactionId: String?
        // Create-path only — `EntryPatch` reaches none of these.
        let sourceTemplateId: String?
        let occurrenceDate: String?
        let groupId: String?
        let allowDuplicate: Bool?
        let skipRules: Bool?
    }

    @discardableResult
    static func run(_ db: Database, _ args: Args) throws -> String {
        // Dedup.wrap turns a raw SQLite "UNIQUE constraint failed" into the
        // friendly duplicate message; without it a double-tap surfaces SQL.
        try Dedup.wrap {
            let a = try args.to(Input.self)
            if a.cells.isEmpty {
                throw I18nError("error.split.minTwo", [:], "A purchase needs at least one payment")
            }
            let base = try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id = ?",
                                           arguments: [a.ledgerId]) ?? "USD"
            let purchaseCcy = a.currency ?? base
            let kind = a.kind.flatMap(Entries.Kind.init(rawValue:))
                ?? (a.cells.reduce(0) { $0 + $1.amount } > 0 ? Entries.Kind.income : .expense)

            // Same card twice in one payload is a mistake, not a two-payment
            // purchase: the amounts would silently merge and the user would never
            // learn which of the two they got.
            var byAccount: [(id: String, amount: Double)] = []
            for c in a.cells {
                if let i = byAccount.firstIndex(where: { $0.id == c.accountId }) {
                    byAccount[i].amount += c.amount
                } else {
                    byAccount.append((c.accountId, c.amount))
                }
            }
            if byAccount.contains(where: { Entries.r2($0.amount) == 0 }) {
                throw I18nError("error.split.zeroShare", [:], "Every payment needs an amount")
            }
            var byCategory: [(id: String?, amount: Double)] = []
            for c in a.cells {
                if let i = byCategory.firstIndex(where: { $0.id == c.categoryId }) {
                    byCategory[i].amount += c.amount
                } else {
                    byCategory.append((c.categoryId, c.amount))
                }
            }
            // One entry is split on at most ONE axis (Decision 27). Both axes at
            // once is the grid, which is one entry per card — Task 5's job.
            if byAccount.count > 1 && byCategory.count > 1 {
                throw I18nError("error.split.multiAccount", [:],
                                "A purchase paid from several accounts takes a single category")
            }

            // Resolve-or-create the merchant. `resolveCounterpartyIdByName` only
            // LOOKS UP, which is why the sheets call `createCounterparty` first —
            // an ordering that cannot survive one command, and that leaves an
            // orphan counterparty behind when the second write fails.
            let counterpartyId = try resolveOrCreateCounterparty(db, a.merchant)

            let oldLegs = try a.id.flatMap { try Entries.resolveEntryRef(db, $0) }
                .map { ref in try Row.fetchAll(db, sql: """
                    SELECT id, account_id, amount, amount_base, memo, cleared_at
                      FROM postings WHERE entry_id = ? AND account_id IS NOT NULL
                    """, arguments: [ref.entryId]) } ?? []

            var legs: [Entries.Leg] = []
            for (accountId, amount) in byAccount {
                guard let acctCcy = try String.fetchOne(db, sql: "SELECT currency FROM accounts WHERE id = ?",
                                                        arguments: [accountId]) else {
                    throw I18nError("error.notFound.account", [:], "Account not found")
                }
                // The cell is in the purchase's currency; the leg is recorded in
                // the card's, because that is what appears on its statement.
                let native = Entries.r2(try Entries.convertToBase(db, amount, purchaseCcy, acctCcy, a.date).amountBase)
                let conv = try Entries.convertToBase(db, amount, purchaseCcy, base, a.date)

                // Match by account (Decision 29): an unchanged card keeps its
                // posting, its memo and its reconcile mark. A changed card is a
                // NEW posting, so the mark goes with the old one — no extra rule.
                let prior = oldLegs.first { ($0["account_id"] as String?) == accountId }
                // …and the mark also drops when the AMOUNT changes (Decision 30):
                // a tick asserts "I checked this against my statement", which a
                // different amount no longer supports. clearedBalance is just the
                // sum of ticked legs, so keeping it would silently move a finished
                // reconciliation.
                let sameAmount = prior.map { abs(($0["amount"] as Double) - native) < 0.005 } ?? false
                legs.append(.account(Entries.AccountLeg(
                    accountId: accountId, amount: native,
                    amountBase: Entries.r2(conv.amountBase), exchangeRate: conv.rate,
                    memo: prior?["memo"], id: prior?["id"],
                    clearedAt: sameAmount ? prior?["cleared_at"] : nil)))
            }
            // The caller computes the balancing category legs (Decision 25):
            // `rebuildEntry` writes exactly what it is handed and has no
            // auto-balance field — that is a `NewEntry`/`postEntry` concept.
            for (categoryId, amount) in byCategory {
                let b = try Entries.convertToBase(db, amount, purchaseCcy, base, a.date).amountBase
                legs.append(.category(Entries.CategoryLeg(categoryId: categoryId, amountBase: Entries.r2(-b))))
            }

            let status = a.status.flatMap(Entries.Status.init(rawValue:))
            let refundedEntryId = try a.refundedTransactionId
                .flatMap { try Entries.resolveEntryRef(db, $0)?.entryId }

            if let id = a.id, let ref = try Entries.resolveEntryRef(db, id) {
                var patch = Entries.EntryPatch()
                patch.date = .set(a.date)
                patch.time = .set(a.time)
                patch.description = .set(a.merchant)
                patch.notes = .set(a.note)
                patch.counterpartyId = .set(counterpartyId)
                patch.refundedEntryId = .set(refundedEntryId)
                if let kindV = a.kind.flatMap(Entries.Kind.init(rawValue:)) { patch.kind = .set(kindV) }
                if let status { patch.status = .set(status) }
                patch.legs = .set(legs)
                try Entries.rebuildEntry(db, ref.entryId, patch)
                // `rebuildEntry` never writes `entry_tags` — which is exactly why
                // `setTransactionTags` is a separate write in both sheets today.
                try replaceTags(db, entryId: ref.entryId, tagIds: a.tagIds)
                return ref.entryId
            }

            let entryId = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: a.ledgerId, date: a.date, time: a.time,
                description: a.merchant, kind: kind, status: status, legs: legs,
                notes: a.note, counterpartyId: counterpartyId, refundedEntryId: refundedEntryId,
                sourceTemplateId: a.sourceTemplateId, occurrenceDate: a.occurrenceDate,
                groupId: a.groupId,
                skipRules: a.skipRules ?? false, allowDuplicate: a.allowDuplicate ?? false))
            try replaceTags(db, entryId: entryId, tagIds: a.tagIds)
            return entryId
        }
    }

    /// Look the merchant up, and create it when the ledger has not seen it.
    private static func resolveOrCreateCounterparty(_ db: Database, _ name: String) throws -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let existing = try Entries.resolveCounterpartyIdByName(db, trimmed) { return existing }
        let id = Entries.newId("cp")
        try db.execute(sql: """
            INSERT INTO counterparties (id, name, is_verified, created_at, updated_at)
            VALUES (?, ?, 0, datetime('now'), datetime('now'))
            """, arguments: [id, trimmed])
        return id
    }

    /// Tags are a SET-REPLACE: nil leaves them alone, a list replaces them wholesale.
    private static func replaceTags(_ db: Database, entryId: String, tagIds: [String]?) throws {
        guard let tagIds else { return }
        try db.execute(sql: "DELETE FROM entry_tags WHERE entry_id = ?", arguments: [entryId])
        for tagId in tagIds {
            try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)",
                           arguments: [entryId, tagId])
        }
    }
}
