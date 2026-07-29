import Foundation
import FinchCore
import GRDB

#if DEBUG

/// Bulk-seed N transactions so the resume shadow can be judged at REALISTIC data
/// volume (THROWAWAY — lab/pilot only).
///
/// Why this exists: every judgement in this investigation, including the
/// validation of the shipped `RightSlideDrill` fix, used the demo seed's ~44
/// transactions. The pilot then showed the artifact is content-dependent — 8 rows
/// clean, 44 clean under a UIKit root, 100 shadowing — so 44 may sit under the
/// trigger threshold. A real ledger has hundreds after a month and thousands after
/// a year, and the fix has never been tested there.
///
/// Launch with `-bulkSeed 2000`. Idempotent: seeds only up to the target count.
/// Writes through `FinchCore.Apply` directly rather than `store.apply`, which is
/// the documented bulk path — it skips the per-write side effects (Spotlight
/// re-index, notification re-plan, widget snapshot, auto-backup) that would make
/// 2,000 inserts take minutes.
enum BulkSeed {

    static func seedIfRequested(_ q: DatabaseQueue) {
        let target = UserDefaults.standard.integer(forKey: "bulkSeed")
        guard target > 0 else { return }
        do { try seed(q, target: target) } catch {
            print("[BulkSeed] failed: \(error)")
        }
    }

    private static func seed(_ q: DatabaseQueue, target: Int) throws {
        let existing = try Projection.run(dbQueue: q, ledgerId: "personal").count
        guard existing < target else {
            print("[BulkSeed] already \(existing) transactions, target \(target) — nothing to do")
            return
        }
        let needed = target - existing
        print("[BulkSeed] inserting \(needed) transactions (existing \(existing), target \(target))…")

        let cal = Calendar.current
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = cal.timeZone
        let now = Date()

        // Spread across ~3 years so the feed has many month sections, like a real
        // ledger — the month grouping is part of what the scroll view renders.
        let merchants = ["Corner Store", "Metro", "Cafe Nero", "Pharmacy", "Hardware",
                         "Bookshop", "Bakery", "Cinema", "Petrol", "Newsagent"]

        for i in 0..<needed {
            let daysAgo: Int = (i * 1100) / max(needed, 1)
            let day = cal.date(byAdding: DateComponents(day: -daysAgo), to: now) ?? now
            let date = df.string(from: day)
            // Deterministic, no RNG: the same seed run twice produces the same ledger.
            let amount = -Double((i % 97) + 3) - Double(i % 100) / 100.0
            try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
                "ledgerId": .string("personal"),
                "accountId": .string("everyday"),
                "amount": .double(amount),
                "merchant": .string(merchants[i % merchants.count]),
                "date": .string(date),
                "time": .string("12:00"),
            ]))
        }
        print("[BulkSeed] done — \(target) transactions")
    }
}

#endif
