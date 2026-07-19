import Foundation

/// Human-readable impact line for deleting a category, or `nil` when there is
/// nothing to warn about (a leaf with no transactions deletes silently).
///
/// - `txCount`: the category's OWN direct transactions — they become
///   uncategorized. Its subcategories keep their own transactions.
/// - `subcatCount`: the category's direct children — they move to top level.
///
/// Clauses join with " · "; each is omitted when its count is 0. Singular and
/// plural (including verb agreement) are spelled out explicitly so a count of 1
/// reads grammatically.
func deleteImpactMessage(txCount: Int, subcatCount: Int) -> String? {
    var clauses: [String] = []
    if txCount > 0 {
        clauses.append(txCount == 1
            ? String(localized: "1 transaction will become uncategorized")
            : String(localized: "\(txCount) transactions will become uncategorized"))
    }
    if subcatCount > 0 {
        clauses.append(subcatCount == 1
            ? String(localized: "1 subcategory moves to top level")
            : String(localized: "\(subcatCount) subcategories move to top level"))
    }
    return clauses.isEmpty ? nil : clauses.joined(separator: " · ")
}
