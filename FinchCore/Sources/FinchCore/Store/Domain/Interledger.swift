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

    /// Re-amount the pair. Each half is rebuilt in place — ids survive, so
    /// attachments and any selection pointing at an entry stay valid — and the
    /// equity leg is restated from the account leg so the half still balances.
    static func update(_ db: Database, _ args: Args) throws {
        let a = try args.to(UpdateArgs.self)
        let ids = try pair(db, a.id)
        guard ids.count == 2 else {
            throw I18nError("error.notFound.transaction", [:], "Not a cross-ledger transfer")
        }
        for entryId in ids {
            guard let row = try Row.fetchOne(db, sql:
                "SELECT ledger_id FROM entries WHERE id = ?", arguments: [entryId]) else { continue }
            let ledgerId: String = row["ledger_id"]
            guard let leg = try Row.fetchOne(db, sql: """
                SELECT account_id, amount FROM postings
                 WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1
                """, arguments: [entryId]) else { continue }
            let accountId: String = leg["account_id"]
            let old: Double = leg["amount"]
            // The outgoing half is the negative one; each side takes its own new
            // amount, because across currencies there is no single right number to
            // derive one from the other (D4).
            let newMagnitude = old < 0 ? a.fromAmount : a.toAmount
            guard let magnitude = newMagnitude.map({ abs($0) }) else { continue }
            guard magnitude > 0 else {
                throw I18nError("error.transfer.amountGt0", [:], "Transfer amount must be greater than 0")
            }
            let signed = Entries.r2(old < 0 ? -magnitude : magnitude)
            let category = try Entries.ensureInterledgerCategory(db, ledgerId)
            var patch = Entries.EntryPatch()
            patch.legs = .set([
                .account(Entries.AccountLeg(accountId: accountId, amount: signed)),
                .category(Entries.CategoryLeg(categoryId: category, amountBase: -signed)),
            ])
            if let date = a.date { patch.date = .set(date) }
            if let time = a.time { patch.time = .set(time) }
            if let note = a.note { patch.notes = .set(note) }
            _ = try Entries.rebuildEntry(db, entryId, patch)
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
