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
