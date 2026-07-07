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

    /// `transferUserInfo` can redeliver; request ids we've already posted are
    /// dropped (the store's duplicate-transaction guard is the backstop).
    /// Only touched on the main actor.
    private var seenQuickAddIds = Set<String>()

    /// Pure mapping (testable): template → `addTransaction` args. Templates are
    /// positive magnitudes; an expense posts negative.
    static func quickAddArgs(_ req: WatchQuickAddRequest, date: String) -> [String: JSONValue] {
        var args: [String: JSONValue] = [
            "ledgerId": .string(req.item.ledgerId),
            "accountId": .string(req.item.accountId),
            "amount": .double(-abs(req.item.amount)),
            "merchant": .string(req.item.merchant),
            "date": .string(date),
        ]
        if let cat = req.item.categoryId { args["categoryId"] = .string(cat) }
        return args
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["quickAdd"] as? Data,
              let req = WatchQuickAddRequest.decode(data) else { return }
        Task { @MainActor in
            guard !self.seenQuickAddIds.contains(req.id) else { return }
            self.seenQuickAddIds.insert(req.id)
            let store = FinchStore.shared
            do {
                try store.apply(.addTransaction, Args(Self.quickAddArgs(req, date: store.today)))
                // The fresh snapshot pushed back to the watch IS the confirmation
                // (and refreshes the recents + the complication).
                WidgetSnapshotWriter.write(from: store)
            } catch {
                // Deleted account/ledger or the duplicate guard — drop. The watch
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
