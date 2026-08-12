import SwiftUI

/// The fixed per-field icon + color vocabulary for the add/edit write sheets.
/// One glyph and one color per field, defined once. The glyph is the row's
/// persistent identity (the visible text label is dropped once a value is set),
/// so it must be stable per field, never value-reflecting. Colors are system/
/// semantic colors so light + dark + macOS all resolve for free.
///
/// Lives beside `TxnKindIcon` / `CategoryIcon` in the app icon vocabulary.
enum FieldGlyph {
    case account, fromAccount, toAccount, amount, category, date, merchant
    case note, status, tags, receipt, refund, name, group, frequency, currency, color, icon
    case card

    var symbol: String {
        switch self {
        case .account:                return "building.columns"
        case .fromAccount:            return "arrow.up.circle"
        case .toAccount:              return "arrow.down.circle"
        case .amount:                 return "dollarsign.circle"
        case .category:               return "folder"
        case .date:                   return "calendar"
        case .frequency:              return "arrow.triangle.2.circlepath"
        case .merchant:               return "storefront"
        case .note:                   return "note.text"
        case .status:                 return "checkmark.circle"
        case .tags:                   return "tag"
        case .receipt:
            #if os(macOS)
            return "paperclip"
            #else
            return "camera"
            #endif
        case .refund:                 return "arrow.uturn.backward.circle"
        case .name:                   return "textformat"
        case .group:                  return "folder.badge.gearshape"
        case .currency:               return "dollarsign.arrow.circlepath"
        case .color:                  return "paintpalette"
        case .icon:                   return "star"
        case .card:                   return "creditcard"
        }
    }

    var tint: Color {
        switch self {
        case .account, .fromAccount, .toAccount: return .blue
        case .card:                              return .blue
        case .amount:                            return .green
        case .category:                          return .orange
        case .date, .frequency:                  return .red
        case .merchant:                          return .purple
        case .note, .name:                       return .secondary
        case .status:                            return .teal
        case .tags:                              return .pink
        case .receipt, .refund:                  return .indigo
        case .group:                             return .brown
        case .currency, .color, .icon:           return .mint
        }
    }
}
