import Foundation
import GRDB

// Transactions domain handlers — port of lib/db/domain/transactions/mutations.ts.
// Full posting-engine coverage: add/update/delete, splits, adjust/reconcile,
// bulk-recategorize, confirm, tags, attachments — all wired to the engine, with
// budget-rollover invalidation (Budgets.invalidateForEntry) on the money paths.
// addTransaction is wrapped in Dedup.wrap so a UNIQUE dedup_hash collision
// surfaces as a friendly I18nError (web parity: _shared/with-dedup-message.ts).
public enum Transactions {

    /// The handlers this domain currently contributes to the chokepoint registry.
    public static let handlers: [ActionName: Apply.Handler] = [
        .addTransaction: addTransaction,
        .adjustAccountBalance: adjustAccountBalance,
        .updateTransaction: updateTransaction,
        .deleteTransaction: deleteTransaction,
        .setCleared: setCleared,
        .setReviewed: setReviewed,
        .markAllReviewed: markAllReviewed,
        .confirmAllPending: confirmAllPending,
        .setTransactionTags: setTransactionTags,
        .bulkRecategorize: bulkRecategorize,
        .confirmTransaction: confirmTransaction,
        .confirmPendingWithMerchant: confirmPendingWithMerchant,
        .removeAttachment: removeAttachment,
        .setEntryAttachment: setEntryAttachment,
        .reconcileAccount: reconcileAccount,
        .setTransactionSplits: setTransactionSplits,
    ]

    // MARK: setTransactionSplits — verbatim port of the web's per-split base
    // allocation (sign × ratio, last leg absorbs the signed remainder); any
    // residue lands on the fx leg via appendResidue, exactly like the web. The
    // write-parity oracle confirms the match.
    static func setTransactionSplits(_ db: Database, _ args: Args) throws {
        struct Split: Decodable { let categoryId: String?; let amount: Double; let description: String? }
        struct A: Decodable { let id: String; let splits: [Split]? }
        let a = try args.to(A.self)
        let splits = a.splits ?? []
        guard let ref = try Entries.resolveEntryRef(db, a.id) else { return }
        let entryId = ref.entryId
        guard let acct = try Row.fetchOne(db, sql: "SELECT id, account_id, amount, amount_base, exchange_rate, memo, orig_amount, orig_currency, cleared_at FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1", arguments: [entryId]) else { return }
        let acctBase: Double = acct["amount_base"]
        var legs: [Entries.Leg] = [.account(Entries.AccountLeg(
            accountId: acct["account_id"], amount: acct["amount"], amountBase: acctBase,
            exchangeRate: (acct["exchange_rate"] as Double?) ?? 1, memo: acct["memo"], id: acct["id"],
            origAmount: acct["orig_amount"], origCurrency: acct["orig_currency"], clearedAt: acct["cleared_at"]))]
        if splits.isEmpty {
            legs.append(.category(Entries.CategoryLeg(categoryId: nil, amountBase: -acctBase)))
        } else {
            if splits.count == 1 { throw I18nError("error.split.minTwo", [:], "Splits require at least two rows") }
            let totalBase = abs(acctBase)
            let splitTotal = splits.reduce(0.0) { $0 + abs($1.amount) }
            if splitTotal > 0 && abs(splitTotal - totalBase) > 0.005 * Double(splits.count) {
                throw I18nError("error.split.sumMismatch", [:], "Split amounts must sum to the transaction total")
            }
            let baseRatio = splitTotal > 0 ? totalBase / splitTotal : 1
            let sign: Double = acctBase > 0 ? 1 : (acctBase < 0 ? -1 : 0)
            var usedBase = 0.0
            for (i, sp) in splits.enumerated() {
                let isLast = i == splits.count - 1
                // Last leg absorbs the remainder so the category legs sum to
                // -acctBase (zero fx residue). It must be -(acctBase + usedBase),
                // NOT acctBase + usedBase — the latter flips the sign and leaves a
                // phantom residue (bug shared with the web; fixed in both, 2026-06-14).
                let spBase = isLast ? Entries.r2(-(acctBase + usedBase)) : Entries.r2(-abs(sp.amount) * baseRatio * sign)
                if !isLast { usedBase += spBase }
                legs.append(.category(Entries.CategoryLeg(categoryId: sp.categoryId, amountBase: spBase, memo: sp.description)))
            }
        }
        var ep = Entries.EntryPatch()
        ep.legs = .set(legs)
        try Entries.rebuildEntry(db, entryId, ep)
    }

