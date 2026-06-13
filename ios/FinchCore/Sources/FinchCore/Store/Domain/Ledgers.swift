import Foundation
import GRDB

/// Ledgers domain — port of lib/db/domain/ledgers/mutations.ts.
public enum Ledgers {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createLedger: create,
        .updateLedger: update,
        .setDefaultLedger: setDefault,
        .deleteLedger: delete,
        .changeLedgerBase: changeBase,
    ]

    /// Re-derive every entry's amount_base at the new base: account legs re-lock
    /// (omit amountBase), category legs reconvert old→new base at the entry date,
    /// fx residue legs are dropped (rebuildEntry re-derives them).
    /// DEFERRED: the final auditLedger safety check (Audit needs a DatabaseQueue;
    /// the seal trigger + per-entry recompute already enforce balance) — and the
    /// FX path is the simplified rateToHub (no derived-rate insert / static map).
    static func changeBase(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let ledgerId: String; let newBase: String }
        let a = try args.to(A.self)
        let ledgerId = a.ledgerId
        let newBase = a.newBase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ledgerId.isEmpty { throw I18nError("error.required.ledgerId", [:], "ledgerId is required") }
        if !isISO3(newBase) { throw I18nError("error.ledger.newBaseISO", [:], "newBase must be a 3-letter ISO code") }
        guard let oldBase = try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id = ?", arguments: [ledgerId]) else {
            throw I18nError("error.notFound.ledger", [:], "Ledger not found")
        }
        if oldBase == newBase { return }

        try Entries.ensureSystemCategories(db, ledgerId)
        try db.execute(sql: "UPDATE ledgers SET base_currency = ?, updated_at = datetime('now') WHERE id = ?", arguments: [newBase, ledgerId])
        let fxCatId = try String.fetchOne(db, sql: "SELECT id FROM categories WHERE ledger_id = ? AND system = 'fx'", arguments: [ledgerId])
        for e in try Row.fetchAll(db, sql: "SELECT id, date FROM entries WHERE ledger_id = ? ORDER BY date, id", arguments: [ledgerId]) {
            let entryId: String = e["id"], entryDate: String = e["date"]
            var legs: [Entries.Leg] = []
            for p in try Row.fetchAll(db, sql: "SELECT id, account_id, category_id, amount, amount_base, memo FROM postings WHERE entry_id = ? ORDER BY sort_order", arguments: [entryId]) {
                if let acctId = p["account_id"] as String? {
                    legs.append(.account(Entries.AccountLeg(accountId: acctId, amount: p["amount"], memo: p["memo"], id: p["id"])))   // omit amountBase → re-lock
                } else {
                    let catId = p["category_id"] as String?
                    if let fx = fxCatId, catId == fx { continue }   // drop fx residue
                    let conv = try Entries.convertToBase(db, p["amount_base"], oldBase, newBase, entryDate)
                    legs.append(.category(Entries.CategoryLeg(categoryId: catId, amountBase: Entries.r2(conv.amountBase), memo: p["memo"], id: p["id"])))
                }
            }
            var ep = Entries.EntryPatch()
            ep.legs = .set(legs)
            try Entries.rebuildEntry(db, entryId, ep)
        }
    }

    private static func isISO3(_ s: String) -> Bool { s.count == 3 && s.allSatisfy { $0.isLetter && $0.isUppercase } }

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let name: String; let base: String; let color: String?; let tagline: String? }
        let a = try args.to(A.self)
        let id = a.id
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = a.base.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if id.isEmpty { throw I18nError("error.required.id", [:], "id is required") }
        if name.isEmpty { throw I18nError("error.required.name", [:], "Name is required") }
        if !isISO3(base) { throw I18nError("error.ledger.baseISO", [:], "base must be a 3-letter ISO code") }
        if try Int.fetchOne(db, sql: "SELECT 1 FROM ledgers WHERE id = ?", arguments: [id]) != nil {
            throw I18nError("error.ledger.duplicateId", [:], "Ledger id already exists")
        }
        try db.execute(sql: "INSERT INTO ledgers (id, name, base_currency, is_default, color, tagline, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?, datetime('now'), datetime('now'))",
                       arguments: [id, name, base, a.color, a.tagline])
        try Entries.ensureSystemCategories(db, id)
    }

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString, !id.isEmpty else { throw I18nError("error.required.id", [:], "id is required") }
        let patch = args.patchObject
        if let nameV = patch["name"], !nameV.isNonEmptyTrimmedString { throw I18nError("error.ledger.nameEmpty", [:], "Name cannot be empty") }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        if let v = patch["name"] { sets.append("name = ?"); bind.append(v.asString?.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if patch.keys.contains("color") { sets.append("color = ?"); bind.append(patch["color"]!.sqlBind) }
        if patch.keys.contains("tagline") { sets.append("tagline = ?"); bind.append(patch["tagline"]!.sqlBind) }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE ledgers SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func setDefault(_ db: Database, _ args: Args) throws {
        guard let id = args.idString, !id.isEmpty else { throw I18nError("error.required.id", [:], "id is required") }
        if try Int.fetchOne(db, sql: "SELECT 1 FROM ledgers WHERE id = ?", arguments: [id]) == nil {
            throw I18nError("error.notFound.ledger", [:], "Ledger not found")
        }
        try db.execute(sql: "UPDATE ledgers SET is_default = 0, updated_at = datetime('now')")
        try db.execute(sql: "UPDATE ledgers SET is_default = 1, updated_at = datetime('now') WHERE id = ?", arguments: [id])
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        let id = try args.to(A.self).id
        if id.isEmpty { throw I18nError("error.required.id", [:], "id is required") }
        guard let wasDefaultInt = try Int.fetchOne(db, sql: "SELECT is_default FROM ledgers WHERE id = ?", arguments: [id]) else {
            throw I18nError("error.notFound.ledger", [:], "Ledger not found")
        }
        let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledgers WHERE id != ?", arguments: [id]) ?? 0
        if remaining == 0 { throw I18nError("error.ledger.lastLedger", [:], "Cannot delete the last ledger") }

        // Explicit child deletes (the web's order; postings/entry_tags cascade off entries).
        for sql in [
            "DELETE FROM entry_attachments WHERE ledger_id = ?", "DELETE FROM entries WHERE ledger_id = ?",
            "DELETE FROM scheduled_templates WHERE ledger_id = ?", "DELETE FROM rules WHERE ledger_id = ?",
            "DELETE FROM holdings WHERE ledger_id = ?", "DELETE FROM budgets WHERE ledger_id = ?",
            "DELETE FROM budget_groups WHERE ledger_id = ?", "DELETE FROM accounts WHERE ledger_id = ?",
            "DELETE FROM account_groups WHERE ledger_id = ?", "DELETE FROM categories WHERE ledger_id = ?",
            "DELETE FROM tags WHERE ledger_id = ?", "DELETE FROM counterparties WHERE ledger_id = ?",
        ] { try db.execute(sql: sql, arguments: [id]) }

        if wasDefaultInt == 1 {
            if let next = try String.fetchOne(db, sql: "SELECT id FROM ledgers WHERE id != ? ORDER BY name LIMIT 1", arguments: [id]) {
                try db.execute(sql: "UPDATE ledgers SET is_default = 1, updated_at = datetime('now') WHERE id = ?", arguments: [next])
            }
        }
        try db.execute(sql: "DELETE FROM ledgers WHERE id = ?", arguments: [id])

        // Drop this ledger from the per-ledger display-currency map.
        if let raw = try AppDomain.getAppState(db, "displayCurrencyByLedger"), let data = raw.data(using: .utf8),
           var map = try? JSONDecoder().decode([String: String].self, from: data), map[id] != nil {
            map.removeValue(forKey: id)
            try AppDomain.setAppState(db, "displayCurrencyByLedger", String(data: try JSONEncoder().encode(map), encoding: .utf8) ?? "{}")
        }
        // DEFERRED: attachment-file unlink.
    }
}
