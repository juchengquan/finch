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

/// SF Symbol for a category `icon` short-name. The 12 names mirror the web's
/// shared set (stored verbatim in the pack for cross-platform parity); we map to
/// SF Symbols only at render. Unknown / nil → "tag.fill" (web's 'tag' fallback).
enum CategoryIcon {
    static let names = ["fork", "home", "car", "bag", "film", "heart",
                        "sync", "tag", "coins", "wallet", "chart", "doc"]

    static func symbol(for name: String?) -> String {
        switch name {
        case "fork":   "fork.knife"
        case "home":   "house.fill"
        case "car":    "car.fill"
        case "bag":    "bag.fill"
        case "film":   "film.fill"
        case "heart":  "heart.fill"
        case "sync":   "arrow.triangle.2.circlepath"
        case "tag":    "tag.fill"
        case "coins":  "dollarsign.circle.fill"
        case "wallet": "wallet.pass.fill"
        case "chart":  "chart.pie.fill"
        case "doc":    "doc.fill"
        default:       "tag.fill"
        }
    }
}
