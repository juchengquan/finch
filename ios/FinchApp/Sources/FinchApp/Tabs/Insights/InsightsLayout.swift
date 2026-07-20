import Foundation

/// The persisted Insights dashboard layout: the enabled card ids, in display
/// order. There are no preset "templates" — the user decides via the Customize
/// sheet; this is their choice. `RawRepresentable` so it can live in
/// `@AppStorage` as a JSON string.
struct InsightsLayout: Codable, Equatable, RawRepresentable {
    var order: [String]

    /// The curated first-run / "Reset to default" set — a focused starter, not
    /// every card (avoids the old 14-card firehose).
    static let defaultOrder = ["tips", "monthlySpending", "savingsRate", "netWorth", "categoryBreakdown", "forecast"]

    static let `default` = InsightsLayout(order: defaultOrder)

    init(order: [String]) { self.order = order }

    // Explicit Codable witnesses: without these, the compiler prefers the
    // stdlib's `Encodable` default for `RawRepresentable where RawValue:
    // Encodable` (which encodes via `self.rawValue`) over synthesizing
    // member-wise coding — and `rawValue` below encodes `self`, so that
    // default recurses infinitely (verified via a stack-overflow crash).
    // Hand-writing these gives a concrete witness that wins over the
    // extension default, breaking the cycle.
    private enum CodingKeys: String, CodingKey { case order }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decode([String].self, forKey: .order)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
    }

    // RawRepresentable (JSON) for @AppStorage
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let v = try? JSONDecoder().decode(InsightsLayout.self, from: data) else { return nil }
        self = v
    }
    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
