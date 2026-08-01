import Foundation
import GRDB

/// Mirror of the web's `lib/db/core/entries.ts::auditLedger` (`entries.ts:708-822`).
/// A read-only semantic sweep over the double-entry ledger returning the 10 typed
/// problem classes. Ported VERBATIM — same JOINs, same `ROUND(…,2)` arithmetic,
/// same `kind-shape` leg-counting, same `detail` strings.
public enum Audit {
    /// The 10 problem codes (the web's `AuditProblem.code` union). Raw value =
    /// the exact web code string.
    public enum Code: String, Codable, Sendable, CaseIterable {
        case unsealed         = "unsealed"
        case unbalanced       = "unbalanced"
        case tooFewLegs       = "too-few-legs"
        case noAccountLeg     = "no-account-leg"
        case currencyMismatch = "currency-mismatch"
        case crossLedger      = "cross-ledger"
        case baseIdentity     = "base-identity"
        case kindShape        = "kind-shape"
        case trialBalance     = "trial-balance"
        case balanceDrift     = "balance-drift"
    }

    /// One audit problem. Mirrors the web `AuditProblem` (`entries.ts:708`):
    /// `{ code, entryId?, detail }`. `entryId` is nil for `trial-balance` /
    /// `balance-drift` (ledger/account scoped). `detail` is the web's `detail`.
    public struct AuditProblem: Equatable, Hashable, Sendable, Codable {
        public let code: Code
        public let entryId: String?
        public let detail: String
        public init(code: Code, entryId: String? = nil, detail: String) {
            self.code = code; self.entryId = entryId; self.detail = detail
        }
    }

    /// Run all 10 checks (optionally scoped to one ledger). Empty array = clean.
    public static func run(on dbQueue: DatabaseQueue, ledgerId: String? = nil,
                           checkBalances: Bool = true) throws -> [AuditProblem] {
        try dbQueue.read { db in try run(on: db, ledgerId: ledgerId, checkBalances: checkBalances) }
    }

