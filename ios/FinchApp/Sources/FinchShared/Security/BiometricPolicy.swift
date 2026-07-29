import Foundation

/// When the app requires biometric re-auth (Phase 6.3).
public enum BiometricPolicy: String, Codable, Sendable, CaseIterable {
    case off, onLaunch, onBackground, onIdle
    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .onLaunch: return "On launch"
        case .onBackground: return "After background"
        case .onIdle: return "After idle"
        }
    }
}

/// The user's lock configuration. Device-local (UserDefaults), NOT ledger data —
/// a biometric policy should not travel in an exported pack to another device.
/// (The design filed this under app_state; the divergence is noted in
/// `_PHASE_6_PART1_OPEN_QUESTIONS.md`.)
public struct BiometricSettings: Codable, Sendable, Equatable {
    public var policy: BiometricPolicy = .off
    public var timeoutSeconds: Int = 300
    public var sensitiveActionsEnabled: Bool = true
    public static let `default` = BiometricSettings()

    private static let key = "finch.biometric.settings"
    public static func load() -> BiometricSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(BiometricSettings.self, from: data) else { return .default }
        return s
    }
    public func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Pure lock-decision (the tested core; the LAContext evaluation is the untested
/// shell over it). Given the policy + session/lifecycle timestamps, should the
/// app be locked right now?
public enum LockDecision {
    public static func shouldLock(policy: BiometricPolicy, hasUnlockedThisSession: Bool,
                                  backgroundedAt: Date?, lastActivityAt: Date, now: Date,
                                  timeoutSeconds: Int) -> Bool {
        switch policy {
        case .off:
            return false
        case .onLaunch:
            return !hasUnlockedThisSession
        case .onBackground:
            if !hasUnlockedThisSession { return true }
            if let b = backgroundedAt { return now.timeIntervalSince(b) > Double(timeoutSeconds) }
            return false
        case .onIdle:
            if !hasUnlockedThisSession { return true }
            return now.timeIntervalSince(lastActivityAt) > Double(timeoutSeconds)
        }
    }
}
