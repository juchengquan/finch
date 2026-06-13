import XCTest
@testable import FinchApp

/// Phase 6.3 — the pure lock-decision (the tested core; the LAContext prompt is
/// the untested shell over it).
final class LockDecisionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_offNeverLocks() {
        XCTAssertFalse(LockDecision.shouldLock(policy: .off, hasUnlockedThisSession: false,
            backgroundedAt: nil, lastActivityAt: t0, now: t0, timeoutSeconds: 300))
    }

    func test_onLaunchLocksUntilUnlocked() {
        XCTAssertTrue(LockDecision.shouldLock(policy: .onLaunch, hasUnlockedThisSession: false,
            backgroundedAt: nil, lastActivityAt: t0, now: t0, timeoutSeconds: 300))
        XCTAssertFalse(LockDecision.shouldLock(policy: .onLaunch, hasUnlockedThisSession: true,
            backgroundedAt: nil, lastActivityAt: t0, now: t0, timeoutSeconds: 300))
    }

    func test_onBackgroundLocksAfterTimeout() {
        // Unlocked, backgrounded 6 min ago, 5-min timeout → lock.
        XCTAssertTrue(LockDecision.shouldLock(policy: .onBackground, hasUnlockedThisSession: true,
            backgroundedAt: t0, lastActivityAt: t0, now: t0.addingTimeInterval(360), timeoutSeconds: 300))
        // Backgrounded only 2 min ago → still unlocked.
        XCTAssertFalse(LockDecision.shouldLock(policy: .onBackground, hasUnlockedThisSession: true,
            backgroundedAt: t0, lastActivityAt: t0, now: t0.addingTimeInterval(120), timeoutSeconds: 300))
        // Cold launch (never unlocked) → lock.
        XCTAssertTrue(LockDecision.shouldLock(policy: .onBackground, hasUnlockedThisSession: false,
            backgroundedAt: nil, lastActivityAt: t0, now: t0, timeoutSeconds: 300))
    }

    func test_onIdleLocksAfterInactivity() {
        XCTAssertTrue(LockDecision.shouldLock(policy: .onIdle, hasUnlockedThisSession: true,
            backgroundedAt: nil, lastActivityAt: t0, now: t0.addingTimeInterval(400), timeoutSeconds: 300))
        XCTAssertFalse(LockDecision.shouldLock(policy: .onIdle, hasUnlockedThisSession: true,
            backgroundedAt: nil, lastActivityAt: t0, now: t0.addingTimeInterval(100), timeoutSeconds: 300))
    }

    func test_settingsRoundTrip() {
        var s = BiometricSettings.default
        s.policy = .onBackground; s.timeoutSeconds = 900; s.sensitiveActionsEnabled = false
        s.save()
        let loaded = BiometricSettings.load()
        XCTAssertEqual(loaded.policy, .onBackground)
        XCTAssertEqual(loaded.timeoutSeconds, 900)
        XCTAssertFalse(loaded.sensitiveActionsEnabled)
        BiometricSettings.default.save()   // reset for other tests
    }
}
