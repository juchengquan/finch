/// The five slots in the iPhone bottom tab bar. The first four mirror `AppTab`;
/// `.more` is the custom overflow tab hosting Settings — replacing SwiftUI's
/// system "More" tab (which dropped titles / doubled the back button).
/// (Activity is no longer a bottom-bar tab — its feed lives inside Accounts.)
/// See plans/ios-macos/2026-06-21-compact-more-tab-design.md.
enum CompactTab: Hashable {
    case ledger, accounts, budgets, scheduled, insights, more
}

/// Pure bridge logic between `DeepLinkRouter.selectedTab` (an `AppTab`) and the
/// compact bottom bar's `CompactTab` selection + the More tab's push path. Kept
/// free of SwiftUI so it is unit-testable (mirrors `LockDecision`).
enum CompactTabRouting {
    /// The bottom-bar slot to highlight for a given app tab. Settings lives
    /// under `.more`.
    static func compactTab(for tab: AppTab) -> CompactTab {
        switch tab {
        case .ledger:   return .ledger
        case .accounts: return .accounts
        case .activity: return .ledger   // the activity feed lives in the Ledger tab now
        case .budgets:  return .budgets
        case .scheduled: return .scheduled
        case .insights: return .insights
        case .settings: return .more
        }
    }

    /// The app tab a primary slot maps to, or `nil` for `.more` (no single tab).
    static func appTab(for compact: CompactTab) -> AppTab? {
        switch compact {
        case .ledger:    return .ledger
        case .accounts:  return .accounts
        case .budgets:   return .budgets
        case .scheduled: return .scheduled
        case .insights:  return .insights
        case .more:      return nil
        }
    }

    /// The overflow screen to push in the More tab for a given app tab, or `nil`
    /// if it isn't an overflow screen.
    static func overflowTab(for tab: AppTab) -> AppTab? {
        switch tab {
        case .settings: return tab
        default: return nil
        }
    }

    /// Sync the compact UI to a (possibly programmatic) router selection. Returns
    /// the bottom-bar slot and the More tab's push path. If the target overflow
    /// screen is already the path tail, the path is preserved (don't stomp a
    /// deeper navigation state).
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
