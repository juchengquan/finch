/// The slots in the iPhone bottom tab bar. The five primaries are Accounts,
/// Budgets, Scheduled, Insights, Settings; `.more` is the corner-pushed overflow
/// role, carrying the two-layer Ledger reached from the top-left control.
/// (Activity is not a bottom-bar tab — its feed lives inside Accounts.)
/// See plans/ios-macos/2026-06-27-nav-settings-ledger-swap-spec.md.
enum CompactTab: Hashable {
    case accounts, budgets, scheduled, insights, settings, more
}

/// Pure bridge logic between `DeepLinkRouter.selectedTab` (an `AppTab`) and the
/// compact bottom bar's `CompactTab` selection + the corner push path. Kept free
/// of SwiftUI so it is unit-testable. Settings is a primary slot; the Ledger is
/// the corner-pushed overflow.
enum CompactTabRouting {
    /// The bottom-bar slot to highlight for a given app tab. Ledger is corner-
    /// pushed (`.more`); Settings is a primary slot; the Activity feed lives in
    /// Accounts.
    static func compactTab(for tab: AppTab) -> CompactTab {
        switch tab {
        case .settings:  return .settings
        case .accounts:  return .accounts
        case .budgets:   return .budgets
        case .scheduled: return .scheduled
        case .insights:  return .insights
        case .ledger:    return .more        // corner-pushed overflow
        case .activity:  return .accounts    // the activity feed lives in the Accounts tab now
        }
    }

    /// The app tab a primary slot maps to, or `nil` for `.more` (corner-pushed).
    static func appTab(for compact: CompactTab) -> AppTab? {
        switch compact {
        case .accounts:  return .accounts
        case .budgets:   return .budgets
        case .scheduled: return .scheduled
        case .insights:  return .insights
        case .settings:  return .settings
        case .more: return nil
        }
    }

    /// The corner-pushed screen for a given app tab, or `nil` if it isn't one.
    static func overflowTab(for tab: AppTab) -> AppTab? {
        switch tab {
        case .ledger: return tab
        default: return nil
        }
    }

    /// Sync the compact UI to a (possibly programmatic) router selection. Returns
    /// the bottom-bar slot and the corner push path. If the target overflow screen
    /// is already the path tail, the path is preserved (don't stomp deeper state).
    static func sync(routerTab: AppTab, currentPath: [AppTab]) -> (selected: CompactTab, path: [AppTab]) {
        if let overflow = overflowTab(for: routerTab) {
            let path = currentPath.last == overflow ? currentPath : [overflow]
            return (.more, path)
        }
        return (compactTab(for: routerTab), [])
    }

    /// The value to write to `router.selectedTab` when the user taps a slot, or
    /// `nil` to leave it unchanged (tapped `.more`, or already matching).
    static func routerTab(forSelected selected: CompactTab, current routerTab: AppTab) -> AppTab? {
        guard let mapped = appTab(for: selected), mapped != routerTab else { return nil }
        return mapped
    }
}
