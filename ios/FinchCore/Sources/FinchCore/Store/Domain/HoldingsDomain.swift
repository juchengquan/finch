import Foundation
import GRDB

/// Holdings domain — port of lib/db/domain/holdings/mutations.ts.
public enum Holdings {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createHolding: create,
        .updateHolding: update,
        .setHoldingPrice: setPrice,
        .deleteHolding: delete,
    ]

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let accountId: String; let symbol: String
            let name: String?; let shares: Double; let costBasis: Double; let currency: String?
            let lastPrice: Double?; let lastPriceDate: String?; let notes: String?
        }
        let a = try args.to(A.self)
        let accountId = a.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = a.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if accountId.isEmpty { throw I18nError("error.required.investmentAccount", [:], "An investment account is required") }
        if symbol.isEmpty { throw I18nError("error.required.symbol", [:], "Symbol is required") }
        if !(a.shares > 0) { throw I18nError("error.holding.sharesGt0", [:], "Shares must be greater than 0") }
        if !(a.costBasis >= 0) { throw I18nError("error.holding.costBasisGte0", [:], "Cost basis must be 0 or greater") }
        guard let acct = try Row.fetchOne(db, sql: "SELECT type, currency, ledger_id FROM accounts WHERE id = ?", arguments: [accountId]) else {
            throw I18nError("error.notFound.account", [:], "Account not found")
        }
        if (acct["type"] as String) != "investment" { throw I18nError("error.holding.notInvestment", [:], "Holdings can only be added to an investment account") }
        let accountCurrency: String = acct["currency"]
        let ledgerId = a.ledgerId ?? (acct["ledger_id"] as String? ?? "personal")
        let requested = a.currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? accountCurrency
        if requested != accountCurrency {
            throw I18nError("error.holding.currencyMismatch", ["currency": accountCurrency], "Holding currency must match the account currency (\(accountCurrency))")
        }
        try db.execute(sql: "INSERT INTO holdings (id,ledger_id,account_id,symbol,name,shares,cost_basis,currency,last_price,last_price_date,notes,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId("h"), ledgerId, accountId, symbol,
                                   a.name?.trimmingCharacters(in: .whitespacesAndNewlines), a.shares, a.costBasis,
                                   accountCurrency, a.lastPrice, a.lastPriceDate, a.notes])
    }

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateHolding requires an id") }
        let patch = args.patchObject
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        if let v = patch["symbol"] {
            guard let s = v.asString, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw I18nError("error.holding.symbolEmpty", [:], "Symbol cannot be empty")
            }
            sets.append("symbol = ?"); bind.append(s.uppercased())
        }
        if patch.keys.contains("name") { sets.append("name = ?"); bind.append(patch["name"]!.sqlBind) }
        if let v = patch["shares"] {
            guard let s = v.asDouble, s > 0 else { throw I18nError("error.holding.sharesGt0", [:], "Shares must be greater than 0") }
            sets.append("shares = ?"); bind.append(s)
        }
        if let v = patch["costBasis"] {
            guard let c = v.asDouble, c >= 0 else { throw I18nError("error.holding.costBasisGte0", [:], "Cost basis must be 0 or greater") }
            sets.append("cost_basis = ?"); bind.append(c)
        }
        if patch.keys.contains("notes") { sets.append("notes = ?"); bind.append(patch["notes"]!.sqlBind) }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE holdings SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func setPrice(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let price: Double?; let date: String? }
        let a = try args.to(A.self)
        if let p = a.price, !(p >= 0) { throw I18nError("error.holding.priceGte0", [:], "Price must be 0 or greater") }
        let date = a.price == nil ? nil : a.date
        if let d = date, !isYMD(d) { throw I18nError("error.fx.dateFormat", [:], "Date must be YYYY-MM-DD") }
        try db.execute(sql: "UPDATE holdings SET last_price = ?, last_price_date = ?, updated_at = datetime('now') WHERE id = ?",
                       arguments: [a.price, date, a.id])
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM holdings WHERE id = ?", arguments: [try args.to(A.self).id])
    }
}
