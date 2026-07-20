import Foundation
import SwiftUI

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

/// Color for an account `type` — one palette shared by the Accounts rows and the
/// Insights net-worth-by-type allocation bar, so "account type ↔ color" reads the
/// same everywhere. (credit_card and unknown types fall back to secondary.)
enum AccountTypeColor {
    static func color(for type: String?) -> Color {
        switch type {
        case "cash":       .green
        case "savings":    .blue
        case "investment": .purple
        case "fx":         .teal
        case "virtual":    .gray
        default:           Color.secondary
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

/// SF Symbol for a category `icon` short-name. Short-names are stored verbatim in
/// the `.finch` pack; we map to SF Symbols only at render. The original 12 mirror
/// the web's shared set — the rest are **native-only** additions (the web renders
/// an unknown name as its 'tag' fallback, exactly as we do here for nil/unknown).
/// The picker presents them in themed `groups`; `names` is the flat union.
/// Unknown / nil → "tag.fill" (web's 'tag' fallback).
enum CategoryIcon {
    /// One themed section of the icon picker (see `CategoryEditSheet`).
    struct Group: Identifiable {
        let title: String
        let names: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Food & Drink",      names: ["fork", "cup", "mug", "cart", "wineglass", "takeout", "carrot", "leaf", "cake"]),
        Group(title: "Shopping",          names: ["bag", "handbag", "tshirt", "gift", "giftcard", "tag", "sparkles", "creditcard", "box"]),
        Group(title: "Transport",         names: ["car", "fuel", "plane", "tram", "bus", "ferry", "bike", "scooter", "parking"]),
        Group(title: "Home & Bills",      names: ["home", "key", "bolt", "drop", "flame", "wifi", "phone", "wrench", "sofa", "trash"]),
        Group(title: "Health & Fitness",  names: ["heart", "pills", "cross", "bandage", "stethoscope", "dumbbell", "run", "yoga"]),
        Group(title: "Entertainment",     names: ["film", "tv", "music", "headphones", "game", "book", "school", "camera", "ticket"]),
        Group(title: "Personal",          names: ["pet", "child", "couple", "friends", "scissors", "person", "crown"]),
        Group(title: "Money & Work",      names: ["briefcase", "coins", "cash", "wallet", "chart", "bank", "office", "doc", "calendar", "sync", "percent"]),
    ]

    /// Flat union of every group's names, in display order.
    static let names = groups.flatMap(\.names)

    static func symbol(for name: String?) -> String {
        switch name {
        // Food & Drink
        case "fork":        "fork.knife"
        case "cup":         "cup.and.saucer.fill"
        case "mug":         "mug.fill"
        case "cart":        "cart.fill"
        case "wineglass":   "wineglass.fill"
        case "takeout":     "takeoutbag.and.cup.and.straw.fill"
        case "carrot":      "carrot.fill"
        case "leaf":        "leaf.fill"
        case "cake":        "birthday.cake.fill"
        // Shopping
        case "bag":         "bag.fill"
        case "handbag":     "handbag.fill"
        case "tshirt":      "tshirt.fill"
        case "gift":        "gift.fill"
        case "giftcard":    "giftcard.fill"
        case "tag":         "tag.fill"
        case "sparkles":    "sparkles"
        case "creditcard":  "creditcard.fill"
        case "box":         "shippingbox.fill"
        // Transport
        case "car":         "car.fill"
        case "fuel":        "fuelpump.fill"
        case "plane":       "airplane"
        case "tram":        "tram.fill"
        case "bus":         "bus.fill"
        case "ferry":       "ferry.fill"
        case "bike":        "bicycle"
        case "scooter":     "scooter"
        case "parking":     "parkingsign.circle.fill"
        // Home & Bills
        case "home":        "house.fill"
        case "key":         "key.fill"
        case "bolt":        "bolt.fill"
        case "drop":        "drop.fill"
        case "flame":       "flame.fill"
        case "wifi":        "wifi"
        case "phone":       "phone.fill"
        case "wrench":      "wrench.and.screwdriver.fill"
        case "sofa":        "sofa.fill"
        case "trash":       "trash.fill"
        // Health & Fitness
        case "heart":       "heart.fill"
        case "pills":       "pills.fill"
        case "cross":       "cross.case.fill"
        case "bandage":     "bandage.fill"
        case "stethoscope": "stethoscope"
        case "dumbbell":    "dumbbell.fill"
        case "run":         "figure.run"
        case "yoga":        "figure.yoga"
        // Entertainment
        case "film":        "film.fill"
        case "tv":          "tv.fill"
        case "music":       "music.note"
        case "headphones":  "headphones"
        case "game":        "gamecontroller.fill"
        case "book":        "book.fill"
        case "school":      "graduationcap.fill"
        case "camera":      "camera.fill"
        case "ticket":      "ticket.fill"
        // Personal
        case "pet":         "pawprint.fill"
        case "child":       "figure.and.child.holdinghands"
        case "couple":      "figure.2"
        case "friends":     "person.2.fill"
        case "scissors":    "scissors"
        case "person":      "figure.stand"
        case "crown":       "crown.fill"
        // Money & Work
        case "briefcase":   "briefcase.fill"
        case "coins":       "dollarsign.circle.fill"
        case "cash":        "banknote.fill"
        case "wallet":      "wallet.pass.fill"
        case "chart":       "chart.pie.fill"
        case "bank":        "building.columns.fill"
        case "office":      "building.2.fill"
        case "doc":         "doc.fill"
        case "calendar":    "calendar"
        case "sync":        "arrow.triangle.2.circlepath"
        case "percent":     "percent"
        default:            "tag.fill"
        }
    }
}
