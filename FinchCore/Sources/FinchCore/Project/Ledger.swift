import Foundation

/// A ledger (the top-level book). The display field is `base` (NOT `baseCurrency`)
/// to match the web client `Tx`/ledger JSON — see WIRE_FORMAT §2.2. Sourced from
/// the `ledgers` table (`base_currency` column → `base`).
public struct Ledger: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let base: String       // from the `base_currency` column
    public let color: String?
    public let tagline: String?

    public init(id: String, name: String, base: String, color: String?, tagline: String?) {
        self.id = id; self.name = name; self.base = base; self.color = color; self.tagline = tagline
    }
}