    // MARK: reconcileAccount

    /// Stamp the reconcile checkpoint; optionally post a reconcile adjustment for
    /// the gap between the statement balance and the cleared (confirmed + cleared)
    /// posting sum, marking that adjustment cleared.
    static func reconcileAccount(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let accountId: String; let statementBalance: Double
            let statementDate: String?; let statementTime: String?; let postAdjustment: Bool?
        }
        let a = try args.to(A.self)
        if !a.statementBalance.isFinite { throw I18nError("error.reconcile.statementBalance", [:], "Statement balance is required") }
        let statementDate = a.statementDate ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        // The moment the statement was cut. "00:00" is midnight, which is what a
        // date-only checkpoint already means — normalised to nil so the stored
        // value stays byte-identical for everyone who never sets a time.
        let statementTime: String? = {
            guard let t = a.statementTime, !t.isEmpty, t != "00:00" else { return nil }
            return t
        }()
        if let t = statementTime, !isHM(t) {
            throw I18nError("error.reconcile.timeFormat", [:], "statementTime must be HH:mm")
        }
        if a.postAdjustment == true {
            guard let ledgerId = try String.fetchOne(db, sql: "SELECT ledger_id FROM accounts WHERE id = ?", arguments: [a.accountId]) else {
                throw I18nError("error.notFound.account", [:], "Account not found")
            }
            let cleared = Entries.r2(try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(p.amount), 0) FROM postings p JOIN entries e ON e.id = p.entry_id
                 WHERE p.account_id = ? AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL
                """, arguments: [a.accountId]) ?? 0)
            let delta = Entries.r2(a.statementBalance - cleared)
            // The adjustment is dated to the statement, so it is timed to it too —
            // without a time it sinks to the bottom of that day's feed, below
            // transactions it was posted to account for.
            if abs(delta) >= 0.005, let adjEntryId = try Entries.postAdjustment(db, ledgerId: ledgerId, accountId: a.accountId, delta: delta, date: statementDate, time: statementTime, source: "reconcile") {
                try db.execute(sql: "UPDATE postings SET cleared_at = datetime('now') WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [adjEntryId])
            }
        }
        // The column is `_at`, a moment: it carries the time when there is one. Every
        // reader already takes `prefix(10)`, so a date-only checkpoint is unchanged
        // and a timed one degrades to the same date everywhere it is read as a day.
        let checkpoint = statementTime.map { "\(statementDate) \($0)" } ?? statementDate
        try db.execute(sql: "UPDATE accounts SET last_reconciled_at = ?, last_reconciled_balance = ?, updated_at = datetime('now') WHERE id = ?",
                       arguments: [checkpoint, a.statementBalance, a.accountId])
    }

    // MARK: removeAttachment

    /// Drop an attachment row. The on-disk file unlink is the app's job
    /// (FinchStore.removeAttachment) — the engine owns only the row, mirroring
    /// the web split where the route handler deletes the file.
    static func removeAttachment(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM entry_attachments WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    // MARK: setEntryAttachment (Phase 6.5 — the 75th action, native-only)

    /// Record an attachment row for an entry. NATIVE-ONLY: the web adds
    /// attachments via the multipart `POST /api/attachments` route (file write +
    /// row insert server-side); the native app has no HTTP server, so it stages
    /// the file (Share Extension / PhotosPicker) and then dispatches this to
    /// record the row. Arg names echo the `entry_attachments` columns. The
    /// ledger is derived from the entry when omitted.
    static func setEntryAttachment(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let entryId: String; let kind: String
            let relPath: String; let mimeType: String; let byteSize: Double
            let sha256: String; let originalFilename: String?
        }
        let a = try args.to(A.self)
        if !["image", "pdf"].contains(a.kind) {
            throw I18nError("error.attachment.kind", [:], "Attachment kind must be image or pdf")
        }
        // entryId may be an entries.id OR a client Tx id (account-posting id) —
        // resolveEntryRef handles both (like deleteTransaction / setCleared).
        guard let entryId = try Entries.resolveEntryRef(db, a.entryId)?.entryId else {
            throw I18nError("error.notFound.entry", [:], "Entry not found")
        }
        guard let ledgerId = try a.ledgerId ?? String.fetchOne(db,
            sql: "SELECT ledger_id FROM entries WHERE id = ?", arguments: [entryId]) else {
            throw I18nError("error.notFound.entry", [:], "Entry not found")
        }
        let id = a.id ?? Entries.newId("att")
        try db.execute(sql: """
            INSERT INTO entry_attachments (id, ledger_id, entry_id, kind, rel_path, mime_type,
                byte_size, sha256, original_filename, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))
            """, arguments: [id, ledgerId, entryId, a.kind, a.relPath, a.mimeType,
                             Int(a.byteSize), a.sha256, a.originalFilename])
    }

    // MARK: confirm

    private static func recomputeEntryAccounts(_ db: Database, _ entryId: String) throws {
        for acct in try String.fetchAll(db, sql: "SELECT DISTINCT account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [entryId]) {
            try Entries.recomputeAccountFromPostings(db, acct)
        }
    }

    static func confirmTransaction(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        guard let ref = try Entries.resolveEntryRef(db, try args.to(A.self).id) else { return }
        try db.execute(sql: "UPDATE entries SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'",
                       arguments: [ISO8601DateFormatter().string(from: Date()), ref.entryId])
        try recomputeEntryAccounts(db, ref.entryId)
    }

    static func confirmPendingWithMerchant(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let counterpartyId: String?; let newCounterpartyName: String? }
        let a = try args.to(A.self)
        guard let ref = try Entries.resolveEntryRef(db, a.id) else { return }
        guard let row = try Row.fetchOne(db, sql: "SELECT description FROM entries WHERE id = ?", arguments: [ref.entryId]) else { return }
        var counterpartyId: String?
        var description: String = row["description"] ?? ""
        if let cpId = a.counterpartyId {
            if let cp = try Row.fetchOne(db, sql: "SELECT name FROM counterparties WHERE id = ?", arguments: [cpId]) {
                counterpartyId = cpId
                description = cp["name"]
            }
        } else if let newName = a.newCounterpartyName?.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty {
            let newCpId = Entries.newId("cp")
            try db.execute(sql: "INSERT INTO counterparties (id,name,is_verified,created_at,updated_at) VALUES (?,?,0,datetime('now'),datetime('now'))",
                           arguments: [newCpId, newName])
            counterpartyId = newCpId
            description = newName
        }
        try db.execute(sql: "UPDATE entries SET status = 'confirmed', confirmed_at = ?, counterparty_id = ?, description = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'",
                       arguments: [ISO8601DateFormatter().string(from: Date()), counterpartyId, description, ref.entryId])
        try recomputeEntryAccounts(db, ref.entryId)
    }


    // MARK: addTransaction (same-currency path → postSimple)

    struct AddInput: Decodable {
        let ledgerId: String
        let accountId: String
        let amount: Double
        let amountBase: Double?
        let currency: String?
        let merchant: String
        let categoryId: String?
        let date: String
        let time: String?
        let note: String?
        let status: String?
        let kind: String?
        let refundedTransactionId: String?
        let counterpartyId: String?
        let skipRules: Bool?
        let tagIds: [String]?
        let sourceTemplateId: String?
        let occurrenceDate: String?
        /// The user saw the possible-duplicate prompt and chose "Add anyway".
        /// Absent/false everywhere else, so the double-submit backstop is
        /// unchanged for ordinary saves — see `Entries.NewEntry.allowDuplicate`.
        let allowDuplicate: Bool?
    }

    static func addTransaction(_ db: Database, _ args: Args) throws {
        _ = try addTransactionReturningId(db, args)
    }

    /// Like `addTransaction` but returns the new entry id (so callers can attach
    /// a receipt). Tags in `tagIds` are written in the same transaction.
    @discardableResult
    static func addTransactionReturningId(_ db: Database, _ args: Args) throws -> String {
      try Dedup.wrap {
        let a = try args.to(AddInput.self)
        let refundedEntryId = try a.refundedTransactionId.flatMap { try Entries.resolveEntryRef(db, $0)?.entryId }
        // Merchants are global — no cross-ledger counterparty guard.
        let counterpartyId = a.counterpartyId
        let kind = a.kind.flatMap(Entries.Kind.init(rawValue:)) ?? (a.amount > 0 ? Entries.Kind.income : .expense)

        let acctCcy = try String.fetchOne(db, sql: "SELECT currency FROM accounts WHERE id = ?", arguments: [a.accountId]) ?? "USD"
        let inputCcy = a.currency ?? acctCcy
        if inputCcy != acctCcy {
            // Foreign-currency entry (web qAddTransaction §5.2): convert the
            // entered amount native → account currency → ledger base, carrying
            // orig_amount/orig_currency for display. One account leg + auto-balance.
            let base = try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id = ?", arguments: [a.ledgerId]) ?? acctCcy
            let toAcct = try Entries.convertToBase(db, a.amount, inputCcy, acctCcy, a.date)
            let toBase = try Entries.convertToBase(db, toAcct.amountBase, acctCcy, base, a.date)
            let eid = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: a.ledgerId, date: a.date, time: a.time, description: a.merchant, kind: kind,
                status: a.status.flatMap(Entries.Status.init(rawValue:)),
                legs: [.account(Entries.AccountLeg(accountId: a.accountId, amount: toAcct.amountBase,
                    amountBase: toBase.amountBase, exchangeRate: toBase.rate,
                    origAmount: a.amount, origCurrency: inputCcy))],
                autoBalance: .category(a.categoryId),
                notes: (a.note?.isEmpty ?? true) ? nil : a.note,
                counterpartyId: counterpartyId, refundedEntryId: refundedEntryId,
                sourceTemplateId: a.sourceTemplateId, occurrenceDate: a.occurrenceDate,
                skipRules: a.skipRules ?? false, allowDuplicate: a.allowDuplicate ?? false))
            try Budgets.invalidateForEntry(db, eid)
            try insertTags(db, entryId: eid, tagIds: a.tagIds)
            return eid
        }

        let eid = try Entries.postSimple(db, .init(
            ledgerId: a.ledgerId, accountId: a.accountId, amount: a.amount, date: a.date,
            description: a.merchant, categoryId: a.categoryId, kind: kind, time: a.time,
            notes: (a.note?.isEmpty ?? true) ? nil : a.note,
            status: a.status.flatMap(Entries.Status.init(rawValue:)),
            counterpartyId: counterpartyId, skipRules: a.skipRules ?? false,
            sourceTemplateId: a.sourceTemplateId, occurrenceDate: a.occurrenceDate,
            refundedEntryId: refundedEntryId, allowDuplicate: a.allowDuplicate ?? false))
        try Budgets.invalidateForEntry(db, eid)
        try insertTags(db, entryId: eid, tagIds: a.tagIds)
        return eid
      }
    }

    private static func insertTags(_ db: Database, entryId: String, tagIds: [String]?) throws {
        for tagId in (tagIds ?? []) {
            try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)", arguments: [entryId, tagId])
        }
    }

    // MARK: adjustAccountBalance (→ postAdjustment)

    struct AdjustArgs: Decodable { let accountId: String; let targetBalance: Double; let date: String?; let time: String?; let note: String?; let source: String? }
    static func adjustAccountBalance(_ db: Database, _ args: Args) throws {
        let a = try args.to(AdjustArgs.self)
        guard a.targetBalance.isFinite else { throw I18nError("error.adjust.targetRequired", [:], "Enter a target balance") }
        guard let acct = try Row.fetchOne(db, sql: "SELECT ledger_id, current_balance FROM accounts WHERE id = ?", arguments: [a.accountId]) else {
            throw I18nError("error.notFound.account", [:], "Account not found")
        }
        let ledgerId: String = acct["ledger_id"]
        let current: Double = acct["current_balance"]
        let delta = Entries.r2(a.targetBalance - current)
        let date = a.date ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        try Entries.postAdjustment(db, ledgerId: ledgerId, accountId: a.accountId, delta: delta,
                                   date: date, time: a.time, note: a.note, source: a.source == "reconcile" ? "reconcile" : "manual")
    }

    // MARK: deleteTransaction (→ resolveEntryRef + deleteEntry)

    struct IdArg: Decodable { let id: String }
    static func deleteTransaction(_ db: Database, _ args: Args) throws {
        let a = try args.to(IdArg.self)
        guard let ref = try Entries.resolveEntryRef(db, a.id) else { return }
        try Budgets.invalidateForEntry(db, ref.entryId)   // touches read before the cascade delete
        try Entries.deleteEntry(db, ref.entryId)
        // Attachment on-disk file cleanup is handled app-side (the engine is
        // filesystem-agnostic): FinchStore unlinks files for deleted entries.
    }

    // MARK: updateTransaction (header-only path → rebuildEntry)

    /// Reads the patch via JSONValue to honor key-presence (present-null = clear,
    /// absent = keep). Header-only edits go straight to rebuildEntry; money edits
    /// (amount/currency/account/category) reconstruct the legs with re-locked
    /// conversion (incl. the §5.2 foreign-currency two-step), preserving orig_*,
    /// cleared_at and memo — a verbatim port of the web's qUpdateTransaction.
    static func updateTransaction(_ db: Database, _ args: Args) throws {
        guard case .string(let id)? = args.values["id"] else {
            throw I18nError("error.invalidArgs", [:], "updateTransaction requires an id")
        }
        guard case .object(let patch)? = args.values["patch"] else { return }
        guard let ref = try Entries.resolveEntryRef(db, id) else { return }
        let entryId = ref.entryId
        defer { try? Budgets.invalidateForEntry(db, entryId) }   // rollover cache, any path
        func strOrNil(_ v: JSONValue?) -> String? { if case .string(let s)? = v { return s }; return nil }
        func has(_ k: String) -> Bool { patch.keys.contains(k) }

        let oldLegs = try Row.fetchAll(db, sql: "SELECT * FROM postings WHERE entry_id = ? ORDER BY sort_order", arguments: [entryId])
        let acctLegs = oldLegs.filter { ($0["account_id"] as String?) != nil }
        let touchesMoney = has("amount") || has("category") || has("account") || has("currency") || has("kind")
        // Transfers (>1 account leg) only take header-only patches.
        if acctLegs.count > 1 && touchesMoney {
            throw I18nError("error.tx.transferLegEdit", [:], "Edit transfers from the Transfers screen")
        }
        let ledgerId = try String.fetchOne(db, sql: "SELECT ledger_id FROM entries WHERE id = ?", arguments: [entryId]) ?? ""

        // Header fields (shared by both paths).
        var ep = Entries.EntryPatch()
        if case .string(let s)? = patch["date"] { ep.date = .set(s) }
        if has("time") { ep.time = .set(strOrNil(patch["time"])) }
        if case .string(let s)? = patch["merchant"] {
            ep.description = .set(s)
            ep.counterpartyId = .set(try Entries.resolveCounterpartyIdByName(db, s))
        }
        if has("note") { ep.notes = .set(strOrNil(patch["note"])) }
        if case .string(let s)? = patch["kind"], let k = Entries.Kind(rawValue: s) { ep.kind = .set(k) }
        if has("refundedTransactionId") {
            ep.refundedEntryId = .set(try strOrNil(patch["refundedTransactionId"]).flatMap { try Entries.resolveEntryRef(db, $0)?.entryId })
        }
        if case .string(let s)? = patch["status"], let st = Entries.Status(rawValue: s) { ep.status = .set(st) }

        let rebuildLegs = has("amount") || has("currency") || has("account") || has("category")
        guard rebuildLegs, let oldAcct = acctLegs.first else {
            try Entries.rebuildEntry(db, entryId, ep); return
        }

        // --- Legs rebuild with re-locked conversion (web §5.2). ---
        let base = try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id = ?", arguments: [ledgerId]) ?? "USD"
        let oldAcctCcy: String = oldAcct["currency"]
        let newAccountId = strOrNil(patch["account"]) ?? (oldAcct["account_id"] as String)
        let newAcctCcy = try String.fetchOne(db, sql: "SELECT currency FROM accounts WHERE id = ?", arguments: [newAccountId]) ?? oldAcctCcy
        let curDate = try String.fetchOne(db, sql: "SELECT date FROM entries WHERE id = ?", arguments: [entryId]) ?? ""
        let nativeTyped: Double = patch["amount"]?.asDouble ?? (oldAcct["amount"] as Double)
        let patchCcy = strOrNil(patch["currency"]) ?? (has("account") ? newAcctCcy : oldAcctCcy)
        let willRelock = has("amount") || has("currency") || has("date") || has("account")
        let effectiveDate = strOrNil(patch["date"]) ?? curDate

        var nativeAmount: Double, amountBase: Double, rate: Double
        var origAmount: Double?, origCurrency: String?
        if willRelock && patchCcy != newAcctCcy {
            let toAcct = try Entries.convertToBase(db, nativeTyped, patchCcy, newAcctCcy, effectiveDate)
            let toBase = try Entries.convertToBase(db, toAcct.amountBase, newAcctCcy, base, effectiveDate)
            nativeAmount = toAcct.amountBase; amountBase = toBase.amountBase; rate = toBase.rate
            origAmount = nativeTyped; origCurrency = patchCcy
        } else if willRelock {
            let conv = try Entries.convertToBase(db, nativeTyped, patchCcy, base, effectiveDate)
            nativeAmount = nativeTyped; amountBase = conv.amountBase; rate = conv.rate
            origAmount = oldAcct["orig_amount"]; origCurrency = oldAcct["orig_currency"]
        } else {
            nativeAmount = nativeTyped; amountBase = oldAcct["amount_base"]; rate = oldAcct["exchange_rate"]
            origAmount = oldAcct["orig_amount"]; origCurrency = oldAcct["orig_currency"]
        }

        let plainCatLegs = oldLegs.filter { ($0["account_id"] as String?) == nil }
        // Category patch on a split entry (≥2 category legs) is a header-only no-op.
        if plainCatLegs.count >= 2 && has("category") { try Entries.rebuildEntry(db, entryId, ep); return }
        let existingCat = plainCatLegs.first
        let newCategoryId: String? = has("category") ? strOrNil(patch["category"]) : (existingCat?["category_id"] as String?)

        ep.legs = .set([
            .account(Entries.AccountLeg(accountId: newAccountId, amount: nativeAmount, amountBase: amountBase,
                exchangeRate: rate, memo: oldAcct["memo"], id: oldAcct["id"],
                origAmount: origAmount, origCurrency: origCurrency, clearedAt: oldAcct["cleared_at"])),
            .category(Entries.CategoryLeg(categoryId: newCategoryId, amountBase: Entries.r2(-amountBase),
                memo: existingCat?["memo"], id: existingCat?["id"])),
        ])
        try Entries.rebuildEntry(db, entryId, ep)
    }

    // MARK: setCleared / setReviewed / markAllReviewed

    struct IdCleared: Decodable { let id: String; let cleared: Bool }
    static func setCleared(_ db: Database, _ args: Args) throws {
        let a = try args.to(IdCleared.self)
        let postingId = try Entries.resolveEntryRef(db, a.id)?.postingId ?? a.id
        try db.execute(sql: a.cleared
            ? "UPDATE postings SET cleared_at = datetime('now') WHERE id = ?"
            : "UPDATE postings SET cleared_at = NULL WHERE id = ?", arguments: [postingId])
    }

    struct IdReviewed: Decodable { let id: String; let reviewed: Bool }
    static func setReviewed(_ db: Database, _ args: Args) throws {
        let a = try args.to(IdReviewed.self)
        let entryId = try Entries.resolveEntryRef(db, a.id)?.entryId ?? a.id
        try db.execute(sql: a.reviewed
            ? "UPDATE entries SET reviewed_at = datetime('now') WHERE id = ?"
            : "UPDATE entries SET reviewed_at = NULL WHERE id = ?", arguments: [entryId])
    }

    struct MarkAll: Decodable { let ledgerId: String?; let accountId: String? }
    static func markAllReviewed(_ db: Database, _ args: Args) throws {
        let a = try args.to(MarkAll.self)
        let ledgerId = a.ledgerId ?? "personal"
        if let accountId = a.accountId {
            try db.execute(sql: """
                UPDATE entries SET reviewed_at = datetime('now')
                 WHERE ledger_id = ? AND reviewed_at IS NULL
                   AND EXISTS (SELECT 1 FROM postings p WHERE p.entry_id = entries.id AND p.account_id = ?)
                """, arguments: [ledgerId, accountId])
        } else {
            try db.execute(sql: "UPDATE entries SET reviewed_at = datetime('now') WHERE ledger_id = ? AND reviewed_at IS NULL",
                           arguments: [ledgerId])
        }
    }

    // MARK: setTransactionTags

    static func setTransactionTags(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let tagIds: [String] }
        let a = try args.to(A.self)
        let entryId = try Entries.resolveEntryRef(db, a.id)?.entryId ?? a.id
        try db.execute(sql: "DELETE FROM entry_tags WHERE entry_id = ?", arguments: [entryId])
        for tagId in a.tagIds {
            try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)", arguments: [entryId, tagId])
        }
    }

    // MARK: bulkRecategorize (→ rebuildEntry with [acctLeg, new category leg])

    /// Single-category entries only; splits (≥2 category legs) are skipped, like
    /// the web. The account leg is forwarded with its reconcile mark + foreign-
    /// entry display fields preserved (web mutations.ts:200,215), so re-categorizing
    /// a cleared or FX transaction keeps cleared_at / orig_amount / orig_currency.
    static func bulkRecategorize(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let ids: [String]; let categoryId: String? }
        let a = try args.to(A.self)
        if a.ids.isEmpty { return }
        for id in a.ids {
            guard let ref = try Entries.resolveEntryRef(db, id) else { continue }
            let entryId = ref.entryId
            let catCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [entryId]) ?? 0
            if catCount >= 2 { continue }
            guard let acct = try Row.fetchOne(db, sql:
                "SELECT id, account_id, amount, amount_base, exchange_rate, memo, orig_amount, orig_currency, cleared_at FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1",
                arguments: [entryId]) else { continue }
            let amountBase: Double = acct["amount_base"]
            var ep = Entries.EntryPatch()
            ep.legs = .set([
                .account(Entries.AccountLeg(accountId: acct["account_id"], amount: acct["amount"],
                    amountBase: acct["amount_base"], exchangeRate: (acct["exchange_rate"] as Double?) ?? 1,
                    memo: acct["memo"], id: acct["id"],
                    origAmount: acct["orig_amount"], origCurrency: acct["orig_currency"], clearedAt: acct["cleared_at"])),
                .category(Entries.CategoryLeg(categoryId: a.categoryId, amountBase: -amountBase)),
            ])
            try Entries.rebuildEntry(db, entryId, ep)
            try Budgets.invalidateForEntry(db, entryId)
        }
    }

    // MARK: confirmAllPending

    static func confirmAllPending(_ db: Database, _ args: Args) throws {
        let accts = try String.fetchAll(db, sql: """
            SELECT DISTINCT p.account_id FROM postings p JOIN entries e ON e.id = p.entry_id
             WHERE e.status = 'pending' AND p.account_id IS NOT NULL
            """)
        try db.execute(sql: "UPDATE entries SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE status = 'pending'",
                       arguments: [ISO8601DateFormatter().string(from: Date())])
        // Pending postings weren't in the cached balance (the trigger only fires
        // on confirmed inserts) — recompute each touched account.
        for acct in accts { try Entries.recomputeAccountFromPostings(db, acct) }
    }
}
