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
        /// Already in the reader's language.
        let title: String
        let names: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: String(localized: "Food & Drink"),      names: ["fork", "cup", "mug", "cart", "wineglass", "takeout", "fish", "carrot", "leaf", "water", "cake"]),
        Group(title: String(localized: "Shopping"),          names: ["bag", "handbag", "tshirt", "jewelry", "gift", "giftcard", "tag", "sparkles", "creditcard", "laptop", "box"]),
        Group(title: String(localized: "Transport"),         names: ["car", "fuel", "charging", "plane", "tram", "bus", "ferry", "bike", "scooter", "truck", "parking"]),
        Group(title: String(localized: "Travel"),            names: ["hotel", "suitcase", "map", "beach", "mountain", "globe", "tent"]),
        Group(title: String(localized: "Home & Bills"),      names: ["home", "key", "bolt", "drop", "flame", "wifi", "phone", "wrench", "paint", "sofa", "light", "washer", "tree", "trash"]),
        Group(title: String(localized: "Health & Fitness"),  names: ["heart", "pills", "cross", "bandage", "stethoscope", "checkup", "vision", "dumbbell", "run", "swim", "yoga", "wellness", "mental", "sports"]),
        Group(title: String(localized: "Entertainment"),     names: ["film", "tv", "streaming", "music", "headphones", "podcast", "game", "book", "school", "camera", "art", "concert", "theater", "ticket"]),
        Group(title: String(localized: "Tech & Comms"),      names: ["mail", "message", "computer", "device", "cloud", "printer"]),
        Group(title: String(localized: "Personal"),          names: ["pet", "child", "baby", "couple", "friends", "toy", "balloon", "scissors", "person", "crown"]),
        Group(title: String(localized: "Money & Work"),      names: ["briefcase", "coins", "cash", "wallet", "chart", "analytics", "growth", "crypto", "bank", "office", "insurance", "doc", "receipt", "calendar", "goal", "sync", "percent", "charity"]),
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
        case "fish":        "fish.fill"
        case "carrot":      "carrot.fill"
        case "leaf":        "leaf.fill"
        case "water":       "waterbottle.fill"
        case "cake":        "birthday.cake.fill"
        // Shopping
        case "bag":         "bag.fill"
        case "handbag":     "handbag.fill"
        case "jewelry":     "diamond.fill"
        case "tshirt":      "tshirt.fill"
        case "gift":        "gift.fill"
        case "giftcard":    "giftcard.fill"
        case "tag":         "tag.fill"
        case "sparkles":    "sparkles"
        case "creditcard":  "creditcard.fill"
        case "laptop":      "laptopcomputer"
        case "box":         "shippingbox.fill"
        // Transport
        case "car":         "car.fill"
        case "fuel":        "fuelpump.fill"
        case "charging":    "bolt.car.fill"
        case "plane":       "airplane"
        case "tram":        "tram.fill"
        case "bus":         "bus.fill"
        case "ferry":       "ferry.fill"
        case "bike":        "bicycle"
        case "scooter":     "scooter"
        case "truck":       "truck.box.fill"
        case "parking":     "parkingsign.circle.fill"
        // Travel
        case "hotel":       "bed.double.fill"
        case "suitcase":    "suitcase.fill"
        case "map":         "map.fill"
        case "beach":       "beach.umbrella.fill"
        case "mountain":    "mountain.2.fill"
        case "globe":       "globe.americas.fill"
        case "tent":        "tent.fill"
        // Home & Bills
        case "home":        "house.fill"
        case "key":         "key.fill"
        case "bolt":        "bolt.fill"
        case "drop":        "drop.fill"
        case "flame":       "flame.fill"
        case "wifi":        "wifi"
        case "phone":       "phone.fill"
        case "wrench":      "wrench.and.screwdriver.fill"
        case "paint":       "paintbrush.fill"
        case "sofa":        "sofa.fill"
        case "light":       "lightbulb.fill"
        case "washer":      "washer.fill"
        case "tree":        "tree.fill"
        case "trash":       "trash.fill"
        // Health & Fitness
        case "heart":       "heart.fill"
        case "pills":       "pills.fill"
        case "cross":       "cross.case.fill"
        case "bandage":     "bandage.fill"
        case "stethoscope": "stethoscope"
        case "checkup":     "heart.text.square.fill"
        case "vision":      "eye.fill"
        case "mental":      "brain.head.profile"
        case "dumbbell":    "dumbbell.fill"
        case "run":         "figure.run"
        case "swim":        "figure.pool.swim"
        case "yoga":        "figure.yoga"
        case "wellness":    "figure.mind.and.body"
        case "sports":      "sportscourt.fill"
        // Entertainment
        case "film":        "film.fill"
        case "tv":          "tv.fill"
        case "streaming":   "play.rectangle.fill"
        case "music":       "music.note"
        case "headphones":  "headphones"
        case "podcast":     "mic.fill"
        case "game":        "gamecontroller.fill"
        case "book":        "book.fill"
        case "school":      "graduationcap.fill"
        case "camera":      "camera.fill"
        case "art":         "paintpalette.fill"
        case "concert":     "music.mic"
        case "theater":     "theatermasks.fill"
        case "ticket":      "ticket.fill"
        // Tech & Comms
        case "mail":        "envelope.fill"
        case "message":     "bubble.left.fill"
        case "computer":    "desktopcomputer"
        case "device":      "iphone"
        case "cloud":       "icloud.fill"
        case "printer":     "printer.fill"
        // Personal
        case "pet":         "pawprint.fill"
        case "child":       "figure.and.child.holdinghands"
        case "baby":        "figure.child"
        case "couple":      "figure.2"
        case "friends":     "person.2.fill"
        case "toy":         "teddybear.fill"
        case "balloon":     "balloon.fill"
        case "scissors":    "scissors"
        case "person":      "figure.stand"
        case "crown":       "crown.fill"
        // Money & Work
        case "briefcase":   "briefcase.fill"
        case "coins":       "dollarsign.circle.fill"
        case "cash":        "banknote.fill"
        case "wallet":      "wallet.pass.fill"
        case "chart":       "chart.pie.fill"
        case "analytics":   "chart.bar.fill"
        case "growth":      "chart.line.uptrend.xyaxis"
        case "crypto":      "bitcoinsign.circle.fill"
        case "bank":        "building.columns.fill"
        case "office":      "building.2.fill"
        case "insurance":   "checkmark.shield.fill"
        case "doc":         "doc.fill"
        case "receipt":     "doc.plaintext.fill"
        case "calendar":    "calendar"
        case "goal":        "target"
        case "sync":        "arrow.triangle.2.circlepath"
        case "percent":     "percent"
        case "charity":     "hand.raised.fill"
        default:            "tag.fill"
        }
    }

    /// A short, human-readable name for an icon short-name, shown when the user
    /// taps an icon in the picker. Unknown names fall back to the capitalized id.
    static func label(for name: String) -> String {
        switch name {
        // Food & Drink
        case "fork":        String(localized: "Dining")
        case "cup":         String(localized: "Coffee")
        case "mug":         String(localized: "Tea")
        case "cart":        String(localized: "Groceries")
        case "wineglass":   String(localized: "Drinks")
        case "takeout":     String(localized: "Takeout")
        case "fish":        String(localized: "Seafood")
        case "carrot":      String(localized: "Produce")
        case "leaf":        String(localized: "Organic")
        case "water":       String(localized: "Water")
        case "cake":        String(localized: "Celebration")
        // Shopping
        case "bag":         String(localized: "Shopping")
        case "handbag":     String(localized: "Accessories")
        case "jewelry":     String(localized: "Jewelry")
        case "tshirt":      String(localized: "Clothing")
        case "gift":        String(localized: "Gifts")
        case "giftcard":    String(localized: "Gift Card")
        case "tag":         String(localized: "Sale")
        case "sparkles":    String(localized: "Beauty")
        case "creditcard":  String(localized: "Card")
        case "laptop":      String(localized: "Electronics")
        case "box":         String(localized: "Package")
        // Transport
        case "car":         String(localized: "Car")
        case "fuel":        String(localized: "Fuel")
        case "charging":    String(localized: "Charging")
        case "plane":       String(localized: "Travel")
        case "tram":        String(localized: "Transit")
        case "bus":         String(localized: "Bus")
        case "ferry":       String(localized: "Ferry")
        case "bike":        String(localized: "Cycling")
        case "scooter":     String(localized: "Scooter")
        case "truck":       String(localized: "Moving")
        case "parking":     String(localized: "Parking")
        // Travel
        case "hotel":       String(localized: "Hotel")
        case "suitcase":    String(localized: "Luggage")
        case "map":         String(localized: "Map")
        case "beach":       String(localized: "Beach")
        case "mountain":    String(localized: "Outdoors")
        case "globe":       String(localized: "Abroad")
        case "tent":        String(localized: "Camping")
        // Home & Bills
        case "home":        String(localized: "Home")
        case "key":         String(localized: "Rent")
        case "bolt":        String(localized: "Electricity")
        case "drop":        String(localized: "Water")
        case "flame":       String(localized: "Gas")
        case "wifi":        String(localized: "Internet")
        case "phone":       String(localized: "Phone")
        case "wrench":      String(localized: "Repairs")
        case "paint":       String(localized: "Improvement")
        case "sofa":        String(localized: "Furniture")
        case "light":       String(localized: "Lighting")
        case "washer":      String(localized: "Laundry")
        case "tree":        String(localized: "Garden")
        case "trash":       String(localized: "Waste")
        // Health & Fitness
        case "heart":       String(localized: "Health")
        case "pills":       String(localized: "Pharmacy")
        case "cross":       String(localized: "Medical")
        case "bandage":     String(localized: "First Aid")
        case "stethoscope": String(localized: "Doctor")
        case "checkup":     String(localized: "Checkup")
        case "vision":      String(localized: "Vision")
        case "mental":      String(localized: "Mental Health")
        case "dumbbell":    String(localized: "Gym")
        case "run":         String(localized: "Running")
        case "swim":        String(localized: "Swimming")
        case "yoga":        String(localized: "Yoga")
        case "wellness":    String(localized: "Wellness")
        case "sports":      String(localized: "Sports")
        // Entertainment
        case "film":        String(localized: "Movies")
        case "tv":          String(localized: "TV")
        case "streaming":   String(localized: "Streaming")
        case "music":       String(localized: "Music")
        case "headphones":  String(localized: "Audio")
        case "podcast":     String(localized: "Podcasts")
        case "game":        String(localized: "Games")
        case "book":        String(localized: "Books")
        case "school":      String(localized: "Education")
        case "camera":      String(localized: "Photography")
        case "art":         String(localized: "Art")
        case "concert":     String(localized: "Concerts")
        case "theater":     String(localized: "Theater")
        case "ticket":      String(localized: "Events")
        // Tech & Comms
        case "mail":        String(localized: "Mail")
        case "message":     String(localized: "Messages")
        case "computer":    String(localized: "Computer")
        case "device":      String(localized: "Devices")
        case "cloud":       String(localized: "Cloud")
        case "printer":     String(localized: "Printing")
        // Personal
        case "pet":         String(localized: "Pets")
        case "child":       String(localized: "Kids")
        case "baby":        String(localized: "Baby")
        case "couple":      String(localized: "Family")
        case "friends":     String(localized: "Friends")
        case "toy":         String(localized: "Toys")
        case "balloon":     String(localized: "Party")
        case "scissors":    String(localized: "Grooming")
        case "person":      String(localized: "Personal")
        case "crown":       String(localized: "Luxury")
        // Money & Work
        case "briefcase":   String(localized: "Work")
        case "coins":       String(localized: "Money")
        case "cash":        String(localized: "Cash")
        case "wallet":      String(localized: "Wallet")
        case "chart":       String(localized: "Investments")
        case "analytics":   String(localized: "Analytics")
        case "growth":      String(localized: "Growth")
        case "crypto":      String(localized: "Crypto")
        case "bank":        String(localized: "Bank")
        case "office":      String(localized: "Business")
        case "insurance":   String(localized: "Insurance")
        case "doc":         String(localized: "Bills")
        case "receipt":     String(localized: "Receipts")
        case "calendar":    String(localized: "Subscriptions")
        case "goal":        String(localized: "Goals")
        case "sync":        String(localized: "Recurring")
        case "percent":     String(localized: "Interest")
        case "charity":     String(localized: "Donations")
        default:            name.capitalized
        }
    }
}
