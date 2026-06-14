import Foundation

/// A counterparty (merchant). `name` is the canonical merchant name the
/// projection's counterparty-name override writes onto each `Tx.merchant`
/// (so a catalog rename follows through to every transaction).
public struct Counterparty: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let ledgerId: String
    public let name: String
    public let isVerified: Bool

    public init(id: String, ledgerId: String, name: String, isVerified: Bool = false) {
        self.id = id; self.ledgerId = ledgerId; self.name = name; self.isVerified = isVerified
    }
}
