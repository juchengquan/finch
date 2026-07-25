import Foundation

/// Typed navigation destinations used across all tab `NavigationStack`s.
///
/// On iPhone, `LedgerListView` is pushed onto each tab's stack via `ledgerPush()`.
/// Without typed wrappers, having multiple `.navigationDestination(for: String.self)`
/// registrations causes SwiftUI to silently keep only one — the others become unreachable.
/// Using distinct enum cases fixes this: each case is its own unique type at runtime.
enum AppDestination: Hashable {
    case account(id: String)
    case budget(id: String)
    case ledger(id: String)
}
