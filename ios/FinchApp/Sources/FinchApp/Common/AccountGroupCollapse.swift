import Foundation

/// Persists which Accounts-tab groups are *collapsed* (keyed by group name) in
/// UserDefaults. Storing the collapsed set — not the expanded set — makes the
/// default (absent) expanded, so untouched and newly-created groups show open.
/// Mirrors the `NotificationPrefs` UserDefaults pattern; `defaults` is injectable
/// for tests.
enum AccountGroupCollapse {
    static let key = "finch.accounts.collapsedGroups"

    static func collapsed(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.array(forKey: key) as? [String] ?? [])
    }

    static func isCollapsed(_ group: String, _ defaults: UserDefaults = .standard) -> Bool {
        collapsed(defaults).contains(group)
    }

    static func setCollapsed(_ group: String, _ isCollapsed: Bool, _ defaults: UserDefaults = .standard) {
        var set = self.collapsed(defaults)
        if isCollapsed { set.insert(group) } else { set.remove(group) }
        defaults.set(Array(set), forKey: key)
    }
}
