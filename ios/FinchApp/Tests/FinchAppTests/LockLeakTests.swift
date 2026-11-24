import XCTest
import FinchCore
@testable import FinchApp

/// The lock and what it hides.
@MainActor
final class LockLeakTests: XCTestCase {

    /// "After background", one minute. Away 30 s and back: no lock, as it should be.
    /// Ninety seconds later the scene becomes active again (Control Center, a system
    /// prompt) without ever going to the background. That is no trip away, so no
    /// lock — but the 30-second trip's mark was kept and by then read as 120 s ago.
    func test_aReturnThatDoesNotLockEndsTheTripAway() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func locks(_ mark: Date?, at seconds: Double) -> Bool {
            LockDecision.shouldLock(policy: .onBackground, hasUnlockedThisSession: true, backgroundedAt: mark,
                                    lastActivityAt: t0, now: t0.addingTimeInterval(seconds), timeoutSeconds: 60)
        }
        var mark: Date? = t0                                  // didEnterBackground
        XCTAssertFalse(locks(mark, at: 30))                   // back after 30 s
        mark = BiometricGate.backgroundMark(mark, afterActivationLocked: false)
        XCTAssertFalse(locks(mark, at: 120), "re-activated mid-use, never backgrounded again")
        XCTAssertTrue(locks(t0, at: 120), "what the kept mark did")
        // A return that DID lock keeps the mark until unlock clears it.
        XCTAssertEqual(BiometricGate.backgroundMark(t0, afterActivationLocked: true), t0)
    }

    /// With a lock set, Spotlight's transaction items carry no amount: it answers
    /// while the app is locked, and the clear only happened at the next foreground.
    func test_spotlightHidesAmountsWhileALockIsSet() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        store.privacyMode = false
        let gate = BiometricGate.shared
        let saved = gate.settings
        defer { gate.settings = saved }

        func amounts() -> [String] {
            SpotlightSnapshot(store: store).entities().compactMap {
                if case .transaction(_, _, let amount) = $0 { return amount }
                return nil
            }
        }
        var off = saved; off.policy = .off
        gate.settings = off
        XCTAssertFalse(amounts().isEmpty)
        XCTAssertFalse(amounts().contains(FinchStore.moneyMask), "no lock, no Hide amounts: figures are searchable")

        var on = saved; on.policy = .onBackground
        gate.settings = on
        XCTAssertEqual(Set(amounts()), [FinchStore.moneyMask])
    }
}
