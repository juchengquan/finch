import Foundation
import GRDB

// The double-entry write chokepoint — port of lib/db/core/entries.ts. This is
// the single insert path for entries + postings: resolve legs → auto-balance →
// (counterparty) → FX residue → validate shape → insert + seal in a SAVEPOINT.
//
// SCOPE: the full posting path including the rules-engine branch (applyRules) on
// income/expense/refund insert. DEFERRED: the cross-currency `rateToHub`
// derived-rate insert / static fallback — single-currency entries (currency ==
// base) take the identity FX path. The deferral is marked inline.

public enum Entries {
    public enum Kind: String, Sendable { case opening, income, expense, transfer, adjustment, refund }
    public enum Status: String, Sendable { case pending, confirmed }

    static func newId(_ prefix: String) -> String {
        let ts = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let rand = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4).lowercased()
        return "\(prefix)-\(ts)-\(rand)"
    }
    static func r2(_ n: Double) -> Double { (n * 100).rounded() / 100 }

    // MARK: system (equity) categories

    public struct SystemCategoryIds: Sendable {
        public let opening: String
        public let adjustment: String
        public let fx: String
    }
    private static let systemCategories: [(system: String, name: String)] = [
        ("opening", "Opening balance"), ("adjustment", "Balance adjustment"), ("fx", "FX gain/loss"),
    ]

    /// Idempotently seed the three equity system categories for a ledger and
    /// return their ids (resolved by the `system` marker, rename-safe).
    @discardableResult
    public static func ensureSystemCategories(_ db: Database, _ ledgerId: String) throws -> SystemCategoryIds {
        var ids: [String: String] = [:]
        for (i, sc) in systemCategories.enumerated() {
            if let existing = try String.fetchOne(db, sql:
                "SELECT id FROM categories WHERE ledger_id = ? AND system = ?", arguments: [ledgerId, sc.system]) {
                ids[sc.system] = existing; continue
            }
            let id = newId("cat")
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at)
                VALUES (?,?,NULL,?,'equity',NULL,NULL,?,?,datetime('now'),datetime('now'))
                """, arguments: [id, ledgerId, sc.name, 9000 + i, sc.system])
            ids[sc.system] = id
        }
        return SystemCategoryIds(opening: ids["opening"]!, adjustment: ids["adjustment"]!, fx: ids["fx"]!)
    }

    // MARK: leg inputs

    public struct AccountLeg: Sendable {
        public var accountId: String
        public var amount: Double          // signed, account currency
        public var amountBase: Double?
        public var exchangeRate: Double?
        public var memo: String?
        public var id: String?             // preserve the posting id across a rebuild
        public var origAmount: Double?     // foreign-currency entry: amount as entered
        public var origCurrency: String?   // …and the currency it was entered in
        public var clearedAt: String?      // reconcile mark — preserved across rebuilds
        public init(accountId: String, amount: Double, amountBase: Double? = nil,
                    exchangeRate: Double? = nil, memo: String? = nil, id: String? = nil,
                    origAmount: Double? = nil, origCurrency: String? = nil, clearedAt: String? = nil) {
            self.accountId = accountId; self.amount = amount; self.amountBase = amountBase
            self.exchangeRate = exchangeRate; self.memo = memo; self.id = id
            self.origAmount = origAmount; self.origCurrency = origCurrency; self.clearedAt = clearedAt
        }
    }
    public struct CategoryLeg: Sendable {
        public var categoryId: String?
        public var amountBase: Double      // signed, ledger base
        public var memo: String?
        public var id: String?
        public init(categoryId: String?, amountBase: Double, memo: String? = nil, id: String? = nil) {
            self.categoryId = categoryId; self.amountBase = amountBase; self.memo = memo; self.id = id
        }
    }
    public enum Leg: Sendable { case account(AccountLeg), category(CategoryLeg) }

    struct ResolvedLeg {
        var id: String
        var accountId: String?
        var categoryId: String?
        var amount: Double
        var currency: String
        var amountBase: Double
        var exchangeRate: Double
        var memo: String?
        var origAmount: Double? = nil
        var origCurrency: String? = nil
        var clearedAt: String? = nil
    }

    /// `autoBalanceCategoryId`: `.none` = don't add; `.category(id?)` = append one
    /// category leg that exactly negates the account legs (id nil = uncategorized).
    public enum AutoBalance: Sendable { case none, category(String?) }

    public struct NewEntry: Sendable {
        public var id: String?
        public var ledgerId: String
        public var date: String
        public var time: String?
        public var description: String
        public var kind: Kind
        public var status: Status?
        public var legs: [Leg]
        public var autoBalance: AutoBalance
        public var notes: String?
        /// nil → resolve a counterparty from the description; the resolver returns
        /// nil when nothing matches (so "no counterparty" still works).
        public var counterpartyId: String?
        public var refundedEntryId: String?
        public var sourceTemplateId: String?
        public var timestamp: String?
        public var skipRules: Bool
        public init(id: String? = nil, ledgerId: String, date: String, time: String? = nil,
                    description: String, kind: Kind, status: Status? = nil, legs: [Leg],
                    autoBalance: AutoBalance = .none, notes: String? = nil, counterpartyId: String? = nil,
                    refundedEntryId: String? = nil, sourceTemplateId: String? = nil,
                    timestamp: String? = nil, skipRules: Bool = false) {
            self.id = id; self.ledgerId = ledgerId; self.date = date; self.time = time
            self.description = description; self.kind = kind; self.status = status; self.legs = legs
            self.autoBalance = autoBalance; self.notes = notes; self.counterpartyId = counterpartyId
            self.refundedEntryId = refundedEntryId; self.sourceTemplateId = sourceTemplateId
            self.timestamp = timestamp; self.skipRules = skipRules
        }
    }

    // MARK: helpers

    private static func categoryLeg(_ id: String?, _ categoryId: String?, _ amountBase: Double,
                                    _ base: String, _ memo: String?) -> ResolvedLeg {
        ResolvedLeg(id: id ?? newId("p"), accountId: nil, categoryId: categoryId,
                    amount: amountBase, currency: base, amountBase: amountBase, exchangeRate: 1, memo: memo)
    }

    private static func ledgerBase(_ db: Database, _ ledgerId: String) throws -> String {
        guard let b = try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id = ?",
                                          arguments: [ledgerId]) else {
            throw I18nError("error.notFound.ledger", [:], "Ledger not found")
        }
        return b
    }

    /// USD-hub FX (HUB_CURRENCY = "USD"). Verbatim port of the web's
    /// queries/rates.ts: cross-rate via the hub, with `rateToHub` doing the
    /// on-or-before → on-or-after → static-fallback lookup + write-through of the
    /// resolved rate. Single-currency (currency == base) returns identity.
    static func convertToBase(_ db: Database, _ native: Double, _ currency: String,
                              _ base: String, _ date: String) throws -> (amountBase: Double, rate: Double) {
        if currency == base { return (native, 1) }
        let rc = try rateToHub(db, currency, date)
        let rb = try rateToHub(db, base, date)
        let rate = rb != 0 ? rc / rb : 1
        return (r2(native * rate), (rate * 1e6).rounded() / 1e6)
    }

    /// Static last-resort USD-per-1-unit map (web FALLBACK_USD_PER_UNIT) — used
    /// only when the rates table has no row for a currency, so a fresh/empty DB
    /// still produces a value.
    private static let fallbackUsdPerUnit: [String: Double] = [
        "USD": 1, "EUR": 1.087, "GBP": 1.266, "JPY": 0.0064, "SGD": 0.741, "CNY": 0.138,
    ]

    /// USD-per-1-unit of `currency` at `date`: exact/on-or-before → on-or-after →
    /// static fallback. When no exact-date row exists, the resolved rate is
    /// pinned under `date` (source 'derived', INSERT OR IGNORE so a user-set rate
    /// is never clobbered) — making every locked conversion reproducible.
    private static func rateToHub(_ db: Database, _ currency: String, _ date: String) throws -> Double {
        if currency == "USD" { return 1 }
        let before = try Row.fetchOne(db, sql:
            "SELECT date AS d, rate AS r FROM exchange_rates WHERE currency = ? AND date <= ? ORDER BY date DESC LIMIT 1",
            arguments: [currency, date])
        if let before, (before["d"] as String) == date { return before["r"] }   // exact → no write-through
        let rate: Double
        if let before {
            rate = before["r"]
        } else if let after = try Double.fetchOne(db, sql:
            "SELECT rate FROM exchange_rates WHERE currency = ? AND date >= ? ORDER BY date ASC LIMIT 1",
            arguments: [currency, date]) {
            rate = after
        } else {
            rate = fallbackUsdPerUnit[currency] ?? 1
        }
        try db.execute(sql: "INSERT OR IGNORE INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, ?, 'derived')",
                       arguments: [date, currency, rate])
        return rate
    }

    static func resolveCounterpartyIdByName(_ db: Database, _ ledgerId: String, _ name: String) throws -> String? {
        try String.fetchOne(db, sql:
            "SELECT id FROM counterparties WHERE ledger_id = ? AND name = ? COLLATE NOCASE LIMIT 1",
            arguments: [ledgerId, name])
    }

    private static func resolveLegs(_ db: Database, _ ledgerId: String, _ date: String,
                                    _ base: String, _ inputs: [Leg]) throws -> [ResolvedLeg] {
        var legs: [ResolvedLeg] = []
        for leg in inputs {
            switch leg {
            case .account(let a):
                guard let acct = try Row.fetchOne(db, sql:
                    "SELECT currency, ledger_id FROM accounts WHERE id = ?", arguments: [a.accountId]) else {
                    throw I18nError("error.notFound.account", [:], "Account not found")
                }
                let acctLedger: String = acct["ledger_id"]
                if acctLedger != ledgerId { throw I18nError("error.account.differentLedger", [:], "Account is in a different ledger") }
                let currency: String = acct["currency"]
                var amountBase = a.amountBase
                var rate = a.exchangeRate
                if amountBase == nil || rate == nil {
                    let conv = try convertToBase(db, a.amount, currency, base, date)
                    amountBase = conv.amountBase; rate = conv.rate
                }
                legs.append(ResolvedLeg(id: a.id ?? newId("p"), accountId: a.accountId, categoryId: nil,
                    amount: r2(a.amount), currency: currency, amountBase: r2(amountBase!),
                    exchangeRate: rate!, memo: a.memo,
                    origAmount: a.origAmount.map(r2), origCurrency: a.origCurrency, clearedAt: a.clearedAt))
            case .category(let c):
                if let cid = c.categoryId {
                    guard let catLedger = try String.fetchOne(db, sql:
                        "SELECT ledger_id FROM categories WHERE id = ?", arguments: [cid]) else {
                        throw I18nError("error.notFound.category", [:], "Category not found")
                    }
                    if catLedger != ledgerId { throw I18nError("error.category.differentLedger", [:], "Category is in a different ledger") }
                }
                legs.append(categoryLeg(c.id, c.categoryId, r2(c.amountBase), base, c.memo))
            }
        }
        return legs
    }

    /// Whatever Σ amount_base leaves becomes an explicit fx equity leg, so the
    /// entry balances to the cent (no tolerance).
    private static func appendResidue(_ db: Database, _ ledgerId: String, _ base: String,
                                      _ legs: inout [ResolvedLeg]) throws {
        let residue = r2(legs.reduce(0.0) { $0 + $1.amountBase })
        if abs(residue) >= 0.005 {
            let sys = try ensureSystemCategories(db, ledgerId)
            legs.append(categoryLeg(nil, sys.fx, r2(-residue), base, nil))
        }
    }

    private static func categoryMeta(_ db: Database, _ legs: [ResolvedLeg]) throws -> [String: (kind: String, system: String?)] {
        let ids = Array(Set(legs.compactMap { $0.categoryId }))
        if ids.isEmpty { return [:] }
        let ph = ids.map { _ in "?" }.joined(separator: ",")
        var out: [String: (kind: String, system: String?)] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, kind, system FROM categories WHERE id IN (\(ph))",
                                  arguments: StatementArguments(ids)) {
            out[r["id"]] = (r["kind"], r["system"])
        }
        return out
    }

    /// The kind label must match the postings shape (web `validateShape`).
    private static func validateShape(_ kind: Kind, _ legs: [ResolvedLeg],
                                      _ meta: [String: (kind: String, system: String?)]) throws {
        let acct = legs.filter { $0.accountId != nil }
        let cats = legs.filter { $0.accountId == nil }
        if legs.count < 2 || acct.count < 1 {
            throw I18nError("error.entry.minPostings", [:], "An entry needs at least two postings including an account leg")
        }
        func sysOf(_ l: ResolvedLeg) -> String? { l.categoryId.flatMap { meta[$0]?.system } }
        func isEquity(_ l: ResolvedLeg) -> Bool { l.categoryId != nil && meta[l.categoryId!]?.kind == "equity" }
        let equity = cats.filter(isEquity)
        let plain = cats.filter { !isEquity($0) }

        switch kind {
        case .transfer:
            if acct.count != 2 { throw I18nError("error.transfer.twoLegs", [:], "A transfer has exactly two account legs") }
            if !plain.isEmpty { throw I18nError("error.transfer.noCategory", [:], "A transfer has no category leg") }
            if equity.contains(where: { sysOf($0) != "fx" }) { throw I18nError("error.transfer.fxOnly", [:], "Only the FX residue may balance a transfer") }
        case .opening, .adjustment:
            let want = kind == .opening ? "opening" : "adjustment"
            let ok = acct.count == 1 && plain.isEmpty
                && equity.contains(where: { sysOf($0) == want })
                && equity.allSatisfy { sysOf($0) == want || sysOf($0) == "fx" }
            if !ok { throw I18nError("error.entry.equityShape", ["kind": kind.rawValue], "An \(kind.rawValue) entry is one account leg against the \(want) equity category") }
        default: // income / expense / refund
            if acct.count != 1 { throw I18nError("error.entry.oneAccountLeg", ["kind": kind.rawValue], "A \(kind.rawValue) entry has exactly one account leg") }
            if plain.count < 1 { throw I18nError("error.entry.needCategory", ["kind": kind.rawValue], "A \(kind.rawValue) entry needs a category leg") }
            if equity.contains(where: { sysOf($0) != "fx" }) { throw I18nError("error.entry.noDirectEquity", [:], "Equity categories cannot be booked directly") }
            if kind == .refund && acct[0].amount <= 0 { throw I18nError("error.refund.positive", [:], "A refund must be positive") }
        }
    }

    /// Double-submit backstop hash; nil when time is nil (parity with the web).
    static func dedupHash(_ date: String, _ time: String?, _ description: String, _ legs: [ResolvedLeg]) -> String? {
        guard let time else { return nil }
        let acct = legs.filter { $0.accountId != nil }
            .map { "\($0.accountId!):\(String(format: "%.2f", $0.amount))" }
            .sorted().joined(separator: ",")
        return Pack.sha256Hex(Data("\(date)|\(time)|\(description)|\(acct)".utf8))
    }

    private static func insertPostings(_ db: Database, _ entryId: String, _ legs: [ResolvedLeg]) throws {
        for (i, l) in legs.enumerated() {
            try db.execute(sql: """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,orig_amount,orig_currency,memo,cleared_at,sort_order)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, arguments: [l.id, entryId, l.accountId, l.categoryId, l.amount, l.currency,
                                 l.amountBase, l.exchangeRate, l.origAmount, l.origCurrency, l.memo, l.clearedAt, i])
        }
    }

    // MARK: postEntry

    @discardableResult
    public static func postEntry(_ db: Database, _ e: NewEntry) throws -> String {
        let entryId = e.id ?? newId("e")
        let ts = e.timestamp ?? ISO8601DateFormatter().string(from: Date())
        let status = e.status ?? .confirmed
        let base = try ledgerBase(db, e.ledgerId)

        var legs = try resolveLegs(db, e.ledgerId, e.date, base, e.legs)
        if case .category(let autoCat) = e.autoBalance {
            let acctSum = r2(legs.filter { $0.accountId != nil }.reduce(0.0) { $0 + $1.amountBase })
            legs.append(categoryLeg(nil, autoCat, r2(-acctSum), base, nil))
        }

        // nil → resolve a counterparty from the description (resolver returns nil
        // when nothing matches).
        var description = e.description
        var notes = e.notes
        var kind = e.kind
        var counterpartyId: String? = try e.counterpartyId ?? resolveCounterpartyIdByName(db, e.ledgerId, e.description)
        var appliedRuleIds: [String]? = nil
        var tagIdsAdd: [String]? = nil
        var reviewedAt: String? = nil

        // Rules engine — income/expense/refund only, mirroring the web's hook.
        let ruled: Set<Kind> = [.income, .expense, .refund]
        if !e.skipRules && ruled.contains(kind) {
            let rules = try Rules.activeRules(db, e.ledgerId)
            if !rules.isEmpty, let acctLeg = legs.first(where: { $0.accountId != nil }) {
                let firstCat = legs.first(where: { $0.accountId == nil })
                let synthetic = Tx(
                    id: entryId, merchant: description, category: firstCat?.categoryId,
                    amount: acctLeg.amountBase, account: acctLeg.accountId!, date: e.date,
                    pending: status == .pending, ledgerId: e.ledgerId, currency: acctLeg.currency,
                    nativeAmount: acctLeg.amount, time: e.time, kind: kind.rawValue,
                    counterpartyId: counterpartyId, tags: [], note: notes,
                    sourceTemplateId: e.sourceTemplateId, refundedTransactionId: e.refundedEntryId)
                let patch = RulesEngine.applyRules(synthetic, rules)
                if !patch.appliedRuleIds.isEmpty {
                    if let m = patch.merchant { description = m }
                    if let n = patch.note { notes = n }
                    if let k = patch.kind, let kk = Kind(rawValue: k), ruled.contains(kk) { kind = kk }
                    if case .set(let cp) = patch.counterpartyId { counterpartyId = cp }
                    if case .set(let cat) = patch.categoryId, let i = legs.firstIndex(where: { $0.accountId == nil }) {
                        legs[i].categoryId = cat
                    }
                    if let splits = patch.splits, splits.count >= 2 {
                        // Replace category legs with fraction-derived ones over the
                        // account leg; the last split absorbs the rounding remainder
                        // in BOTH native and base space (else r2 drift mints a phantom
                        // sys:fx residue on cross-currency entries).
                        let ratio = acctLeg.amount != 0 ? acctLeg.amountBase / acctLeg.amount : 1
                        legs.removeAll { $0.accountId == nil }
                        var remaining = acctLeg.amount
                        var remainingBase = acctLeg.amountBase
                        for (i, s) in splits.enumerated() {
                            let isLast = i == splits.count - 1
                            let portion = isLast ? r2(remaining) : r2(acctLeg.amount * s.fraction)
                            remaining = r2(remaining - portion)
                            let catBase = isLast ? r2(-remainingBase) : r2(-portion * ratio)
                            remainingBase = r2(remainingBase + catBase)
                            legs.append(categoryLeg(nil, s.categoryId, catBase, base, s.description))
                        }
                    }
                    if patch.reviewed { reviewedAt = ts }
                    if let t = patch.tagIdsAdd, !t.isEmpty { tagIdsAdd = t }
                    appliedRuleIds = patch.appliedRuleIds
                }
            }
        }

        try appendResidue(db, e.ledgerId, base, &legs)
        try validateShape(kind, legs, try categoryMeta(db, legs))

        let sp = "pe_\(newId(""))".replacingOccurrences(of: "-", with: "")
        try db.execute(sql: "SAVEPOINT \(sp)")
        do {
            let appliedJson = appliedRuleIds.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) } ?? nil
            try db.execute(sql: """
                INSERT INTO entries (id,ledger_id,date,time,description,kind,status,confirmed_at,counterparty_id,refunded_entry_id,source_template_id,notes,applied_rule_ids,reviewed_at,dedup_hash,sealed,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?)
                """, arguments: [entryId, e.ledgerId, e.date, e.time, description, kind.rawValue, status.rawValue,
                                 status == .confirmed ? ts : nil, counterpartyId, e.refundedEntryId, e.sourceTemplateId,
                                 notes, appliedJson, reviewedAt, dedupHash(e.date, e.time, description, legs), ts, ts])
            try insertPostings(db, entryId, legs)
            // Rule-added tags land inside the same SAVEPOINT (the entry row exists).
            for tagId in tagIdsAdd ?? [] {
                try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)", arguments: [entryId, tagId])
            }
            try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = ?", arguments: [entryId])
            try db.execute(sql: "RELEASE \(sp)")
        } catch {
            try? db.execute(sql: "ROLLBACK TO \(sp)")
            try? db.execute(sql: "RELEASE \(sp)")
            throw error
        }
        return entryId
    }

    // MARK: postSimple

    public struct SimpleEntryInput: Sendable {
        public var ledgerId: String
        public var accountId: String
        public var amount: Double           // signed, account currency
        public var date: String
        public var description: String
        public var categoryId: String?
        public var kind: Kind?
        public var time: String?
        public var notes: String?
        public var status: Status?
        public var counterpartyId: String?
        public var skipRules: Bool
        public var id: String?
        public var sourceTemplateId: String?
        public init(ledgerId: String, accountId: String, amount: Double, date: String, description: String,
                    categoryId: String? = nil, kind: Kind? = nil, time: String? = nil, notes: String? = nil,
                    status: Status? = nil, counterpartyId: String? = nil, skipRules: Bool = false, id: String? = nil,
                    sourceTemplateId: String? = nil) {
            self.ledgerId = ledgerId; self.accountId = accountId; self.amount = amount; self.date = date
            self.description = description; self.categoryId = categoryId; self.kind = kind; self.time = time
            self.notes = notes; self.status = status; self.counterpartyId = counterpartyId
            self.skipRules = skipRules; self.id = id; self.sourceTemplateId = sourceTemplateId
        }
    }

    /// One account leg + one auto-balanced category leg — addTransaction's shape.
    /// Kind defaults to income/expense by sign.
    @discardableResult
    public static func postSimple(_ db: Database, _ s: SimpleEntryInput) throws -> String {
        let kind = s.kind ?? (s.amount > 0 ? Kind.income : Kind.expense)
        return try postEntry(db, NewEntry(
            id: s.id, ledgerId: s.ledgerId, date: s.date, time: s.time, description: s.description,
            kind: kind, status: s.status, legs: [.account(AccountLeg(accountId: s.accountId, amount: s.amount))],
            autoBalance: .category(s.categoryId), notes: s.notes, counterpartyId: s.counterpartyId,
            sourceTemplateId: s.sourceTemplateId, skipRules: s.skipRules))
    }

    /// Resolve a client Tx id (a posting id) — or an entry id — to its entry +
    /// primary account-leg posting. Mirrors `resolveEntryRef`.
    public struct EntryRef: Sendable { public let entryId: String; public let postingId: String?; public let accountId: String? }
    public static func resolveEntryRef(_ db: Database, _ id: String) throws -> EntryRef? {
        if let p = try Row.fetchOne(db, sql: "SELECT id, entry_id, account_id FROM postings WHERE id = ?", arguments: [id]) {
            return EntryRef(entryId: p["entry_id"], postingId: p["id"], accountId: p["account_id"])
        }
        if try Int.fetchOne(db, sql: "SELECT 1 FROM entries WHERE id = ?", arguments: [id]) == nil { return nil }
        let leg = try Row.fetchOne(db, sql:
            "SELECT id, account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order LIMIT 1",
            arguments: [id])
        return EntryRef(entryId: id, postingId: leg?["id"], accountId: leg?["account_id"])
    }

    /// Two account legs (from −amount, to +amount) + any FX residue — the
    /// double-entry transfer. Same-currency requires matching magnitudes.
    @discardableResult
    public static func postTransfer(_ db: Database, ledgerId: String? = nil, fromAccountId: String,
                                    toAccountId: String, fromAmount: Double, toAmount: Double? = nil,
                                    date: String, time: String? = nil, note: String? = nil,
                                    sourceTemplateId: String? = nil, id: String? = nil,
                                    timestamp: String? = nil) throws -> String {
        let fromAmt = abs(fromAmount)
        if fromAmt == 0 { throw I18nError("error.transfer.amountGt0", [:], "Transfer amount must be greater than 0") }
        if fromAccountId == toAccountId { throw I18nError("error.transfer.sameAccount", [:], "Pick two different accounts") }
        guard let from = try Row.fetchOne(db, sql: "SELECT ledger_id, currency, name FROM accounts WHERE id = ?", arguments: [fromAccountId]),
              let to = try Row.fetchOne(db, sql: "SELECT currency, name FROM accounts WHERE id = ?", arguments: [toAccountId]) else {
            throw I18nError("error.notFound.account", [:], "Account not found")
        }
        let lid = ledgerId ?? (from["ledger_id"] as String)
        let fromCcy: String = from["currency"], toCcy: String = to["currency"]
        let toAmt: Double
        if let ta = toAmount {
            toAmt = abs(ta)
            if !(toAmt > 0) { throw I18nError("error.transfer.receivedGt0", [:], "Received amount must be greater than 0") }
            if fromCcy == toCcy && abs(toAmt - fromAmt) > 0.005 {
                throw I18nError("error.transfer.sameCurrencyMismatch", [:], "Same-currency transfer amounts must match")
            }
        } else {
            toAmt = try convertToBase(db, fromAmt, fromCcy, toCcy, date).amountBase
        }
        let fromName: String = from["name"], toName: String = to["name"]
        return try postEntry(db, NewEntry(
            id: id, ledgerId: lid, date: date, time: time, description: "Transfer", kind: .transfer,
            legs: [.account(AccountLeg(accountId: fromAccountId, amount: -fromAmt, memo: "Transfer to \(toName)")),
                   .account(AccountLeg(accountId: toAccountId, amount: toAmt, memo: "Transfer from \(fromName)"))],
            notes: note, sourceTemplateId: sourceTemplateId, timestamp: timestamp, skipRules: true))
    }

    /// One account leg against the `adjustment` equity category — the manual
    /// balance-reconciliation entry. Zero/sub-cent delta is a silent no-op.
    @discardableResult
    public static func postAdjustment(_ db: Database, ledgerId: String, accountId: String, delta: Double,
                                      date: String, note: String? = nil, source: String? = nil,
                                      id: String? = nil, timestamp: String? = nil) throws -> String? {
        if r2(delta) == 0 { return nil }
        let sys = try ensureSystemCategories(db, ledgerId)
        return try postEntry(db, NewEntry(
            id: id, ledgerId: ledgerId, date: date,
            description: source == "reconcile" ? "Reconciliation adjustment" : "Balance adjustment",
            kind: .adjustment, legs: [.account(AccountLeg(accountId: accountId, amount: r2(delta)))],
            autoBalance: .category(sys.adjustment), notes: note, timestamp: timestamp, skipRules: true))
    }

    /// The opening-balance entry (`open-<accountId>`), one account leg against
    /// the `opening` equity category. Idempotent; zero amount → no entry (nil).
    /// NOTE: the web marks the opening leg cleared (reconcile anchor); my
    /// simplified leg drops cleared_at (DEFERRED) — the balance is unaffected.
    @discardableResult
    public static func postOpening(_ db: Database, ledgerId: String, accountId: String, amount: Double,
                                   date: String, timestamp: String? = nil) throws -> String? {
        if r2(amount) == 0 { return nil }
        let id = "open-\(accountId)"
        if try Int.fetchOne(db, sql: "SELECT 1 FROM entries WHERE id = ?", arguments: [id]) != nil { return id }
        let sys = try ensureSystemCategories(db, ledgerId)
        let ts = timestamp ?? ISO8601DateFormatter().string(from: Date())
        return try postEntry(db, NewEntry(
            id: id, ledgerId: ledgerId, date: date, description: "Opening balance", kind: .opening,
            legs: [.account(AccountLeg(accountId: accountId, amount: r2(amount)))],
            autoBalance: .category(sys.opening), timestamp: ts, skipRules: true))
    }

    /// Delete the whole entry (postings cascade) then recompute touched accounts.
    @discardableResult
    public static func deleteEntry(_ db: Database, _ entryId: String) throws -> [String] {
        let accts = try String.fetchAll(db, sql:
            "SELECT DISTINCT account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL",
            arguments: [entryId]).sorted()
        try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [entryId])
        for id in accts { try recomputeAccountFromPostings(db, id) }
        return accts
    }

    // MARK: rebuildEntry (the edit path)

    /// A patch field: `.keep` (absent) vs `.set(value)` (present, incl. null).
    public enum Field<T: Sendable>: Sendable { case keep, set(T) }

    public struct EntryPatch: Sendable {
        public var date: Field<String> = .keep
        public var time: Field<String?> = .keep
        public var description: Field<String> = .keep
        public var kind: Field<Kind> = .keep
        public var notes: Field<String?> = .keep
        public var counterpartyId: Field<String?> = .keep
        public var refundedEntryId: Field<String?> = .keep
        public var status: Field<Status> = .keep
        public var legs: Field<[Leg]> = .keep
        public init() {}
    }

    private static func rowToResolved(_ r: Row) -> ResolvedLeg {
        ResolvedLeg(id: r["id"], accountId: r["account_id"], categoryId: r["category_id"],
                    amount: r["amount"], currency: r["currency"], amountBase: r["amount_base"],
                    exchangeRate: (r["exchange_rate"] as Double?) ?? 1, memo: r["memo"])
    }

    /// Unseal → patch header → (maybe) rewrite legs → reseal → recompute touched
    /// accounts. Mirrors the web `rebuildEntry`. Returns the touched account ids.
    @discardableResult
    public static func rebuildEntry(_ db: Database, _ entryId: String, _ patch: EntryPatch) throws -> [String] {
        guard let cur = try Row.fetchOne(db, sql: "SELECT * FROM entries WHERE id = ?", arguments: [entryId]) else { return [] }
        let oldLegRows = try Row.fetchAll(db, sql: "SELECT * FROM postings WHERE entry_id = ? ORDER BY sort_order", arguments: [entryId])
        var touched = Set(oldLegRows.compactMap { (r: Row) -> String? in r["account_id"] })

        let ledgerId: String = cur["ledger_id"]
        let base = try ledgerBase(db, ledgerId)
        let curDate: String = cur["date"]
        let curKind: String = cur["kind"]
        let curStatus: String = cur["status"]
        var date = curDate
        if case .set(let d) = patch.date { date = d }
        var kind = Kind(rawValue: curKind) ?? .expense
        if case .set(let k) = patch.kind { kind = k }
        let ts = ISO8601DateFormatter().string(from: Date())

        let dateChanged: Bool = { if case .set(let d) = patch.date { return d != curDate }; return false }()
        let legsProvided: Bool = { if case .set = patch.legs { return true }; return false }()
        let mustRebuildLegs = legsProvided || dateChanged

        let sp = "re_" + newId("x").replacingOccurrences(of: "-", with: "")
        try db.execute(sql: "SAVEPOINT \(sp)")
        do {
            try db.execute(sql: "UPDATE entries SET sealed = 0 WHERE id = ?", arguments: [entryId])

            var sets: [String] = []
            var bind: [DatabaseValueConvertible?] = []
            if case .set(let v) = patch.date { sets.append("date = ?"); bind.append(v) }
            if case .set(let v) = patch.time { sets.append("time = ?"); bind.append(v) }
            if case .set(let v) = patch.description { sets.append("description = ?"); bind.append(v) }
            if case .set(let v) = patch.kind { sets.append("kind = ?"); bind.append(v.rawValue) }
            if case .set(let v) = patch.notes { sets.append("notes = ?"); bind.append(v) }
            if case .set(let v) = patch.counterpartyId { sets.append("counterparty_id = ?"); bind.append(v) }
            if case .set(let v) = patch.refundedEntryId { sets.append("refunded_entry_id = ?"); bind.append(v) }
            if case .set(let v) = patch.status, v.rawValue != curStatus {
                sets.append("status = ?"); bind.append(v.rawValue)
                if v == .confirmed { sets.append("confirmed_at = ?"); bind.append(ts) } else { sets.append("confirmed_at = NULL") }
            }
            sets.append("updated_at = ?"); bind.append(ts); bind.append(entryId)
            try db.execute(sql: "UPDATE entries SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))

            var rebuiltLegs: [ResolvedLeg]? = nil
            if mustRebuildLegs {
                var inputs: [Leg]
                if case .set(let provided) = patch.legs {
                    inputs = provided
                } else {
                    let fxId = try String.fetchOne(db, sql: "SELECT id FROM categories WHERE ledger_id = ? AND system = 'fx'", arguments: [ledgerId])
                    inputs = oldLegRows.compactMap { r -> Leg? in
                        let catId: String? = r["category_id"]
                        if catId != nil && catId == fxId { return nil }
                        if let acctId: String = r["account_id"] {
                            return .account(AccountLeg(accountId: acctId, amount: r["amount"], memo: r["memo"], id: r["id"]))
                        }
                        return .category(CategoryLeg(categoryId: catId, amountBase: r["amount_base"], memo: r["memo"], id: r["id"]))
                    }
                }
                try db.execute(sql: "DELETE FROM postings WHERE entry_id = ?", arguments: [entryId])
                var resolved = try resolveLegs(db, ledgerId, date, base, inputs)
                if !legsProvided {
                    // date-only re-lock: scale kept category legs by newSum/oldSum.
                    let oldSum = oldLegRows.filter { ($0["account_id"] as String?) != nil }.reduce(0.0) { $0 + ($1["amount_base"] as Double) }
                    let newSum = resolved.filter { $0.accountId != nil }.reduce(0.0) { $0 + $1.amountBase }
                    let scale = oldSum != 0 ? newSum / oldSum : 1
                    for i in resolved.indices where resolved[i].accountId == nil {
                        resolved[i].amountBase = r2(resolved[i].amountBase * scale)
                        resolved[i].amount = resolved[i].amountBase
                    }
                }
                try appendResidue(db, ledgerId, base, &resolved)
                try validateShape(kind, resolved, try categoryMeta(db, resolved))
                try insertPostings(db, entryId, resolved)
                for l in resolved where l.accountId != nil { touched.insert(l.accountId!) }
                rebuiltLegs = resolved
            } else if case .set(let k) = patch.kind, k.rawValue != curKind {
                let current = oldLegRows.map(rowToResolved)
                try validateShape(kind, current, try categoryMeta(db, current))
            }

            // Re-stamp the dedup hash from the entry's EFFECTIVE content.
            var effTime: String? = cur["time"]
            if case .set(let t) = patch.time { effTime = t }
            var effDesc: String = (cur["description"] as String?) ?? ""
            if case .set(let d) = patch.description { effDesc = d }
            let hashLegs = rebuiltLegs ?? oldLegRows.map(rowToResolved)
            try db.execute(sql: "UPDATE entries SET dedup_hash = ? WHERE id = ?",
                           arguments: [dedupHash(date, effTime, effDesc, hashLegs), entryId])

            try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = ?", arguments: [entryId])
            try db.execute(sql: "RELEASE \(sp)")
        } catch {
            try? db.execute(sql: "ROLLBACK TO \(sp)")
            try? db.execute(sql: "RELEASE \(sp)")
            throw error
        }

        for id in touched.sorted() { try recomputeAccountFromPostings(db, id) }
        return touched.sorted()
    }

    /// Rebuild a confirmed account's cached balance from its postings.
    public static func recomputeAccountFromPostings(_ db: Database, _ accountId: String) throws {
        let total = try Double.fetchOne(db, sql: """
            SELECT COALESCE(SUM(p.amount), 0) FROM postings p JOIN entries e ON e.id = p.entry_id
             WHERE p.account_id = ? AND e.status = 'confirmed'
            """, arguments: [accountId]) ?? 0
        try db.execute(sql: "UPDATE accounts SET current_balance = ROUND(?, 2), updated_at = datetime('now') WHERE id = ?",
                       arguments: [total, accountId])
    }
}
