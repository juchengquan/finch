#if os(iOS)
import Foundation
import WatchConnectivity
import FinchCore

/// Watch sub-project CP1 — pushes the latest snapshot to the paired Apple Watch
/// via `WCSession.updateApplicationContext` (latest-state, coalescing; App Groups
/// don't span devices). iOS-only: WatchConnectivity is unavailable on macOS, and
/// FinchMac shares these sources.
final class PhoneWatchLink: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchLink()

    /// Activate once at launch (no-op if the device has no WCSession support).
    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Send the latest payload to the watch. Inert unless a watch app is installed.
    func push(_ payload: WatchSnapshotPayload) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled,
              let data = payload.encoded() else { return }
        try? s.updateApplicationContext(["snapshot": data])
    }

    // MARK: CP3 — receive on-wrist quick-adds

    /// Persisted redelivery guard (the approved CP3 spec's ring; the store's
    /// duplicate-transaction guard is the backstop).
    private let dedupe = QuickAddDedupe()

    /// Pure mapping (testable): item → `addTransaction` args. Items carry
    /// positive magnitudes; an expense posts negative. Wrist entries land as
    /// **pending** (the CP3 spec §3) — the phone's Pending review is the
    /// confirm/edit surface for terse on-wrist captures.
    static func quickAddArgs(_ item: WatchQuickAddItem, date: String) -> [String: JSONValue] {
        var args: [String: JSONValue] = [
            "ledgerId": .string(item.ledgerId),
            "accountId": .string(item.accountId),
            "amount": .double(-abs(item.amount)),
            "merchant": .string(item.merchant),
            "date": .string(date),
            "status": .string("pending"),
        ]
        if let cat = item.categoryId { args["categoryId"] = .string(cat) }
        return args
    }

    /// Catalog-staleness guards (CP3 spec §3): an unknown account falls back to
    /// the ledger's first active account, an unknown category to the ledger's
    /// first expense category (or none) — rather than dropping the spend. Nil
    /// only when the whole ledger is gone.
    static func resolvedItem(_ item: WatchQuickAddItem,
                             accounts: [AccountRow], categories: [CategoryRow]) -> WatchQuickAddItem? {
        var out = item
        let ledgerAccounts = accounts.filter { ($0.ledgerId ?? "personal") == item.ledgerId && ($0.isActive ?? true) }
        if !ledgerAccounts.contains(where: { $0.id == item.accountId }) {
            guard let fallback = ledgerAccounts.first else { return nil }
            out.accountId = fallback.id
        }
        if let cat = item.categoryId,
           !categories.contains(where: { $0.id == cat && $0.ledgerId == item.ledgerId }) {
            out.categoryId = categories.first { $0.ledgerId == item.ledgerId && ($0.kind ?? "expense") == "expense" }?.id
        }
        return out
    }

    /// Booking date: the wrist tap's `createdAt` when present (an overnight-
    /// queued add books on the day it was tapped), else the phone's today.
    static func bookingDate(_ req: WatchQuickAddRequest, fallback: String) -> String {
        guard let created = req.createdAt else { return fallback }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: created)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["quickAdd"] as? Data,
              let req = WatchQuickAddRequest.decode(data),
              dedupe.firstSeen(req.id) else { return }
        Task { @MainActor in
            let store = FinchStore.shared
            guard let item = Self.resolvedItem(req.item, accounts: store.accounts,
                                               categories: store.pickableCategories) else { return }
            do {
                try store.apply(.addTransaction,
                                Args(Self.quickAddArgs(item, date: Self.bookingDate(req, fallback: store.wallToday))))
                // The fresh snapshot pushed back to the watch IS the confirmation
                // (and refreshes the recents/catalog + the complication).
                WidgetSnapshotWriter.write(from: store)
            } catch {
                // The duplicate guard or a validation failure — drop. The watch
                // row only ever claims "queued", not "posted".
            }
        }
    }

    // MARK: WCSessionDelegate (iOS-required stubs)
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }  // re-activate for watch switching
}

extension WatchSnapshotPayload {
    /// Map the phone's WidgetSnapshot to the watch wire format (the four glance
    /// fields + a fresh timestamp).
    init(widget snap: WidgetSnapshot) {
        self.init(netWorth: snap.netWorth, currency: snap.currency,
                  budgetUsedPct: snap.budgetUsedPct, weeklySpent: snap.weeklySpent,
                  generatedAt: Date())
    }
}
#endif
