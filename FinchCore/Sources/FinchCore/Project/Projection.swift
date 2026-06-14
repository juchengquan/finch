import Foundation
import GRDB

/// Mirror of the web's `lib/db/state.ts::projectState` (the `Tx[]` projection).
/// One Tx per account-leg posting (opening excluded), enriched with category /
/// splits / tags from the other legs, then the counterparty-name override.
/// With `ledgerId == nil` projects ALL ledgers (matches the web full
/// projection — the selectors then filter client-side). The app passes the
/// active ledger so a single write only re-projects that ledger's transactions
/// (every mutation targets the active ledger), not every ledger's.
public enum Projection {
    private static func selectSQL(scopedToLedger: Bool) -> String {
        """
        SELECT p.id AS pid, p.account_id AS p_account, p.amount AS p_amount, p.amount_base AS p_base,
               p.currency AS p_ccy, p.orig_amount, p.orig_currency, p.cleared_at AS p_cleared, p.memo AS p_memo,
               e.id AS eid, e.ledger_id, e.date, e.time, e.description, e.kind, e.status, e.counterparty_id,
               e.refunded_entry_id, e.source_template_id, e.notes, e.applied_rule_ids, e.reviewed_at,
               e.created_at AS e_created_at
          FROM postings p JOIN entries e ON e.id = p.entry_id
         WHERE p.account_id IS NOT NULL AND e.kind != 'opening'
         \(scopedToLedger ? "AND e.ledger_id = ?" : "")
         ORDER BY e.date DESC, e.time DESC, e.created_at DESC, p.sort_order
        """
    }

    public static func run(dbQueue: DatabaseQueue, ledgerId: String? = nil) throws -> [Tx] {
        try dbQueue.read { db in
            let sql = selectSQL(scopedToLedger: ledgerId != nil)
            let args: StatementArguments = ledgerId.map { [$0] } ?? []
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            var txns = rows.map(mapRow)
            let entryIds: [String] = rows.map { $0["eid"] }
            try enrichLegTxs(db, &txns, entryIds)
            // Counterparty-name override: canonical name follows catalog renames.
            let cpNames = try Row.fetchAll(db, sql: "SELECT id, name FROM counterparties")
                .reduce(into: [String: String]()) { $0[$1["id"]] = $1["name"] }
            for i in txns.indices {
                if let cp = txns[i].counterpartyId, let canonical = cpNames[cp] { txns[i].merchant = canonical }
            }
            return txns
        }
    }

    /// The 15-table CANONICAL_TABLES (metadata.ts:47) — the `db.row_counts` keys.
    public static let canonicalTables = [
        "ledgers", "account_groups", "accounts", "categories", "counterparties",
        "entries", "postings", "entry_tags", "entry_attachments", "budgets",
        "tags", "scheduled_templates", "scheduled_splits", "exchange_rates", "app_state",
    ]

    public static func rowCounts(dbQueue: DatabaseQueue) throws -> [String: Int] {
        try dbQueue.read { db in
            var out: [String: Int] = [:]
            for t in canonicalTables {
                out[t] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(t)") ?? 0
            }
            return out
        }
    }

    // MARK: row → partial Tx (state.ts:59-92)

