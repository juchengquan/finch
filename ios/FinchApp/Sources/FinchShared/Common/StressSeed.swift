import Foundation
import FinchCore
import GRDB

#if DEBUG
/// DEBUG-only bulk transaction generator, for measuring projection cost at scale.
/// Triggered by the `-stressSeed N` launch flag (see `FinchStore.bootstrap`) on a
/// freshly-seeded DB: appends N synthetic transactions to the "personal" ledger's
/// first account (+ first category), spread over ~2 years. Goes through the normal
/// `Apply` write chokepoint so the entries/postings are valid double-entry and the
/// projection processes them like real data. Never compiled into release.
///
/// Usage (simulator): launch with `-resetStore YES -stressSeed 20000` once to build
/// the dataset (slow — one write txn per row), then relaunch WITHOUT flags and read
/// the `launch` timing marks to see reproject cost at that scale.
enum StressSeed {
    static func seed(_ q: DatabaseQueue, count: Int) throws {
        guard count > 0,
              let acctId = ((try? Projection.accounts(dbQueue: q, ledgerId: "personal")) ?? []).first?.id
        else { return }
        let catId = ((try? Projection.categories(dbQueue: q, ledgerId: "personal")) ?? []).first?.id
        let cal = Calendar.current
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = cal.timeZone
        let now = Date()
        for i in 0..<count {
            let date = df.string(from: cal.date(byAdding: .day, value: -(i % 730), to: now) ?? now)
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"),
                "accountId": .string(acctId),
                "amount": .double(-Double((i % 300) + 1)),
                "merchant": .string("Stress \(i % 40)"),
                "date": .string(date),
                "time": .string("12:00"),
            ]
            if let catId { args["categoryId"] = .string(catId) }
            try Apply.apply(dbQueue: q, action: "addTransaction", args: Args(args))
        }
    }
}
#endif
