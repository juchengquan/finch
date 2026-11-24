import Foundation
import LocalAuthentication

/// Phase 6.3 — the optional biometric lock. Drives `isLocked` from the policy +
/// app lifecycle, and runs the Face ID / Touch ID / passcode prompt
/// (`LAPolicy.deviceOwnerAuthentication`, so the device passcode is the system
/// fallback — finch implements no passcode of its own). If the device can't
/// evaluate any policy (no biometrics/passcode, e.g. a bare simulator), the gate
/// stays unlocked rather than trapping the user.
@MainActor
public final class BiometricGate: ObservableObject {
    public static let shared = BiometricGate()

    @Published public private(set) var isLocked: Bool = false
    @Published public var settings: BiometricSettings = .load() {
        didSet {
            settings.save(); reevaluate()
            // With a lock set, Spotlight holds no amounts (`SpotlightSnapshot`), so
            // turning it on or off re-indexes.
            if (oldValue.policy == .off) != (settings.policy == .off) {
                Task { await SpotlightIndexer.shared.indexAll(store: FinchStore.shared) }
            }
        }
    }

    private var hasUnlockedThisSession = false
    private var backgroundedAt: Date?
    private var lastActivityAt = Date()

    /// Call once at launch.
    public func start() { reevaluate() }

    /// Record a user interaction — resets the `.onIdle` clock. Called from the
    /// shell's root tap gesture.
    public func noteActivity() { lastActivityAt = Date() }

    /// Re-check the lock state. Called by the foreground idle timer so an
    /// `.onIdle` timeout actually fires while the app stays open (the lifecycle
    /// hooks alone never re-evaluate a still-foregrounded app).
    public func tick() {
        guard settings.policy == .onIdle, hasUnlockedThisSession else { return }
        reevaluate()
    }

    public func didEnterBackground() { backgroundedAt = Date() }

    public func didBecomeActive() {
        reevaluate()
        backgroundedAt = Self.backgroundMark(backgroundedAt, afterActivationLocked: isLocked)
    }

    /// The background mark once the app is active again. A return that did NOT
    /// lock ends that trip away, so the mark goes. Kept, it kept counting: the next
    /// time the scene became active — Control Center, the Face ID prompt — the time
    /// since that OLD trip passed the timeout and locked the app in the middle of
    /// use. A return that locked keeps it until `unlock`, which clears it.
    nonisolated static func backgroundMark(_ mark: Date?, afterActivationLocked locked: Bool) -> Date? {
        locked ? mark : nil
    }

    private func reevaluate() {
        guard canAuthenticate else { isLocked = false; return }
        isLocked = LockDecision.shouldLock(
            policy: settings.policy, hasUnlockedThisSession: hasUnlockedThisSession,
            backgroundedAt: backgroundedAt, lastActivityAt: lastActivityAt,
            now: Date(), timeoutSeconds: settings.timeoutSeconds)
    }

    /// Whether the device can evaluate biometrics or passcode at all.
    public var canAuthenticate: Bool {
        if settings.policy == .off { return false }
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    /// Run the system auth prompt; on success, unlock for this session.
    public func unlock() async {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            isLocked = false; return   // can't evaluate → don't trap the user
        }
        let ok = (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                localizedReason: "Unlock finch")) ?? false
        if ok {
            hasUnlockedThisSession = true
            backgroundedAt = nil
            lastActivityAt = Date()
            isLocked = false
        }
    }

    /// Gate a sensitive action (export, delete-all, change base). Returns true to
    /// proceed. No-op (allows) when the device can't evaluate or the toggle is off.
    public func confirmSensitive() async -> Bool {
        guard settings.sensitiveActionsEnabled, settings.policy != .off else { return true }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                              localizedReason: "Confirm with Face ID")) ?? false
    }
}
