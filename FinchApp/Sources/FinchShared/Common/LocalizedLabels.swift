import Foundation

/// Localized display labels for the string-typed kind/frequency vocabularies
/// the write screens and pickers share. These strings previously rendered via
/// `rawValue.capitalized` / plain `String`s — which bypass the localization
/// extraction entirely, so they shipped English in every language and neither
/// CI i18n guard could notice (the guards only see what `String(localized:)`
/// and `LocalizedStringKey` literals put into the catalog).
enum KindLabel {
    static func label(_ raw: String) -> String {
        switch raw {
        case "expense": String(localized: "Expense")
        case "income": String(localized: "Income")
        case "transfer": String(localized: "Transfer")
        case "refund": String(localized: "Refund")
        case "adjust", "adjustment": String(localized: "Adjust Balance")
        default: raw.capitalized
        }
    }
}

enum FrequencyLabel {
    static func label(_ raw: String) -> String {
        switch raw {
        case "hourly": String(localized: "Hourly")
        case "daily": String(localized: "Daily")
        case "weekly": String(localized: "Weekly")
        case "biweekly": String(localized: "Biweekly")
        case "monthly": String(localized: "Monthly")
        case "quarterly": String(localized: "Quarterly")
        case "yearly": String(localized: "Yearly")
        case "once": String(localized: "Once")
        default: raw.capitalized
        }
    }
}

/// The account types the engine accepts (`cash`, `savings`, `credit_card`,
/// `investment`, `fx`, `virtual`). The type picker and the Insights account list
/// both showed `rawValue.capitalized`, so every type read in English.
enum AccountTypeLabel {
    static func label(_ raw: String?) -> String {
        switch raw {
        case "cash": String(localized: "Cash")
        case "savings": String(localized: "Savings")
        case "credit_card": String(localized: "Credit Card")
        case "investment": String(localized: "Investment")
        case "fx": String(localized: "Foreign Currency")
        case "virtual": String(localized: "Virtual")
        case .some(let s): s.capitalized
        case .none: "—"
        }
    }
}
