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
