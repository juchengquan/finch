import Foundation

/// SF Symbol for an account `type`. The real schema types are
/// savings/credit_card/investment/cash/fx/virtual (accounts table CHECK) —
/// NOT checking/credit. Default: "banknote".
enum AccountTypeIcon {
    static func icon(for type: String?) -> String {
        switch type {
        case "savings":     "building.columns"
        case "credit_card": "creditcard"
        case "investment":  "chart.line.uptrend.xyaxis"
        case "cash":        "banknote"
        case "fx":          "dollarsign.arrow.circlepath"
        case "virtual":     "circle.dashed"
        default:            "banknote"
        }
    }
}

/// SF Symbol for a transaction `kind` (a string on `Tx`, optional — nil falls
/// back to a neutral circle; the row tints by amount sign separately).
enum TxnKindIcon {
    static func icon(for kind: String?) -> String {
        switch kind {
        case "income":     "arrow.down.left.circle"
        case "expense":    "arrow.up.right.circle"
        case "transfer":   "arrow.left.arrow.right.circle"
        case "adjustment": "slider.horizontal.3"
        case "refund":     "arrow.uturn.left.circle"
        default:           "circle"
        }
    }
}
