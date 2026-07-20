import Foundation

/// Named preset card sets. "Custom" is NOT a case — it's the derived state when
/// a layout matches no template (see `InsightsLayout.matchingTemplate`).
enum InsightsTemplate: String, CaseIterable, Identifiable {
    case overview, spending, wealth, everything
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .spending: return "Spending"
        case .wealth: return "Wealth"
        case .everything: return "Everything"
        }
    }

    var cardIDs: [String] {
        switch self {
        case .overview:   return ["tips", "monthlySpending", "savingsRate", "netWorth", "categoryBreakdown", "forecast"]
        case .spending:   return ["monthlySpending", "categoryBreakdown", "topMerchants", "categoryDeltas", "spendingHeatmap"]
        case .wealth:     return ["netWorth", "netWorthByType", "cashflow", "savingsRate", "whatIf"]
        case .everything: return InsightsCatalog.all.map(\.id)
        }
    }
}

/// The persisted dashboard layout: enabled card ids in display order, plus the
/// template it currently matches (nil == "Custom"). `RawRepresentable` so it can
/// live in `@AppStorage` as a JSON string.
struct InsightsLayout: Codable, Equatable, RawRepresentable {
    var order: [String]
    /// A persisted hint for which preset this came from. NOTE: the menu label is
    /// derived live from `matchingTemplate()` (over `order`), not this field —
    /// keep them in sync when mutating `order` (Phase 2's Customize does via retag).
    var templateName: String?

    static let `default` = InsightsLayout(
        order: InsightsTemplate.overview.cardIDs,
        templateName: InsightsTemplate.overview.rawValue)

    /// The template whose `cardIDs` equal `order` exactly, else nil ("Custom").
    func matchingTemplate() -> InsightsTemplate? {
        InsightsTemplate.allCases.first { $0.cardIDs == order }
    }

    init(order: [String], templateName: String?) { self.order = order; self.templateName = templateName }

    // Explicit Codable witnesses: without these, the compiler prefers the
    // stdlib's `Encodable` default for `RawRepresentable where RawValue:
    // Encodable` (which encodes via `self.rawValue`) over synthesizing
    // member-wise coding — and `rawValue` below encodes `self`, so that
    // default recurses infinitely (verified via a stack-overflow crash).
    // Hand-writing these gives a concrete witness that wins over the
    // extension default, breaking the cycle.
    private enum CodingKeys: String, CodingKey { case order, templateName }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decode([String].self, forKey: .order)
        templateName = try c.decodeIfPresent(String.self, forKey: .templateName)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
        try c.encodeIfPresent(templateName, forKey: .templateName)
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
