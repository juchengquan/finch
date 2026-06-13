import Foundation
import GRDB

/// App/system domain — port of lib/db/domain/_app/mutations.ts: the FX rate pair
/// + the app_state setters. DEFERRED: `reset` (truncate + re-seed reference data
/// + transactions.json) is intentionally not registered — it stays
/// notImplemented until the seed is ported.
public enum App {
    public static let handlers: [ActionName: Apply.Handler] = [
        .setExchangeRate: setExchangeRate,
        .deleteExchangeRate: deleteExchangeRate,
        .setMobileTabIds: setMobileTabIds,
        .setDisplayCurrency: setDisplayCurrency,
        .setBackupFrequency: setBackupFrequency,
        .setBackupRetention: setBackupRetention,
    ]

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
