import Foundation
import GRDB

/// Scheduled-templates domain — port of lib/db/domain/scheduled/mutations.ts
/// (the CRUD + split actions). DEFERRED: postScheduled + generateDueScheduled
/// (the template→transaction posting actions) and postSingle/split posting.
public enum Scheduled {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createScheduled: create,
        .updateScheduled: update,
        .deleteScheduled: delete,
        .addScheduledSplit: addSplit,
        .updateScheduledSplit: updateSplit,
        .removeScheduledSplit: removeSplit,
        .generateDueScheduled: generateDue,
        .postScheduled: post,
    ]

    /// The time a posting carries: an explicitly requested one, else the template's
    /// intended time-of-day, else the moment it fires.
    ///
    /// Never nil, and that is the point. An entry with a NULL time sinks to the
    /// BOTTOM of its day — the feed orders by `date DESC, time DESC` and SQLite sorts
    /// NULLs last — which is exactly what `AddTransactionSheet` avoids when it
    /// prefills an occurrence. The automatic path used to cause it.
    ///
    /// The `explicit` argument is what keeps this deterministic: the app omits it and
    /// gets the firing moment, while the parity fixture pins it — the same shape the
    /// action's `date` already uses ("postScheduled with a PINNED date").
    static func postingTime(_ template: Row, explicit: String?) -> String {
        if let e = explicit, !e.isEmpty { return e }
        if let t = template["start_time"] as String?, !t.isEmpty { return t }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private static func postSingle(_ db: Database, ledgerId: String, accountId: String, amount: Double,
                                   description: String, date: String, time: String?, sourceTemplateId: String,
                                   categoryId: String?, occurrenceDate: String? = nil) throws {
        try Entries.postSimple(db, .init(ledgerId: ledgerId, accountId: accountId, amount: amount, date: date,
            description: description, categoryId: categoryId, kind: amount > 0 ? .income : .expense,
            time: time, sourceTemplateId: sourceTemplateId, occurrenceDate: occurrenceDate))
    }

    /// Post one transaction/transfer NOW from a template (confirmed). Honours the
    /// installment cap and income splits.
    static func post(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let templateId: String; let date: String?; let time: String?; let occurrenceDate: String? }
        let a = try args.to(A.self)
        let templateId = a.templateId
        guard let t = try Row.fetchOne(db, sql: "SELECT * FROM scheduled_templates WHERE id = ?", arguments: [templateId]) else {
            throw I18nError("error.notFound.template", [:], "Template not found")
        }
        let ledgerId: String = t["ledger_id"]
        let name = (t["name"] as String?) ?? ""
        if let total = t["installment_total"] as Int? {
            let paid = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id = ? AND status = 'confirmed'", arguments: [templateId]) ?? 0
            if paid >= total { throw I18nError("error.scheduled.installmentDone", ["name": name, "total": String(total)], "\"\(name)\" has finished its \(total)-payment plan") }
        }
        // Explicit date wins; otherwise today (unchanged legacy behaviour). The
        // occurrence defaults to the posting date, so a plain post still resolves
        // its own cell.
        let date = a.date ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let occurrenceDate = a.occurrenceDate ?? date
        let desc = (t["description"] as String?) ?? name
        let postTime = postingTime(t, explicit: a.time)
        let type: String = t["kind"]
        let accountId: String = t["account_id"]

        if type == "transfer" {
            guard let from = t["from_account_id"] as String? else { throw I18nError("error.scheduled.missingAccount", ["name": name], "\"\(name)\" is missing an account") }
            try Entries.postTransfer(db, fromAccountId: from, toAccountId: accountId, fromAmount: abs((t["amount"] as Double?) ?? 0),
                                     date: date, time: postTime, note: desc, sourceTemplateId: templateId, occurrenceDate: occurrenceDate)
            return
        }
        guard let amount = t["amount"] as Double? else { throw I18nError("error.scheduled.variableAmount", ["name": name], "\"\(name)\" has a variable amount — add it manually") }
        let categoryId = t["category_id"] as String?

        if type == "income" {
            let splits = try Row.fetchAll(db, sql: "SELECT account_id, amount_pct, amount_abs, description FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order", arguments: [templateId])
            if !splits.isEmpty {
                // ONE transaction with an account leg per split — the same shape the Add
                // sheet produces for a split payment. This used to call postSingle once
                // per split, so a salary paid into two accounts became two unrelated
                // transactions while the identical split entered by hand became one.
                //
                // A single entry has a single `description`, so each split's own
                // `description` (e.g. "main" / "savings") has no row of its own to sit
                // on any more. It is carried onto that leg's `memo` instead of being
                // dropped — reproducing EXACTLY the string the old per-split loop used
                // to stamp as that row's own `description` ("\(desc) · \(label)"), so an
                // existing split template looks unchanged in the feed after this ships.
                // `memo ?? description` is what the projection shows, so a split with no
                // label gets no memo at all (falls through to the entry's own
                // description) rather than a dangling " · " or a redundant duplicate.
                let legs: [Entries.Leg] = splits.compactMap { sp -> Entries.Leg? in
                    let portion = (sp["amount_abs"] as Double?) ?? (amount * ((sp["amount_pct"] as Double?) ?? 0) / 100)
                    guard portion != 0, let acct = sp["account_id"] as String? else { return nil }
                    let label = sp["description"] as String?
                    let memo = (label?.isEmpty ?? true) ? nil : "\(desc) · \(label!)"
                    return .account(Entries.AccountLeg(accountId: acct, amount: portion, memo: memo))
                }
                if legs.isEmpty {
                    throw I18nError("error.scheduled.noSplits", ["name": name], "No split amounts to post for \"\(name)\"")
                }
                _ = try Entries.postEntry(db, Entries.NewEntry(
                    ledgerId: ledgerId, date: date, time: postTime, description: desc, kind: .income,
                    legs: legs, autoBalance: .category(categoryId),
                    sourceTemplateId: templateId, occurrenceDate: occurrenceDate))
                return
            }
        }
        try postSingle(db, ledgerId: ledgerId, accountId: accountId, amount: (type == "income" ? 1 : -1) * amount,
                       description: desc, date: date, time: postTime, sourceTemplateId: templateId,
                       categoryId: categoryId, occurrenceDate: occurrenceDate)
    }

    /// Post every due (not-yet-generated) occurrence of each active template as a
    /// pending transaction/transfer. DEFERRED: split-enabled templates are
    /// skipped (as on the web), and the rules engine isn't applied.
    static func generateDue(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let today: String?; let time: String? }
        let parsed = try? args.to(A.self)
        let today = (parsed?.today).flatMap { $0 } ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let explicitTime = (parsed?.time).flatMap { $0 }
        let ts = ISO8601DateFormatter().string(from: Date())
        for r in try Row.fetchAll(db, sql: "SELECT * FROM scheduled_templates WHERE is_active = 1") {
            let type: String = r["kind"]
            guard let amount = r["amount"] as Double? else { continue }
            if (r["splits_enabled"] as Int? ?? 0) != 0 { continue }
            if type == "transfer" && (r["from_account_id"] as String?) == nil { continue }

            let template = ScheduledTemplate(
                id: r["id"], name: (r["name"] as String?) ?? "", description: nil, type: type,
                amount: amount, frequency: r["frequency"], dayOfMonth: (r["day_of_month"] as Int?) ?? 1,
                weekDay: r["day_of_week"], accountId: r["account_id"], fromAccountId: r["from_account_id"],
                startDate: r["start_date"], startTime: r["start_time"], endDate: r["end_date"], nextRun: (r["next_run"] as String?) ?? "",
                maxExecutions: nil, installmentTotal: nil, installmentPaid: nil)
            var dates = Selectors.occurrencesUpTo(template, today)
            if dates.isEmpty { continue }
            // Resolution keys on occurrenceDate ?? date (see Selectors), so
            // "already posted" must key on the same coalesce — not the raw
            // posting date — or an occurrence posted under a different
            // transaction date (e.g. paid late) is not recognised and gets
            // regenerated as a duplicate.
            let have = Set(try String.fetchAll(db, sql: "SELECT COALESCE(occurrence_date, date) FROM entries WHERE source_template_id = ?", arguments: [r["id"] as String]))
            dates = dates.filter { !have.contains($0) }
            if let maxEx = r["max_executions"] as Int? { dates = Array(dates.prefix(Swift.max(0, maxEx - have.count))) }
            if let instTotal = r["installment_total"] as Int? { dates = Array(dates.prefix(Swift.max(0, instTotal - have.count))) }
            if dates.isEmpty { continue }

            let ledgerId: String = r["ledger_id"]
            let acctId: String = r["account_id"]
            let description = (r["description"] as String?) ?? (r["name"] as String?) ?? ""
            if type == "transfer" {
                let fromAccountId: String = r["from_account_id"]
                for date in dates {
                    try Entries.postTransfer(db, fromAccountId: fromAccountId, toAccountId: acctId, fromAmount: abs(amount),
                                             date: date, time: postingTime(r, explicit: explicitTime), note: description.isEmpty ? nil : description,
                                             sourceTemplateId: r["id"], occurrenceDate: date, timestamp: ts)
                }
                continue
            }
            let signed = (type == "income" ? 1.0 : -1.0) * amount
            let categoryId: String? = r["category_id"]
            let cpId = try Entries.resolveCounterpartyIdByName(db, description)
            for date in dates {
                try Entries.postSimple(db, .init(ledgerId: ledgerId, accountId: acctId, amount: signed, date: date,
                    description: description, categoryId: categoryId, kind: type == "income" ? .income : .expense,
                    time: postingTime(r, explicit: explicitTime), status: .pending, counterpartyId: cpId, id: nil,
                    sourceTemplateId: r["id"], occurrenceDate: date))
            }
        }
    }

    /// null/empty → nil; otherwise a positive whole number (else throws).
    private static func parseInstallmentTotal(_ v: JSONValue?) throws -> Int? {
        guard let v, !(v == .null) else { return nil }
        if case .string(let s) = v, s.isEmpty { return nil }
        guard let d = v.asDouble, d > 0, d.truncatingRemainder(dividingBy: 1) == 0 else {
            throw I18nError("error.scheduled.installmentTotal", [:], "Installment total must be a positive whole number")
        }
        return Int(d)
    }

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let name: String; let description: String?; let type: String?
            let amount: Double?; let frequency: String?; let dayOfMonth: Double?; let weekDay: Double?
            let accountId: String?; let fromAccountId: String?; let color: String?; let category: String?
            let startDate: String?; let startTime: String?; let endDate: String?; let maxExecutions: Double?
        }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.templateName", [:], "Template name is required") }
        let type = a.type ?? "expense"
        if !["income", "expense", "transfer"].contains(type) { throw I18nError("error.account.splitTypeUnknown", ["type": type], "Unknown type \"\(type)\"") }
        let frequency = a.frequency ?? "monthly"
        if !["once", "daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"].contains(frequency) {
            throw I18nError("error.account.splitFreqUnknown", ["freq": frequency], "Unknown frequency \"\(frequency)\"")
        }
        let accountId = (a.accountId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if accountId.isEmpty { throw I18nError("error.required.account", [:], "An account is required") }
        let installmentTotal = try parseInstallmentTotal(args.values["installmentTotal"])
        let fromAccountId = (type == "transfer") ? a.fromAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let startDate = a.startDate ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        try db.execute(sql: """
            INSERT INTO scheduled_templates
              (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,
               from_account_id,category_id,frequency,day_of_month,day_of_week,start_date,start_time,
               end_date,max_executions,installment_total,next_run,last_run,auto_post,color,is_active,created_at,updated_at)
            VALUES (?,?,?,?,?,?,0,0,?,?,?,?,?,?,?,?,?,?,?,NULL,NULL,?,?,1,datetime('now'),datetime('now'))
            """, arguments: [a.id ?? Entries.newId("sch"), a.ledgerId ?? "personal", name,
                             a.description?.trimmingCharacters(in: .whitespacesAndNewlines), type, a.amount,
                             accountId, fromAccountId, a.category, frequency, Int(a.dayOfMonth ?? 1) == 0 ? 1 : Int(a.dayOfMonth ?? 1),
                             a.weekDay.map { Int($0) }, startDate, a.startTime, a.endDate, a.maxExecutions.map { Int($0) }, installmentTotal,
                             (args.values["autoPost"]?.isTruthy ?? false) ? 1 : 0, a.color])
    }

    private static let cols: [String: String] = [
        "name": "name", "description": "description", "amount": "amount", "frequency": "frequency",
        "dayOfMonth": "day_of_month", "weekDay": "day_of_week", "autoPost": "auto_post", "color": "color",
        "type": "kind", "category": "category_id", "endDate": "end_date", "maxExecutions": "max_executions",
        "installmentTotal": "installment_total",
        // Editable: occurrences are DERIVED from start_date (`Forecast.occurrencesUpTo`
        // anchors on it), and `next_run` is never written — inserted NULL and left
        // there. So moving the start moves the whole schedule, with nothing stored to
        // recompute. It was omitted here, which is the only reason the sheet showed it
        // read-only.
        "startDate": "start_date",
        // The intended time-of-day for postings. NULL keeps today's behaviour.
        "startTime": "start_time",
    ]

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateScheduled requires an id") }
        var patch = args.patchObject
        if let n = patch["name"], !n.isNonEmptyTrimmedString { throw I18nError("error.required.templateName", [:], "Template name is required") }
        if patch.keys.contains("installmentTotal") {
            patch["installmentTotal"] = try parseInstallmentTotal(patch["installmentTotal"]).map { JSONValue.int($0) } ?? .null
        }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        for (key, col) in cols where patch.keys.contains(key) {
            sets.append("\(col) = ?"); bind.append(patch[key]!.sqlBind)
        }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE scheduled_templates SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM scheduled_templates WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    static func addSplit(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let templateId: String; let accountId: String; let pct: Double? }
        let a = try args.to(A.self)
        let accountId = a.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if accountId.isEmpty { throw I18nError("error.required.splitAccount", [:], "A split needs an account") }
        let sort = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM scheduled_splits WHERE template_id = ?", arguments: [a.templateId]) ?? 0
        let id = "\(a.templateId)-s\(sort)-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased())"
        try db.execute(sql: "INSERT INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,category_id,description,sort_order) VALUES (?,?,?,?,NULL,NULL,NULL,?)",
                       arguments: [id, a.templateId, accountId, a.pct ?? 0, sort])
        try db.execute(sql: "UPDATE scheduled_templates SET splits_enabled = 1, updated_at = datetime('now') WHERE id = ?", arguments: [a.templateId])
    }

    static func updateSplit(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let templateId: String; let index: Int; let pct: Double }
        let a = try args.to(A.self)
        try db.execute(sql: """
            UPDATE scheduled_splits SET amount_pct = ?
             WHERE id = (SELECT id FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)
            """, arguments: [a.pct, a.templateId, a.index])
    }

    static func removeSplit(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let templateId: String; let index: Int }
        let a = try args.to(A.self)
        try db.execute(sql: """
            DELETE FROM scheduled_splits
             WHERE id = (SELECT id FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)
            """, arguments: [a.templateId, a.index])
        let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scheduled_splits WHERE template_id = ?", arguments: [a.templateId]) ?? 0
        if n == 0 {
            try db.execute(sql: "UPDATE scheduled_templates SET splits_enabled = 0, updated_at = datetime('now') WHERE id = ?", arguments: [a.templateId])
        }
    }
}
