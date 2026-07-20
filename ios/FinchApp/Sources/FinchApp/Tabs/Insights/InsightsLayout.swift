import Foundation

/// The persisted Insights dashboard layout. `order` holds **all** catalog card
/// ids in the user's display order (so every card — shown or hidden — is
/// reorderable), and `hidden` marks the ones toggled off (kept in `order`, just
/// not rendered). There are no preset templates — the user decides via the
/// Customize sheet. `RawRepresentable` so it lives in `@AppStorage` as JSON.
struct InsightsLayout: Codable, Equatable, RawRepresentable {
    var order: [String]
    var hidden: Set<String>

    /// The curated first-run / "Reset to default" set that starts *visible*;
    /// every other catalog card starts hidden (still present + reorderable).
    static let defaultShown = ["tips", "monthlySpending", "savingsRate", "netWorth", "categoryBreakdown", "forecast"]

    // Seed the order from the curated shown set (in that order); the init below
    // appends the remaining catalog cards after it — those are the hidden ones.
    static let `default` = InsightsLayout(
        order: defaultShown,
        hidden: Set(InsightsCatalog.all.map(\.id)).subtracting(defaultShown))

    /// Shown card ids in display order — what the dashboard renders.
    var shownOrder: [String] { order.filter { !hidden.contains($0) } }

    /// Normalizes to the catalog: drops unknown ids, appends any new catalog
    /// cards at the end (shown by default), and clamps `hidden` to known ids.
    init(order: [String], hidden: Set<String>) {
        let known = InsightsCatalog.all.map(\.id)
        let knownSet = Set(known)
        self.order = order.filter { knownSet.contains($0) } + known.filter { !order.contains($0) }
        self.hidden = hidden.intersection(knownSet)
    }

    // Explicit Codable witnesses (see below) — the round-trip is (order, hidden).
    private enum CodingKeys: String, CodingKey { case order, hidden }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedOrder = try c.decode([String].self, forKey: .order)
        if let h = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) {
            self.init(order: decodedOrder, hidden: h)
        } else {
            // Legacy layout (`order` held only the *shown* ids): everything the
            // old order omitted was hidden.
            self.init(order: decodedOrder,
                      hidden: Set(InsightsCatalog.all.map(\.id)).subtracting(decodedOrder))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
        try c.encode(hidden, forKey: .hidden)
    }

    // RawRepresentable (JSON) for @AppStorage. NOTE: the hand-written Codable
    // witnesses above are required — a type that is both `Codable` and
    // `RawRepresentable where RawValue: Encodable` otherwise picks up the stdlib
    // default that encodes via `self.rawValue`, which re-encodes `self` → infinite
    // recursion (a real stack-overflow crash). Concrete witnesses win over it.
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
