import Foundation

/// Watch CP3 — persisted redelivery guard (per the approved CP3 spec §3).
/// `transferUserInfo` can redeliver on failure paths and across app relaunches,
/// so processed request ids live in a bounded ring in UserDefaults rather than
/// memory. Pure Foundation — compiles for FinchMac too (unused there).
final class QuickAddDedupe {
    private let defaults: UserDefaults
    private let key = "finch.watch.processedQuickAddIds"
    private let capacity: Int

    init(defaults: UserDefaults = .standard, capacity: Int = 200) {
        self.defaults = defaults
        self.capacity = capacity
    }

    /// True exactly once per id; records it, evicting the oldest past capacity.
    func firstSeen(_ id: String) -> Bool {
        var ids = defaults.stringArray(forKey: key) ?? []
        guard !ids.contains(id) else { return false }
        ids.append(id)
        if ids.count > capacity { ids.removeFirst(ids.count - capacity) }
        defaults.set(ids, forKey: key)
        return true
    }
}
