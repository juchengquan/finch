import Foundation
import GRDB

/// App/system domain — port of lib/db/domain/_app/mutations.ts: the FX rate pair,
/// the app_state setters, and `reset` (truncate). DEFERRED on reset: the web's
/// re-seed of reference data + transactions.json (iOS clears to empty).
public enum AppDomain {
    public static let handlers: [ActionName: Apply.Handler] = [
        .setExchangeRate: setExchangeRate,
        .deleteExchangeRate: deleteExchangeRate,
        .setMobileTabIds: setMobileTabIds,
        .setDisplayCurrency: setDisplayCurrency,
        .setBudgetOrder: setBudgetOrder,
        .setTrackedCurrencies: setTrackedCurrencies,
        .setBackupFrequency: setBackupFrequency,
        .setBackupRetention: setBackupRetention,
        .reset: reset,
    ]

    /// Truncate the canonical tables (children first; the web's RESET_TABLES order,
    /// minus the dropped legacy `transfers` table). DEFERRED: the web's re-seed of
    /// reference data + transactions.json — iOS reset clears to empty; re-seeding
    /// from a bundled default is a product decision for later.
    static func reset(_ db: Database, _ args: Args) throws {
        let tables = [
            "holdings", "entry_attachments", "entry_tags", "postings", "entries",
            "scheduled_splits", "scheduled_templates", "tags", "budgets", "budget_groups",
            "counterparties", "categories", "accounts", "account_groups", "exchange_rates",
            "rules", "ledgers", "app_state",
        ]
        for t in tables { try db.execute(sql: "DELETE FROM \(t)") }
    }

    // MARK: app_state get/set (upsert)

    static func setAppState(_ db: Database, _ key: String, _ value: String) throws {
        try db.execute(sql: """
            INSERT INTO app_state (key, value, created_at, updated_at)
            VALUES (?, ?, datetime('now'), datetime('now'))
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')
            """, arguments: [key, value])
    }
    static func getAppState(_ db: Database, _ key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = ?", arguments: [key])
    }

    // MARK: FX rates

    static func setExchangeRate(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let date: String; let currency: String; let rate: Double; let source: String? }
        let a = try args.to(A.self)
        let currency = a.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !isYMD(a.date) { throw I18nError("error.fx.dateFormat", [:], "Date must be YYYY-MM-DD") }
        if currency.isEmpty { throw I18nError("error.required.currency", [:], "Currency is required") }
        if !(a.rate > 0) { throw I18nError("error.fx.rateGt0", [:], "Rate must be greater than 0") }
        if currency == "USD" { throw I18nError("error.fx.usdHub", [:], "USD is the hub currency and is not stored") }
        try db.execute(sql: "INSERT OR REPLACE INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, ?, ?)",
                       arguments: [a.date, currency, a.rate, a.source])
    }

    static func deleteExchangeRate(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let date: String; let currency: String }
        let a = try args.to(A.self)
        try db.execute(sql: "DELETE FROM exchange_rates WHERE date = ? AND currency = ?",
                       arguments: [a.date, a.currency.uppercased()])
    }

    // MARK: app_state setters

    static func setMobileTabIds(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let ids: [String] }
        let ids = try args.to(A.self).ids
        try setAppState(db, "mobileTabs", String(data: try JSONEncoder().encode(ids), encoding: .utf8) ?? "[]")
    }

    static func setDisplayCurrency(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let ledgerId: String; let currency: String }
        let a = try args.to(A.self)
        var map: [String: String] = [:]
        if let raw = try getAppState(db, "displayCurrencyByLedger"), let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) { map = parsed }
        map[a.ledgerId] = a.currency
        try setAppState(db, "displayCurrencyByLedger", String(data: try JSONEncoder().encode(map), encoding: .utf8) ?? "{}")
    }

    static func setBudgetOrder(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let ledgerId: String; let budgetIds: [String] }
        let a = try args.to(A.self)
        var map: [String: [String]] = [:]
        if let raw = try getAppState(db, "budgetOrderByLedger"), let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: [String]].self, from: data) { map = parsed }
        map[a.ledgerId] = a.budgetIds
        try setAppState(db, "budgetOrderByLedger", String(data: try JSONEncoder().encode(map), encoding: .utf8) ?? "{}")
    }

    static func setTrackedCurrencies(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let codes: [String] }
        let codes = try args.to(A.self).codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && $0 != "USD" }
        let unique = Array(Set(codes)).sorted()
        try setAppState(db, "fxTrackedCurrencies", String(data: try JSONEncoder().encode(unique), encoding: .utf8) ?? "[]")
    }

    static func setBackupFrequency(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let frequencyMs: Double? }
        let ms = try args.to(A.self).frequencyMs
        let next = (ms.flatMap { $0.isFinite ? Int($0) : nil }) ?? (60 * 60 * 1000)
        try mergeBackupConfig(db, frequencyMs: next, retention: nil)
    }

    static func setBackupRetention(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let retention: Double? }
        let n = try args.to(A.self).retention
        let next = (n.flatMap { ($0.isFinite && $0 > 0) ? Int($0) : nil }) ?? 14
        try mergeBackupConfig(db, frequencyMs: nil, retention: next)
    }

    private static func mergeBackupConfig(_ db: Database, frequencyMs: Int?, retention: Int?) throws {
        var freq = 60 * 60 * 1000
        var ret = 14
        if let raw = try getAppState(db, "backupConfig"), let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let f = (parsed["frequencyMs"] as? Double).map(Int.init) ?? parsed["frequencyMs"] as? Int { freq = f }
            if let r = (parsed["retention"] as? Double).map(Int.init) ?? parsed["retention"] as? Int, r > 0 { ret = r }
        }
        if let f = frequencyMs { freq = f }
        if let r = retention { ret = r }
        let dict: [String: Int] = ["frequencyMs": freq, "retention": ret]
        try setAppState(db, "backupConfig", String(data: try JSONSerialization.data(withJSONObject: dict), encoding: .utf8) ?? "{}")
    }
}
