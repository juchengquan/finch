import Foundation

/// Persists which Accounts-tab groups are *collapsed*, per ledger (keyed by
/// ledger id + group name) in UserDefaults. Storing the collapsed set — not the
/// expanded set — makes the default (absent) expanded, so untouched and
/// newly-created groups show open. Per-ledger so same-named groups in different
/// ledgers don't share state. `defaults` is injectable for tests.
enum AccountGroupCollapse {
    private static let base = "finch.accounts.collapsedGroups"
    private static func key(_ ledgerId: String) -> String { "\(base).\(ledgerId)" }

    static func collapsed(ledger ledgerId: String, _ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.array(forKey: key(ledgerId)) as? [String] ?? [])
    }

    static func isCollapsed(_ group: String, ledger ledgerId: String, _ defaults: UserDefaults = .standard) -> Bool {
        collapsed(ledger: ledgerId, defaults).contains(group)
    }

    static func setCollapsed(_ group: String, _ isCollapsed: Bool, ledger ledgerId: String, _ defaults: UserDefaults = .standard) {
        var set = self.collapsed(ledger: ledgerId, defaults)
        if isCollapsed { set.insert(group) } else { set.remove(group) }
        defaults.set(Array(set), forKey: key(ledgerId))
    }
}
