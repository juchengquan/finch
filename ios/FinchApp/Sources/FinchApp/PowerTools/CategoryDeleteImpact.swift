import Foundation

/// Human-readable impact line for deleting a category, or `nil` when there is
/// nothing to warn about (a leaf with no transactions deletes silently).
///
/// - `txCount`: the category's OWN direct transactions — they become
///   uncategorized. Its subcategories keep their own transactions.
/// - `subcatCount`: the category's direct children — they move to top level.
///
/// Clauses join with " · "; each is omitted when its count is 0. Strings are
/// intentionally non-pluralized to match the shared copy / zh-Hans batch.
func deleteImpactMessage(txCount: Int, subcatCount: Int) -> String? {
    var clauses: [String] = []
    if txCount > 0 {
        clauses.append(String(localized: "\(txCount) transactions will become uncategorized"))
    }
    if subcatCount > 0 {
        clauses.append(String(localized: "\(subcatCount) subcategories move to top level"))
    }
    return clauses.isEmpty ? nil : clauses.joined(separator: " · ")
}
