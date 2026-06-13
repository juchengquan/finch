import XCTest
import GRDB
@testable import FinchCore

/// Write-side round-trip parity (Phase 2 Task 17). Replays the EXACT seed + write
/// sequence the web oracle ran (from sequence.json) through the iOS `Apply`
/// chokepoint, then compares a canonical, id-/timestamp-agnostic snapshot of the
/// DB to the web's. Numbers render as "%.6f" strings so the structural JSONValue
/// comparison is free of float/JSON-format drift.
final class WriteParityTests: XCTestCase {

    func test_writeSequenceMatchesWebOracle() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("writeparity")
        struct Step: Decodable { let action: String; let args: JSONValue }
        struct Fixture: Decodable { let seedSql: [String]; let sequence: [Step]; let expected: JSONValue }
        let fx = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: dir.appendingPathComponent("sequence.json")))

        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in for sql in fx.seedSql { try db.execute(sql: sql) } }
        for step in fx.sequence {
            guard case .object(let o) = step.args else { continue }
            try Apply.apply(dbQueue: q, action: step.action, args: Args(o))
        }

        let actual = try q.read { db in try Self.canonicalState(db) }
        // Per-key diff for a readable failure.
        if actual != fx.expected, case .object(let exp) = fx.expected, case .object(let act) = actual {
            for key in Set(exp.keys).union(act.keys).sorted() where exp[key] != act[key] {
                XCTFail("canonicalState mismatch in '\(key)':\n  expected: \(exp[key] ?? .null)\n  actual:   \(act[key] ?? .null)")
            }
        }
        XCTAssertEqual(actual, fx.expected)
    }

    // MARK: canonicalState (mirror of export-fixtures.ts::canonicalState)

    private static func numStr(_ v: Double?) -> JSONValue { v.map { .string(String(format: "%.6f", $0)) } ?? .null }
    private static func str(_ v: String?) -> JSONValue { v.map { .string($0) } ?? .null }
    /// Parse a stored JSON blob into a structural JSONValue (key-order-independent).
    private static func parseJSON(_ v: String?) -> JSONValue {
        guard let v, let data = v.data(using: .utf8), let j = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return j
    }

    static func canonicalState(_ db: Database) throws -> JSONValue {
        // entries with nested postings, content-sorted (id-free).
        var entries: [(key: String, obj: JSONValue)] = []
        for e in try Row.fetchAll(db, sql: "SELECT * FROM entries") {
            let eid: String = e["id"]
            var postings: [JSONValue] = []
            var keyParts: [String] = []
            for p in try Row.fetchAll(db, sql: "SELECT account_id, category_id, amount, currency, amount_base, exchange_rate, orig_amount, orig_currency, memo, cleared_at, sort_order FROM postings WHERE entry_id = ? ORDER BY sort_order", arguments: [eid]) {
                let acct = p["account_id"] as String?, cat = p["category_id"] as String?, ab: Double = p["amount_base"]
                keyParts.append("\(acct ?? ""):\(cat ?? ""):\(String(format: "%.6f", ab))")
                postings.append(.object([
                    "account_id": str(acct), "category_id": str(cat), "amount": numStr(p["amount"]),
                    "currency": str(p["currency"]), "amount_base": numStr(ab), "exchange_rate": numStr(p["exchange_rate"]),
                    "orig_amount": numStr(p["orig_amount"]), "orig_currency": str(p["orig_currency"]),
                    "memo": str(p["memo"]), "cleared": .bool((p["cleared_at"] as String?) != nil),
                    "sort_order": .int(p["sort_order"]),
                ]))
            }
            let date: String = e["date"], kind: String = e["kind"], desc = e["description"] as String?
            let ekey = "\(date)|\(kind)|\(desc ?? "")|" + keyParts.joined(separator: ";")
            entries.append((ekey, .object([
                "ledger_id": str(e["ledger_id"]), "date": .string(date), "time": str(e["time"]),
                "description": str(desc), "kind": .string(kind), "status": str(e["status"]),
                "counterparty_id": str(e["counterparty_id"]), "refunded_entry_id": str(e["refunded_entry_id"]),
                "source_template_id": str(e["source_template_id"]), "notes": str(e["notes"]),
                "applied_rule_ids": str(e["applied_rule_ids"]), "reviewed": .bool((e["reviewed_at"] as String?) != nil),
                "sealed": .int(e["sealed"]), "postings": .array(postings),
            ])))
        }
        let entryArr = entries.sorted { $0.key < $1.key }.map { $0.obj }

        func table(_ sql: String, _ cols: [(String, (Row) -> JSONValue)]) throws -> JSONValue {
            .array(try Row.fetchAll(db, sql: sql).map { r in .object(Dictionary(uniqueKeysWithValues: cols.map { ($0.0, $0.1(r)) })) })
        }

        return .object([
            "entries": .array(entryArr),
            "ledgers": try table("SELECT * FROM ledgers ORDER BY id", [
                ("id", { str($0["id"]) }), ("name", { str($0["name"]) }), ("base", { str($0["base_currency"]) }),
                ("is_default", { .int($0["is_default"]) }), ("color", { str($0["color"]) }), ("tagline", { str($0["tagline"]) })]),
            "account_groups": try table("SELECT * FROM account_groups ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("name", { str($0["name"]) }), ("sort_order", { .int($0["sort_order"]) })]),
            "accounts": try table("SELECT * FROM accounts ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("group_id", { str($0["group_id"]) }),
                ("name", { str($0["name"]) }), ("type", { str($0["type"]) }), ("currency", { str($0["currency"]) }),
                ("current_balance", { numStr($0["current_balance"]) }), ("sort_order", { .int($0["sort_order"]) }),
                ("include_in_net_worth", { .int($0["include_in_net_worth"]) }), ("is_active", { .int($0["is_active"]) }),
                ("archived", { .bool(($0["archived_at"] as String?) != nil) })]),
            "categories": try table("SELECT * FROM categories ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("parent_id", { str($0["parent_id"]) }),
                ("name", { str($0["name"]) }), ("kind", { str($0["kind"]) }), ("system", { str($0["system"]) }), ("sort_order", { .int($0["sort_order"]) })]),
            "counterparties": try table("SELECT * FROM counterparties ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("name", { str($0["name"]) }), ("is_verified", { .int($0["is_verified"]) })]),
            "tags": try table("SELECT * FROM tags ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("name", { str($0["name"]) }), ("color", { str($0["color"]) })]),
            "budgets": try table("SELECT * FROM budgets ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("group_id", { str($0["group_id"]) }),
                ("name", { str($0["name"]) }), ("kind", { str($0["kind"]) }), ("amount", { numStr($0["amount"]) }),
                ("saved", { numStr($0["saved"]) }), ("frequency", { str($0["frequency"]) }), ("start_date", { str($0["start_date"]) }),
                ("end_date", { str($0["end_date"]) }), ("is_recurring", { .int($0["is_recurring"]) }), ("rollover", { .int($0["rollover"]) }),
                ("account_ids", { str($0["account_ids"]) }), ("category_ids", { str($0["category_ids"]) }),
                ("warning_pct", { numStr($0["warning_pct"]) }), ("pending_amount", { numStr($0["pending_amount"]) })]),
            "budget_groups": try table("SELECT * FROM budget_groups ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("name", { str($0["name"]) }), ("sort_order", { .int($0["sort_order"]) })]),
            "holdings": try table("SELECT * FROM holdings ORDER BY id", [
                ("id", { str($0["id"]) }), ("account_id", { str($0["account_id"]) }), ("symbol", { str($0["symbol"]) }),
                ("shares", { numStr($0["shares"]) }), ("cost_basis", { numStr($0["cost_basis"]) }), ("currency", { str($0["currency"]) }), ("last_price", { numStr($0["last_price"]) })]),
            "exchange_rates": try table("SELECT * FROM exchange_rates ORDER BY date, currency", [
                ("date", { str($0["date"]) }), ("currency", { str($0["currency"]) }), ("rate", { numStr($0["rate"]) }), ("source", { str($0["source"]) })]),
            "scheduled_templates": try table("SELECT * FROM scheduled_templates ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("name", { str($0["name"]) }), ("kind", { str($0["kind"]) }),
                ("amount", { numStr($0["amount"]) }), ("frequency", { str($0["frequency"]) }), ("day_of_month", { .int($0["day_of_month"]) }),
                ("account_id", { str($0["account_id"]) }), ("from_account_id", { str($0["from_account_id"]) }),
                ("start_date", { str($0["start_date"]) }), ("is_active", { .int($0["is_active"]) }), ("splits_enabled", { .int($0["splits_enabled"]) })]),
            "rules": try table("SELECT * FROM rules ORDER BY id", [
                ("id", { str($0["id"]) }), ("ledger_id", { str($0["ledger_id"]) }), ("priority", { .int($0["priority"]) }),
                ("condition", { parseJSON($0["condition"]) }), ("actions", { parseJSON($0["actions"]) }), ("is_active", { .int($0["is_active"]) })]),
            "app_state": try table("SELECT * FROM app_state ORDER BY key", [
                ("key", { str($0["key"]) }), ("value", { str($0["value"]) })]),
        ])
    }
}
