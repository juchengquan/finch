import Foundation
import FinchCore

/// Map a thrown error to a user-facing string: an `I18nError` localized for the
/// device language (zh via ErrorL10n, else the English fallback), or any other
/// error's description. The catch arm every write screen shares.
func i18nMessage(_ error: Error) -> String {
    guard let e = error as? I18nError else { return "\(error)" }
    if Locale.current.language.languageCode?.identifier == "zh", let zh = ErrorL10n.zh[e.code] {
        return zh
    }
    return e.message
}
