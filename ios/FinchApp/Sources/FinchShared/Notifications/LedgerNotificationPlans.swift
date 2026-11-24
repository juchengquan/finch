import Foundation
import FinchCore
import GRDB

/// Every ledger's notifications, not only the one on screen.
///
/// The plan used to be built from the store, which holds the ACTIVE ledger. The
/// reconcile step withdraws whatever the plan does not contain and forgets it was
/// shown, so switching ledgers cancelled the other ledger's pending reminders, and
/// switching back re-sent every alert the user had already dismissed there.
///
/// The ledgers not on screen are read from the database. They change only when that
/// ledger is written, which mostly means it is on screen, so their plans are cached
/// (`OtherLedgerPlans`) and rebuilt when the cache key moves: another ledger becomes
/// active, the day turns, a preference or Hide amounts changes, or their entries
/// change (a cross-ledger transfer writes both sides).
extension FinchStore {

    /// One inactive ledger's rows, as the planner reads them.
    struct LedgerSlices: Sendable {
        let ledger: Ledger
        let budgets: [BudgetRow]
        let txns: [Tx]
        let scheduled: [ScheduledTemplate]
        let categories: [CategoryRow]
        let accounts: [AccountRow]
    }

    /// What the inactive ledgers' plans depend on in the database: their entries'
    /// count and newest edit. Cheap (two aggregates), so it is read on every refresh.
    nonisolated static func otherLedgerDataSignature(_ q: DatabaseQueue, active: String) -> String {
        (try? q.read { db in
            let r = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS n, COALESCE(MAX(updated_at), '') AS u FROM entries WHERE ledger_id <> ?
                """, arguments: [active])
            return "\(r?["n"] as Int? ?? 0)/\(r?["u"] as String? ?? "")"
        }) ?? ""
    }

    /// Read every ledger but `active`. A ledger whose rows fail to load is left out
    /// rather than failing the whole plan.
    nonisolated static func loadOtherLedgers(_ q: DatabaseQueue, active: String) -> [LedgerSlices] {
        ((try? Projection.ledgers(dbQueue: q)) ?? []).filter { $0.id != active }.compactMap { l in
            try? LedgerSlices(
                ledger: l,
                budgets: Projection.budgets(dbQueue: q, ledgerId: l.id),
                txns: Projection.run(dbQueue: q, ledgerId: l.id),
                scheduled: Projection.scheduledTemplates(dbQueue: q, ledgerId: l.id),
                categories: Projection.categories(dbQueue: q, ledgerId: l.id),
                accounts: Projection.accounts(dbQueue: q, ledgerId: l.id))
        }
    }

    /// The notifications of the ledgers in `slices`, each in its own currency. Same
    /// planner and inputs as the active ledger's, but no weekly digest: its id is the
    /// week, not the ledger, so it stays the active ledger's.
    func planNotifications(for slices: [LedgerSlices], enabled: Set<NotificationKind>,
                           deliveryHour: Int) -> [PlannedNotification] {
        slices.flatMap { s -> [PlannedNotification] in
            let id = s.ledger.id
            return NotificationPlanner.plan(
                budgets: s.budgets, txns: s.txns, scheduled: s.scheduled,
                categories: s.categories.map { CategoryNode(id: $0.id, parentId: $0.parentId) },
                // Data-anchored like the store's `today`, but on this ledger's rows.
                today: s.txns.map(\.date).max() ?? wallToday, wallToday: wallToday,
                ledgerId: id, enabled: enabled.subtracting([.weeklyDigest]),
                money: { [unowned self] in self.displayMoney($0, forLedger: id) },
                deliveryHour: deliveryHour,
                accounts: s.accounts,
                accountMoney: { [unowned self] amount, currency in
                    self.displayMoney(self.toBase(amount, from: currency, ledgerBase: s.ledger.base), forLedger: id)
                },
                fxConvert: { [unowned self] in self.fxConvert($0, from: $1, to: $2, on: $3) })
        }
    }
}

/// The inactive ledgers' last plan and the key it was built under.
struct OtherLedgerPlans {
    let key: String
    let planned: [PlannedNotification]
    let templateIds: Set<String>
}