    /// The same checks against an open `Database` — callable inside a write
    /// transaction (e.g. the post-`changeLedgerBase` sweep, which must run before
    /// commit so a failed recompute rolls back).
    public static func run(on db: Database, ledgerId: String? = nil,
                           checkBalances: Bool = true) throws -> [AuditProblem] {
            var problems: [AuditProblem] = []
            // `${scope}` in the web: an `AND e.ledger_id = ?` tail when scoped.
            let scope = ledgerId != nil ? "AND e.ledger_id = ?" : ""
            let bind: StatementArguments = ledgerId != nil ? [ledgerId] : []

            // 1. unsealed
            for r in try Row.fetchAll(db, sql:
                "SELECT e.id FROM entries e WHERE e.sealed = 0 \(scope)", arguments: bind) {
                problems.append(AuditProblem(code: .unsealed, entryId: r["id"],
                    detail: "entry was never sealed (torn write)"))
            }
            // 2. unbalanced
            for r in try Row.fetchAll(db, sql: """
                SELECT e.id, ROUND(SUM(p.amount_base), 2) AS s FROM entries e JOIN postings p ON p.entry_id = e.id
                  WHERE 1=1 \(scope) GROUP BY e.id HAVING ROUND(SUM(p.amount_base), 2) != 0
                """, arguments: bind) {
                problems.append(AuditProblem(code: .unbalanced, entryId: r["id"],
                    detail: "postings sum to \(jsNum(r["s"])), not 0"))
            }
            // 3/4. too-few-legs / no-account-leg (one query, code chosen by a < 1)
            for r in try Row.fetchAll(db, sql: """
                SELECT e.id, COUNT(p.id) AS n, SUM(CASE WHEN p.account_id IS NOT NULL THEN 1 ELSE 0 END) AS a
                   FROM entries e LEFT JOIN postings p ON p.entry_id = e.id
                  WHERE 1=1 \(scope) GROUP BY e.id HAVING n < 2 OR a < 1
                """, arguments: bind) {
                let n: Int = r["n"]; let a: Int = r["a"]
                problems.append(AuditProblem(code: a < 1 ? .noAccountLeg : .tooFewLegs,
                    entryId: r["id"], detail: "\(n) postings, \(a) account legs"))
            }
            // 5. currency-mismatch
            for r in try Row.fetchAll(db, sql: """
                SELECT p.id, e.id AS eid FROM postings p JOIN entries e ON e.id = p.entry_id JOIN accounts a ON a.id = p.account_id
                  WHERE p.currency != a.currency \(scope)
                """, arguments: bind) {
                let pid: String = r["id"]
                problems.append(AuditProblem(code: .currencyMismatch, entryId: r["eid"],
                    detail: "posting \(pid) not in its account's currency"))
            }
            // 6. cross-ledger
            for r in try Row.fetchAll(db, sql: """
                SELECT p.id, e.id AS eid FROM postings p JOIN entries e ON e.id = p.entry_id
                   LEFT JOIN accounts a ON a.id = p.account_id
                   LEFT JOIN categories c ON c.id = p.category_id
                  WHERE ((p.account_id IS NOT NULL AND a.ledger_id != e.ledger_id)
                      OR (p.category_id IS NOT NULL AND c.ledger_id != e.ledger_id)) \(scope)
                """, arguments: bind) {
                let pid: String = r["id"]
                problems.append(AuditProblem(code: .crossLedger, entryId: r["eid"],
                    detail: "posting \(pid) references another ledger"))
            }
            // 7. base-identity
            for r in try Row.fetchAll(db, sql: """
                SELECT p.id, e.id AS eid FROM postings p JOIN entries e ON e.id = p.entry_id JOIN ledgers l ON l.id = e.ledger_id
                  WHERE p.currency = l.base_currency AND ROUND(p.amount - p.amount_base, 2) != 0 \(scope)
                """, arguments: bind) {
                let pid: String = r["id"]
                problems.append(AuditProblem(code: .baseIdentity, entryId: r["eid"],
                    detail: "posting \(pid): amount != amount_base in the base currency (I9)"))
            }
            // 8. kind-shape (I7): count leg shapes per entry, compare to the kind's contract
            for r in try Row.fetchAll(db, sql: """
                SELECT e.id, e.kind,
                       SUM(CASE WHEN p.account_id IS NOT NULL THEN 1 ELSE 0 END) AS acct,
                       SUM(CASE WHEN p.account_id IS NULL AND COALESCE(c.kind, '') != 'equity' THEN 1 ELSE 0 END) AS plain,
                       SUM(CASE WHEN COALESCE(c.kind, '') = 'equity' AND c.system = 'opening'    THEN 1 ELSE 0 END) AS eq_open,
                       SUM(CASE WHEN COALESCE(c.kind, '') = 'equity' AND c.system = 'adjustment' THEN 1 ELSE 0 END) AS eq_adj,
                       SUM(CASE WHEN COALESCE(c.kind, '') = 'equity' AND c.system = 'fx'         THEN 1 ELSE 0 END) AS eq_fx,
                       SUM(CASE WHEN p.account_id IS NOT NULL AND p.amount <= 0 THEN 1 ELSE 0 END) AS neg_acct
                  FROM entries e JOIN postings p ON p.entry_id = e.id LEFT JOIN categories c ON c.id = p.category_id
                  WHERE 1=1 \(scope) GROUP BY e.id
                """, arguments: bind) {
                let kind: String = r["kind"]
                let acct: Int = r["acct"]; let plain: Int = r["plain"]
                let eqOpen: Int = r["eq_open"]; let eqAdj: Int = r["eq_adj"]; let eqFx: Int = r["eq_fx"]
                let negAcct: Int = r["neg_acct"]
                // Broken into named sub-expressions: the single combined boolean
                // trips Swift's "unable to type-check in reasonable time" limit.
                let badTransfer = kind == "transfer" && (acct != 2 || plain > 0 || eqOpen + eqAdj > 0)
                let badOpening = kind == "opening" && (acct != 1 || plain > 0 || eqOpen < 1 || eqAdj > 0)
                let badAdjust = kind == "adjustment" && (acct != 1 || plain > 0 || eqAdj < 1 || eqOpen > 0)
                let badRefund = kind == "refund" && negAcct > 0
                // `acct >= 1` rather than `acct == 1`: one purchase may be paid from
                // several accounts (split tender). The written invariant I7 never
                // required a single account leg for income/expense/refund — only
                // transfer (exactly 2), opening/adjustment (exactly 1) — and the seal
                // trigger already guarantees at least one account leg exists.
                let badSimple = ["income", "expense", "refund"].contains(kind) && (acct < 1 || plain < 1 || eqOpen + eqAdj > 0)
                let bad = badTransfer || badOpening || badAdjust || badRefund || badSimple
                if bad {
                    problems.append(AuditProblem(code: .kindShape, entryId: r["id"],
                        detail: "kind=\(kind) but shape is acct=\(acct) plain=\(plain) eq=[\(eqOpen),\(eqAdj),\(eqFx)]"))
                }
            }
            // 9. trial-balance (per-ledger sum; JS filters s != 0 in code)
            for r in try Row.fetchAll(db, sql: """
                SELECT e.ledger_id AS lid, ROUND(SUM(p.amount_base), 2) AS s
                   FROM postings p JOIN entries e ON e.id = p.entry_id WHERE 1=1 \(scope) GROUP BY e.ledger_id
                """, arguments: bind) {
                let s: Double = r["s"]
                if s != 0 {
                    let lid: String = r["lid"]
                    problems.append(AuditProblem(code: .trialBalance, entryId: nil,
                        detail: "ledger \(lid) trial balance is \(jsNum(s)), not 0"))
                }
            }
            // 10. balance-drift (cached vs derived from confirmed postings)
            if checkBalances {
                let driftScope = ledgerId != nil ? "WHERE a.ledger_id = ?" : ""
                for r in try Row.fetchAll(db, sql: """
                    SELECT * FROM (
                      SELECT a.id, a.current_balance AS cached, ROUND(COALESCE((
                               SELECT SUM(p.amount) FROM postings p JOIN entries e ON e.id = p.entry_id
                                WHERE p.account_id = a.id AND e.status = 'confirmed'), 0), 2) AS derived
                        FROM accounts a \(driftScope)
                    ) WHERE ROUND(cached - derived, 2) != 0
                    """, arguments: bind) {
                    let id: String = r["id"]
                    problems.append(AuditProblem(code: .balanceDrift, entryId: nil,
                        detail: "account \(id): cached \(jsNum(r["cached"])) vs derived \(jsNum(r["derived"]))"))
                }
            }
            return problems
    }
}

/// Format a double the way JS `Number.toString` does in the web's `detail`
/// template literals: integers print without a decimal point (`-5`, not `-5.0`),
/// non-integers print their shortest round-tripping form. The audit's numbers
/// are `ROUND(…, 2)` results, so ≤ 2 decimals.
private func jsNum(_ d: Double) -> String {
    if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
    return String(d)
}
