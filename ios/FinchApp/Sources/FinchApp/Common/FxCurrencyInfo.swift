import Foundation

/// Localized currency names + signs for the Currencies page. The symbol table
/// is built once by scanning available locales (shortest distinct symbol per
/// code wins — "€", not "EUR"); labels are memoized per code so 145-row list
/// refreshes and search keystrokes don't re-hit Locale.
@MainActor
enum FxCurrencyInfo {
    private static var labelCache: [String: String] = [:]

    private static let symbolByCode: [String: String] = {
        var best: [String: String] = [:]
        for id in Locale.availableIdentifiers {
            let loc = Locale(identifier: id)
            guard let code = loc.currency?.identifier, let sym = loc.currencySymbol else { continue }
            if sym == code { continue }   // "CHF" as its own symbol is not a sign
            if let cur = best[code], cur.count <= sym.count { continue }
            best[code] = sym
        }
        return best
    }()

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static func symbol(_ code: String) -> String? {
        symbolByCode[code.uppercased()]
    }

    /// "Euro (€)" — bracket omitted when no distinct symbol exists.
    static func label(_ code: String) -> String {
        if let hit = labelCache[code] { return hit }
        let n = name(code)
        let l = symbol(code).map { "\(n) (\($0))" } ?? n
        labelCache[code] = l
        return l
    }
}
