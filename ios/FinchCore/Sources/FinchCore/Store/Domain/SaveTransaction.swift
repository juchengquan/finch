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
        ///
        /// **A transfer is the exception**, and it follows from what a transfer is:
        /// there is no single purchase currency when 110 USD leaves one card and
        /// 100 EUR arrives at another. The user types both, so a transfer's cells
        /// are already in each card's own currency and are stored as given.
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
            // Every card must move money the same way the kind says (Decision 28).
            // Rejected, never coerced: a mixed-sign expense records a purchase the
            // user did not describe — one card paying while another receives — and
            // it BALANCES, so nothing downstream would ever flag it.
            //
            // Scoped to the payment cells only. Applied to a top-level amount it
            // would break the CSV import, which carries raw signed amounts and no
            // kind, and App Intents. A transfer is exempt by definition: one leg
            // out, one leg in, which `validateShape` checks separately.
            if kind != .transfer {
                let wantsPositive = (kind == .income || kind == .refund)
                if byAccount.contains(where: { ($0.amount > 0) != wantsPositive }) {
                    throw I18nError("error.split.signMismatch", [:],
                                    "Every payment must match the transaction's direction")
                }
            }
            var byCategory: [(id: String?, amount: Double)] = []
            for c in a.cells {
                if let i = byCategory.firstIndex(where: { $0.id == c.categoryId }) {
                    byCategory[i].amount += c.amount
                } else {
                    byCategory.append((c.categoryId, c.amount))
                }
            }
            // A transfer's description and leg memos are ENGINE-authored, not the
            // sheet's job — they name the other side, so the transfer reads
            // correctly in each account's feed. Only filled when absent, so an
            // edit that preserved a leg keeps whatever memo it already had.
            var transferMemos: [String: String] = [:]
            var description = a.merchant
            if kind == .transfer, byAccount.count == 2 {
                let names = try Row.fetchAll(db, sql: "SELECT id, name FROM accounts WHERE id IN (?, ?)",
                                             arguments: [byAccount[0].id, byAccount[1].id])
                    .reduce(into: [String: String]()) { $0[$1["id"]] = $1["name"] }
                let from = byAccount.first { $0.amount < 0 } ?? byAccount[0]
                let to = byAccount.first { $0.amount > 0 } ?? byAccount[1]
                if let toName = names[to.id] { transferMemos[from.id] = "Transfer to \(toName)" }
                if let fromName = names[from.id] { transferMemos[to.id] = "Transfer from \(fromName)" }
                if description.trimmingCharacters(in: .whitespaces).isEmpty { description = "Transfer" }
            }

            // Resolve-or-create the merchant. `resolveCounterpartyIdByName` only
            // LOOKS UP, which is why the sheets call `createCounterparty` first —
            // an ordering that cannot survive one command, and that leaves an
            // orphan counterparty behind when the second write fails.
            let counterpartyId = kind == .transfer ? nil : try resolveOrCreateCounterparty(db, a.merchant)

            let oldLegs = try a.id.flatMap { try Entries.resolveEntryRef(db, $0) }
                .map { ref in try Row.fetchAll(db, sql: """
                    SELECT id, account_id, amount, amount_base, memo, cleared_at
                      FROM postings WHERE entry_id = ? AND account_id IS NOT NULL
                    """, arguments: [ref.entryId]) } ?? []

            let status = a.status.flatMap(Entries.Status.init(rawValue:))
            let refundedEntryId = try a.refundedTransactionId
                .flatMap { try Entries.resolveEntryRef(db, $0)?.entryId }

            // SHAPE DERIVATION (Decision 15). The CATEGORY count decides, not the
            // card count:
            //   one category  -> ONE transaction with a payment leg per card
            //   several       -> one transaction PER CARD, linked by group_id
            //
            // The first is the shape that already ships, and deriving it wrongly
            // is the trap here: "one entry per card" is the obvious implementation
            // of a grid and would silently turn every split-tender purchase into a
            // group. Several categories genuinely cannot be one entry — a single
            // entry is split on at most one axis, because the projection copies
            // its whole splits array onto every account-leg row.
            let isGrid = byCategory.count > 1 && byAccount.count > 1

            // The id may name an ENTRY (ordinary) or a GROUP (grid).
            var existingIds: [String] = []
            if let id = a.id {
                existingIds = try String.fetchAll(db, sql:
                    "SELECT id FROM entries WHERE group_id = ? ORDER BY created_at", arguments: [id])
                if existingIds.isEmpty, let ref = try Entries.resolveEntryRef(db, id) {
                    existingIds = [ref.entryId]
                }
            }
            // Match rows to existing entries BY CARD (Decision 21): a card that is
            // still here keeps its entry, its id, its receipt and its reconcile
            // marks. Minting fresh ids instead would destroy all three on an
            // ordinary edit while every other test here still passed.
            var entryForAccount: [String: String] = [:]
            for e in existingIds {
                for acct in try String.fetchAll(db, sql:
                    "SELECT account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL",
                    arguments: [e]) where entryForAccount[acct] == nil {
                    entryForAccount[acct] = e
                }
            }

            let rows: [[(id: String, amount: Double)]] = isGrid ? byAccount.map { [$0] } : [byAccount]
            // A group of one is not a group (Decision 20), so a rewrite that
            // collapses to a single row clears the link rather than leaving a lone
            // transaction claiming membership.
            //
            // **Only when the rewrite covers the whole purchase.** Editing ONE card
            // of a grid names a single entry and comes back with a single row, which
            // looks identical to a collapse from here. Clearing the link there would
            // quietly split one purchase into two — and `purchaseKey` would then
            // count it twice, the exact bug `group_id` exists to prevent. Decision 21
            // wants the whole grid to reopen so this cannot be sent at all; until it
            // does, membership survives a partial edit.
            let groupId: String?
            if rows.count > 1 {
                groupId = existingIds.isEmpty ? Entries.newId("grp") : (a.id ?? Entries.newId("grp"))
            } else if existingIds.count == 1,
                      let held = try String.fetchOne(db, sql: "SELECT group_id FROM entries WHERE id = ?",
                                                     arguments: [existingIds[0]]),
                      (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE group_id = ?",
                                        arguments: [held]) ?? 0) > 1 {
                groupId = held
            } else {
                groupId = nil
            }

            var writtenIds: [String] = []
            for row in rows {
                let rowAccounts = Set(row.map(\.id))
                let rowCells = a.cells.filter { rowAccounts.contains($0.accountId) }
                let legs = try buildLegs(db, row: row, cells: rowCells, kind: kind,
                                         purchaseCcy: purchaseCcy, base: base, date: a.date,
                                         transferMemos: transferMemos,
                                         priorEntryId: isGrid
                                            ? row.compactMap { entryForAccount[$0.id] }.first
                                            : existingIds.first)
                // Matching by card is a GRID rule — there, each entry IS a card,
                // so a card that vanished takes its entry with it. An ordinary
                // transaction has no such correspondence: moving its payment to
                // another card is an EDIT, not a delete-and-recreate, which would
                // destroy the receipt and change the id of the row on screen.
                let target = isGrid
                    ? row.compactMap { entryForAccount[$0.id] }.first
                    : existingIds.first

                if let target, existingIds.contains(target) {
                    var patch = Entries.EntryPatch()
                    patch.date = .set(a.date)
                    patch.time = .set(a.time)
                    patch.description = .set(description)
                    patch.notes = .set(a.note)
                    patch.counterpartyId = .set(counterpartyId)
                    patch.refundedEntryId = .set(refundedEntryId)
                    if let kindV = a.kind.flatMap(Entries.Kind.init(rawValue:)) { patch.kind = .set(kindV) }
                    if let status { patch.status = .set(status) }
                    patch.legs = .set(legs)
                    try Entries.rebuildEntry(db, target, patch)
                    try db.execute(sql: "UPDATE entries SET group_id = ? WHERE id = ?", arguments: [groupId, target])
                    // `rebuildEntry` never writes `entry_tags` — which is exactly
                    // why `setTransactionTags` is a separate write in both sheets.
                    try replaceTags(db, entryId: target, tagIds: a.tagIds)
                    writtenIds.append(target)
                } else {
                    let newId = try Entries.postEntry(db, Entries.NewEntry(
                        ledgerId: a.ledgerId, date: a.date, time: a.time,
                        description: description, kind: kind, status: status, legs: legs,
                        notes: a.note, counterpartyId: counterpartyId, refundedEntryId: refundedEntryId,
                        sourceTemplateId: a.sourceTemplateId, occurrenceDate: a.occurrenceDate,
                        groupId: groupId,
                        skipRules: a.skipRules ?? false, allowDuplicate: a.allowDuplicate ?? false))
                    try replaceTags(db, entryId: newId, tagIds: a.tagIds)
                    writtenIds.append(newId)
                }
            }

            // A card the user removed takes its entry with it.
            for stale in existingIds where !writtenIds.contains(stale) {
                try Entries.deleteEntry(db, stale)
            }
            // Every money path invalidates the rollover cache, and it must run for
            // EVERY row: skipping one leaves wrong budget numbers with no error and
            // nothing in the audit.
            for id in writtenIds { try Budgets.invalidateForEntry(db, id) }

            return writtenIds.first ?? ""
        }
    }

    /// Build one entry's legs: a payment leg per card in `row`, plus the
    /// balancing category legs derived from that row's cells.
    ///
    /// `priorEntryId` is the entry this row is replacing, if any — its postings
    /// supply the ids, memos and reconcile marks that survive the edit.
    private static func buildLegs(_ db: Database, row: [(id: String, amount: Double)],
                                  cells: [Cell], kind: Entries.Kind,
                                  purchaseCcy: String, base: String, date: String,
                                  transferMemos: [String: String],
                                  priorEntryId: String?) throws -> [Entries.Leg] {
        let oldLegs = try priorEntryId.map { id in
            try Row.fetchAll(db, sql: """
                SELECT id, account_id, amount, memo, cleared_at
                  FROM postings WHERE entry_id = ? AND account_id IS NOT NULL
                """, arguments: [id])
        } ?? []

        var legs: [Entries.Leg] = []
        for (accountId, amount) in row {
            guard let acctCcy = try String.fetchOne(db, sql: "SELECT currency FROM accounts WHERE id = ?",
                                                    arguments: [accountId]) else {
                throw I18nError("error.notFound.account", [:], "Account not found")
            }
            // The cell is in the PURCHASE's currency; the leg is recorded in the
            // card's, because that is what appears on that card's statement.
            //
            // A TRANSFER is the one exception, and it follows from what a transfer
            // is rather than working around it: there is no single purchase
            // currency when 110 USD leaves one card and 100 EUR arrives at
            // another. The user types BOTH numbers, so each cell is already in its
            // own card's currency. Converting them would store 90.91 EUR for a
            // typed 100 — a different transfer than the one described, balancing
            // through the FX residue so nothing downstream would flag it.
            let cellCcy = kind == .transfer ? acctCcy : purchaseCcy
            let native = Entries.r2(try Entries.convertToBase(db, amount, cellCcy, acctCcy, date).amountBase)
            let conv = try Entries.convertToBase(db, amount, cellCcy, base, date)

            // Match by account (Decision 29): an unchanged card keeps its posting,
            // its memo and its reconcile mark. A changed card is a NEW posting, so
            // the mark goes with the old one — no extra rule needed.
            let prior = oldLegs.first { ($0["account_id"] as String?) == accountId }
            // The mark ALSO drops when the amount changes (Decision 30): a tick
            // asserts "I checked this against my statement", and clearedBalance is
            // just the sum of ticked legs, so keeping it across an amount change
            // silently moves a finished reconciliation.
            let sameAmount = prior.map { abs(($0["amount"] as Double) - native) < 0.005 } ?? false
            // What the user TYPED, when that is not already what the leg says.
            // `Projection.swift:81` displays `orig_amount ?? amount`, so without
            // this a €100 purchase on a USD card comes back as $110 — and the €100
            // is gone, recoverable from nothing else in the row.
            //
            // Only when the currencies differ, mirroring `addTransaction`
            // (`Transactions.swift:350`): on a same-currency purchase the pair
            // would just duplicate `amount`, and a nil is what "not a
            // foreign-currency entry" means everywhere else in the schema.
            //
            // A transfer never qualifies: `cellCcy` IS `acctCcy` above, because a
            // transfer's two sides are each typed in their own card's currency.
            let typedInAnotherCurrency = cellCcy != acctCcy
            legs.append(.account(Entries.AccountLeg(
                accountId: accountId, amount: native,
                amountBase: Entries.r2(conv.amountBase), exchangeRate: conv.rate,
                memo: prior?["memo"] ?? transferMemos[accountId], id: prior?["id"],
                origAmount: typedInAnotherCurrency ? Entries.r2(amount) : nil,
                origCurrency: typedInAnotherCurrency ? cellCcy : nil,
                clearedAt: sameAmount ? prior?["cleared_at"] : nil)))
        }

        // A transfer has NO category leg — that is what makes it a transfer — and
        // its two account legs already sum to zero.
        if kind != .transfer {
            var byCategory: [(id: String?, amount: Double)] = []
            for c in cells {
                if let i = byCategory.firstIndex(where: { $0.id == c.categoryId }) {
                    byCategory[i].amount += c.amount
                } else {
                    byCategory.append((c.categoryId, c.amount))
                }
            }
            // The caller computes the balancing legs (Decision 25): `rebuildEntry`
            // writes exactly what it is handed and has no auto-balance field.
            //
            // A category leg is stored in the LEDGER BASE, so on a foreign-currency
            // purchase the stored figure is not the one that was entered. Keeping
            // the typed figure per cell is what lets a grid reopen showing the
            // numbers the user wrote rather than back-converted ones — which drift
            // by a cent on awkward rates, and would be baked in on the next save.
            //
            // Negated alongside `amountBase` so the two carry one sign convention
            // and `Projection`'s existing flip restores both together.
            let typedInAnotherCurrency = purchaseCcy != base
            for (categoryId, amount) in byCategory {
                let b = try Entries.convertToBase(db, amount, purchaseCcy, base, date).amountBase
                legs.append(.category(Entries.CategoryLeg(
                    categoryId: categoryId, amountBase: Entries.r2(-b),
                    origAmount: typedInAnotherCurrency ? Entries.r2(-amount) : nil,
                    origCurrency: typedInAnotherCurrency ? purchaseCcy : nil)))
            }
        }
        return legs
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