    private static func mapRow(_ r: Row) -> Tx {
        let amount: Double = r["p_base"]
        let pAmount: Double = r["p_amount"]
        let origAmount: Double? = r["orig_amount"]
        let origCcy: String? = r["orig_currency"]
        let pCcy: String? = r["p_ccy"]
        let memo: String? = r["p_memo"]
        let description: String? = r["description"]
        let status: String = r["status"]
        var appliedRuleIds: [String]? = nil
        if let raw: String = r["applied_rule_ids"], let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            appliedRuleIds = arr
        }
        return Tx(
            id: r["pid"], merchant: memo ?? description ?? "", category: nil,
            amount: amount, account: r["p_account"], date: r["date"],
            pending: status == "pending", ledgerId: r["ledger_id"],
            currency: origCcy ?? pCcy, nativeAmount: origAmount ?? pAmount, time: r["time"],
            kind: r["kind"], transferGroupId: nil, counterpartyId: r["counterparty_id"],
            splits: nil, tags: nil, note: r["notes"],
            sourceTemplateId: r["source_template_id"], refundedTransactionId: r["refunded_entry_id"],
            clearedAt: r["p_cleared"], appliedRuleIds: appliedRuleIds, reviewedAt: r["reviewed_at"])
    }

    // MARK: enrichLegTxs (queries/transactions.ts:99) — category/splits/tags + transfer + refund

    private struct Leg { let id: String; let categoryId: String?; let amountBase: Double; let sortOrder: Int }

    private static func enrichLegTxs(_ db: Database, _ rows: inout [Tx], _ entryIds: [String]) throws {
        if entryIds.isEmpty { return }
        let uniq = Array(Set(entryIds))
        let ph = uniq.map { _ in "?" }.joined(separator: ",")
        let args = StatementArguments(uniq)

        var catsByEntry: [String: [Leg]] = [:]
        for r in try Row.fetchAll(db, sql: """
            SELECT p.id, p.entry_id, p.category_id, p.amount_base, p.sort_order
              FROM postings p
             WHERE p.entry_id IN (\(ph)) AND p.account_id IS NULL
               AND (p.category_id IS NULL OR (SELECT c.kind FROM categories c WHERE c.id = p.category_id) != 'equity')
             ORDER BY p.entry_id, p.sort_order
            """, arguments: args) {
            let eid: String = r["entry_id"]
            catsByEntry[eid, default: []].append(Leg(id: r["id"], categoryId: r["category_id"],
                                                     amountBase: r["amount_base"], sortOrder: r["sort_order"]))
        }
        var acctCount: [String: Int] = [:]
        for r in try Row.fetchAll(db, sql:
            "SELECT p.entry_id, COUNT(*) AS n FROM postings p WHERE p.entry_id IN (\(ph)) AND p.account_id IS NOT NULL GROUP BY p.entry_id",
            arguments: args) {
            acctCount[r["entry_id"]] = r["n"]
        }
        var tagsByEntry: [String: [String]] = [:]
        for r in try Row.fetchAll(db, sql:
            "SELECT et.entry_id, et.tag_id FROM entry_tags et WHERE et.entry_id IN (\(ph))", arguments: args) {
            tagsByEntry[r["entry_id"], default: []].append(r["tag_id"])
        }
        // refund resolution: raw entry id → first account-posting id (by sort_order)
        let refEntryIds = rows.compactMap { $0.refundedTransactionId }
        var refPostingMap: [String: String] = [:]
        if !refEntryIds.isEmpty {
            let refUniq = Array(Set(refEntryIds))
            let refPh = refUniq.map { _ in "?" }.joined(separator: ",")
            for r in try Row.fetchAll(db, sql:
                "SELECT p.entry_id, p.id AS pid FROM postings p WHERE p.entry_id IN (\(refPh)) AND p.account_id IS NOT NULL ORDER BY p.sort_order",
                arguments: StatementArguments(refUniq)) {
                let eid: String = r["entry_id"]
                if refPostingMap[eid] == nil { refPostingMap[eid] = r["pid"] }
            }
        }

        for i in rows.indices {
            let eid = entryIds[i]
            let legs = catsByEntry[eid] ?? []
            if legs.isEmpty { rows[i].category = nil }
            else if legs.count == 1 { rows[i].category = legs[0].categoryId }
            else {
                var dominant = legs[0]
                for l in legs.dropFirst() where abs(l.amountBase) > abs(dominant.amountBase) { dominant = l }
                rows[i].category = dominant.categoryId
                rows[i].splits = legs.sorted { $0.sortOrder < $1.sortOrder }.map {
                    TxSplit(id: $0.id, categoryId: $0.categoryId, amount: -$0.amountBase, amountBase: -$0.amountBase, description: nil)
                }
            }
            if (acctCount[eid] ?? 1) >= 2 { rows[i].transferGroupId = eid }
            if let ref = rows[i].refundedTransactionId, let resolved = refPostingMap[ref] {
                rows[i].refundedTransactionId = resolved
            }
            if let tags = tagsByEntry[eid], !tags.isEmpty { rows[i].tags = tags }
        }
    }
}
