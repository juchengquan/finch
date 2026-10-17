import Foundation
import GRDB

/// Cross-ledger transfers — moving money between two sets of books
/// (`plans/ios-macos/2026-08-12-cross-ledger-transfers-design.md`).
///
/// **A pair of entries, never one.** `entries.ledger_id` is a single column and
/// the seal trigger checks `SUM(amount_base) = 0` per entry, where `amount_base`
/// is *that ledger's* base currency — two ledgers do not share a base, so a
/// single entry spanning both is not a well-formed statement. Each half is
/// therefore complete on its own: one account leg (the money leaving or
/// arriving) against the ledger's `interledger` equity category (where it went),
/// which is what makes the source book genuinely poorer rather than merely
/// rearranged. `interledger_link_id` ties the two so the app can treat them as
/// one thing.
///
/// **NATIVE-ONLY**, like `setEntryAttachment` and friends: the web has no action
/// that writes this, which is what keeps the whole feature — schema included —
/// off the web side without diverging anything the parity gates compare.
public enum Interledger {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createInterledgerTransfer: create,
        .updateInterledgerTransfer: update,
        .deleteInterledgerTransfer: delete,
    ]

    private struct Endpoint {
        let accountId: String
        let ledgerId: String
        let ledgerName: String
        let accountName: String
        let currency: String
    }

    private static func endpoint(_ db: Database, _ accountId: String) throws -> Endpoint {
        guard let r = try Row.fetchOne(db, sql: """
            SELECT a.ledger_id, a.name AS account_name, a.currency, l.name AS ledger_name
              FROM accounts a JOIN ledgers l ON l.id = a.ledger_id WHERE a.id = ?
            """, arguments: [accountId]) else {
            throw I18nError("error.notFound.account", [:], "Account not found")
        }
        return Endpoint(accountId: accountId, ledgerId: r["ledger_id"], ledgerName: r["ledger_name"],
                        accountName: r["account_name"], currency: r["currency"])
    }

    /// "Travel · Travel Card" — the partner's book and account, stamped at write
    /// time (D7) so a row can say where the money went without the projection
    /// ever reaching outside its own ledger.
    private static func label(_ e: Endpoint) -> String { "\(e.ledgerName) · \(e.accountName)" }

    struct CreateArgs: Decodable {
        let fromAccountId: String
        let toAccountId: String
        let fromAmount: Double
        let toAmount: Double?
        let date: String
        let time: String?
        let note: String?
        let status: String?
    }

    static func create(_ db: Database, _ args: Args) throws {
        let a = try args.to(CreateArgs.self)
        if a.fromAccountId == a.toAccountId {
            throw I18nError("error.transfer.sameAccount", [:], "Pick two different accounts")
        }
        let from = try endpoint(db, a.fromAccountId)
        let to = try endpoint(db, a.toAccountId)
        guard from.ledgerId != to.ledgerId else {
            // Not a judgement call: two accounts in one book is an ordinary
            // transfer — a single balanced entry. Writing a pair here would
            // record two entries where one belongs, and each would carry an
            // equity leg claiming money left the books when it never did.
            throw I18nError("error.interledger.sameLedger", [:],
                            "Both accounts are in the same ledger — use an ordinary transfer")
        }
        let fromAmt = abs(a.fromAmount)
        guard fromAmt > 0 else {
            throw I18nError("error.transfer.amountGt0", [:], "Transfer amount must be greater than 0")
        }
        // D5: the caller's received amount wins; absent, derive it from the stored
        // rate. Nothing can verify either number — each book balances alone — so
        // this is about record-keeping accuracy, not correctness.
        let toAmt: Double
        if let given = a.toAmount {
            toAmt = abs(given)
            guard toAmt > 0 else {
                throw I18nError("error.transfer.receivedGt0", [:], "Received amount must be greater than 0")
            }
        } else {
            toAmt = try Entries.convertToBase(db, fromAmt, from.currency, to.currency, a.date).amountBase
        }

        let status = a.status.flatMap(Entries.Status.init(rawValue:))
        let linkId = Entries.newId("xfer")
        let outId = try half(db, at: from, partner: to, amount: -fromAmt, args: a, status: status)
        let inId = try half(db, at: to, partner: from, amount: toAmt, args: a, status: status)
        try db.execute(sql: "UPDATE entries SET interledger_link_id = ? WHERE id IN (?, ?)",
                       arguments: [linkId, outId, inId])
    }

    /// One half: a single account leg auto-balanced against this ledger's
    /// `interledger` equity category — the same shape `postAdjustment` uses, and
    /// the shape both `validateShape` and the audit's kind-shape clause demand.
    private static func half(_ db: Database, at side: Endpoint, partner: Endpoint,
                             amount: Double, args a: CreateArgs, status: Entries.Status?) throws -> String {
        let category = try Entries.ensureInterledgerCategory(db, side.ledgerId)
        return try Entries.postEntry(db, Entries.NewEntry(
            ledgerId: side.ledgerId, date: a.date, time: a.time,
            description: label(partner), kind: .interledger, status: status,
            legs: [.account(Entries.AccountLeg(accountId: side.accountId, amount: Entries.r2(amount)))],
            autoBalance: .category(category), notes: a.note, skipRules: true))
    }

    /// Both halves of the pair an entry belongs to, in a stable order. Returns []
    /// when the id is not part of one.
    private static func pair(_ db: Database, _ entryId: String) throws -> [String] {
        guard let link = try String.fetchOne(db, sql:
            "SELECT interledger_link_id FROM entries WHERE id = ?", arguments: [entryId]) else { return [] }
        return try String.fetchAll(db, sql:
            "SELECT id FROM entries WHERE interledger_link_id = ? ORDER BY ledger_id", arguments: [link])
    }

    struct UpdateArgs: Decodable {
        let id: String
        let fromAmount: Double?
        let toAmount: Double?
        let date: String?
        let time: String?
        let note: String?
    }

    /// Re-amount and/or re-date the pair. Each half is rebuilt in place — ids
    /// survive, so attachments and any selection pointing at an entry stay valid.
    ///
    /// A half whose amount does not change keeps its legs: the Edit sheet always
    /// resends both amounts, so a date- or note-only edit arrives looking like a
    /// re-amount, and restating legs nobody changed is how a phantom FX leg got in.
    /// A half that does change restates its equity leg from the account leg's
    /// BASE value — the account may hold a currency other than its ledger's base,
    /// and mirroring the native figure left a gap `appendResidue` booked as FX.
    static func update(_ db: Database, _ args: Args) throws {
        let a = try args.to(UpdateArgs.self)
        let ids = try pair(db, a.id)
        guard ids.count == 2 else {
            throw I18nError("error.notFound.transaction", [:], "Not a cross-ledger transfer")
        }
        struct Half { let entryId, ledgerId, date, accountId, currency: String; let amount: Double }
        let halves: [Half] = try ids.compactMap { entryId in
            guard let r = try Row.fetchOne(db, sql: """
                SELECT e.ledger_id, e.date, p.account_id, p.amount, a.currency
                  FROM entries e JOIN postings p ON p.entry_id = e.id AND p.account_id IS NOT NULL
                  JOIN accounts a ON a.id = p.account_id
                 WHERE e.id = ? LIMIT 1
                """, arguments: [entryId]) else { return nil }
            return Half(entryId: entryId, ledgerId: r["ledger_id"], date: r["date"],
                        accountId: r["account_id"], currency: r["currency"], amount: r["amount"])
        }
        // The outgoing half is the negative one.
        guard let out = halves.first(where: { $0.amount < 0 }),
              let inc = halves.first(where: { $0.amount >= 0 }) else {
            throw I18nError("error.notFound.transaction", [:], "Not a cross-ledger transfer")
        }
        let oldFrom = abs(out.amount), oldTo = inc.amount
        let newFrom = a.fromAmount.map(abs) ?? oldFrom
        guard newFrom > 0 else {
            throw I18nError("error.transfer.amountGt0", [:], "Transfer amount must be greater than 0")
        }
        // Each side takes its own amount when given, because across currencies
        // there is no single right number to derive one from the other (D4).
        // Absent, the received side follows the transfer's own implied rate —
        // the rate the user effectively chose — not today's market rate.
        let newTo: Double
        if let given = a.toAmount {
            newTo = abs(given)
            guard newTo > 0 else {
                throw I18nError("error.transfer.receivedGt0", [:], "Received amount must be greater than 0")
            }
        } else {
            newTo = oldFrom > 0 ? Entries.r2(newFrom * oldTo / oldFrom) : oldTo
        }

        for (half, signed) in [(out, Entries.r2(-newFrom)), (inc, Entries.r2(newTo))] {
            var patch = Entries.EntryPatch()
            if signed != Entries.r2(half.amount) {
                let date = a.date ?? half.date
                let base = try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id = ?",
                                               arguments: [half.ledgerId]) ?? half.currency
                let conv = try Entries.convertToBase(db, signed, half.currency, base, date)
                let category = try Entries.ensureInterledgerCategory(db, half.ledgerId)
                patch.legs = .set([
                    .account(Entries.AccountLeg(accountId: half.accountId, amount: signed,
                                                amountBase: conv.amountBase, exchangeRate: conv.rate)),
                    .category(Entries.CategoryLeg(categoryId: category, amountBase: -conv.amountBase)),
                ])
            }
            if let date = a.date { patch.date = .set(date) }
            if let time = a.time { patch.time = .set(time) }
            if let note = a.note { patch.notes = .set(note) }
            _ = try Entries.rebuildEntry(db, half.entryId, patch)
        }
    }

    struct DeleteArgs: Decodable { let id: String }

    /// Deleting either half removes both: a surviving orphan would claim money
    /// arrived from — or vanished into — nowhere, and its book would no longer be
    /// true. (Deleting a whole LEDGER is the opposite case and deliberately
    /// leaves the survivor standing — see D8; it stays valid, just anonymous.)
    static func delete(_ db: Database, _ args: Args) throws {
        let a = try args.to(DeleteArgs.self)
        let ids = try pair(db, a.id)
        for entryId in (ids.isEmpty ? [a.id] : ids) {
            try Entries.deleteEntry(db, entryId)
        }
    }
}
