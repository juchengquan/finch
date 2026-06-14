import Foundation
import GRDB

/// Transfers domain — port of lib/db/domain/transfers/mutations.ts.
public enum Transfers {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createTransfer: create,
        .updateTransfer: update,
        .deleteTransfer: delete,
    ]

    /// Re-amount a transfer's two account legs (ratio-scaling the other side when
    /// only one is given), preserving pinned rates, then rebuild. Each leg's
    /// reconcile mark (cleared_at) is carried through, so editing a cleared
    /// transfer keeps both legs cleared.
    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateTransfer requires an id") }
        let patch = args.patchObject
        guard let ref = try Entries.resolveEntryRef(db, id) else { return }
        let entryId = ref.entryId
        let legs = try Row.fetchAll(db, sql: "SELECT id, account_id, amount, amount_base, exchange_rate, currency, memo, cleared_at FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order", arguments: [entryId])
        if legs.count < 2 { return }
        let fromLeg = legs.first { ($0["amount"] as Double) < 0 } ?? legs[0]
        let toLeg = legs.first { ($0["amount"] as Double) > 0 } ?? legs[legs.count - 1]
        let sameCurrency = (fromLeg["currency"] as String) == (toLeg["currency"] as String)
        let hasFrom = patch.keys.contains("fromAmount"), hasTo = patch.keys.contains("toAmount")

        var newFromNative = abs(fromLeg["amount"] as Double)
        var newToNative = abs(toLeg["amount"] as Double)
        if hasFrom || hasTo {
            let oldFrom = abs(fromLeg["amount"] as Double), oldTo = abs(toLeg["amount"] as Double)
            if hasFrom { newFromNative = abs(patch["fromAmount"]?.asDouble ?? 0) }
            if hasTo { newToNative = abs(patch["toAmount"]?.asDouble ?? 0) }
            if !(newFromNative > 0) || !(newToNative > 0) { throw I18nError("error.transfer.amountGt0", [:], "Transfer amount must be greater than 0") }
            if hasFrom && !hasTo { newToNative = Entries.r2(oldTo * (oldFrom > 0 ? newFromNative / oldFrom : 1)) }
            else if hasTo && !hasFrom { newFromNative = Entries.r2(oldFrom * (oldTo > 0 ? newToNative / oldTo : 1)) }
            else if sameCurrency && abs(newFromNative - newToNative) > 0.005 {
                throw I18nError("error.transfer.sameCurrencyMismatch", [:], "Same-currency transfer amounts must match")
            }
        }
        let oldFromBase = abs(fromLeg["amount_base"] as Double), oldToBase = abs(toLeg["amount_base"] as Double)
        let oldFrom2 = abs(fromLeg["amount"] as Double), oldTo2 = abs(toLeg["amount"] as Double)
        let newFromBase = Entries.r2(oldFromBase * (oldFrom2 > 0 ? newFromNative / oldFrom2 : 1))
        let newToBase = Entries.r2(oldToBase * (oldTo2 > 0 ? newToNative / oldTo2 : 1))
        let newFromRate = newFromNative != 0 ? ((newFromBase / newFromNative) * 1e6).rounded() / 1e6 : (fromLeg["exchange_rate"] as Double)
        let newToRate = newToNative != 0 ? ((newToBase / newToNative) * 1e6).rounded() / 1e6 : (toLeg["exchange_rate"] as Double)

        var ep = Entries.EntryPatch()
        ep.legs = .set([
            .account(Entries.AccountLeg(accountId: fromLeg["account_id"], amount: -newFromNative, amountBase: -newFromBase, exchangeRate: newFromRate, memo: fromLeg["memo"], id: fromLeg["id"], clearedAt: fromLeg["cleared_at"])),
            .account(Entries.AccountLeg(accountId: toLeg["account_id"], amount: newToNative, amountBase: newToBase, exchangeRate: newToRate, memo: toLeg["memo"], id: toLeg["id"], clearedAt: toLeg["cleared_at"])),
        ])
        if let d = patch["date"]?.asString { ep.date = .set(d) }
        if patch.keys.contains("time") { ep.time = .set(patch["time"]?.asString) }
        if patch.keys.contains("note") { ep.notes = .set(patch["note"]?.asString) }
        try Entries.rebuildEntry(db, entryId, ep)
    }

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let fromAccountId: String; let toAccountId: String; let fromAmount: Double
            let toAmount: Double?; let date: String; let time: String?; let note: String?; let sourceTemplateId: String?
        }
        let a = try args.to(A.self)
        try Entries.postTransfer(db, fromAccountId: a.fromAccountId, toAccountId: a.toAccountId,
                                 fromAmount: a.fromAmount, toAmount: a.toAmount, date: a.date,
                                 time: a.time, note: a.note, sourceTemplateId: a.sourceTemplateId)
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        guard let ref = try Entries.resolveEntryRef(db, try args.to(A.self).id) else { return }
        try Entries.deleteEntry(db, ref.entryId)
    }
}
