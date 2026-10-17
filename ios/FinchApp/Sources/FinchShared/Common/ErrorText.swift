import Foundation
import FinchCore

/// Map a thrown error to a user-facing string: an `I18nError` localized for the
/// device language (zh via ErrorL10n, else the English fallback), or any other
/// error's description. The catch arm every write screen shares.
func i18nMessage(_ error: Error) -> String {
    i18nMessage(error, zh: Locale.current.language.languageCode?.identifier == "zh")
}

/// The language split out so tests can pin it. A zh string's `{name}`-style
/// placeholders are filled from the error's params, as the web's `t(code, params)`
/// does; returned verbatim they showed as literal braces.
func i18nMessage(_ error: Error, zh: Bool) -> String {
    guard let e = error as? I18nError else { return "\(error)" }
    guard zh, let template = ErrorL10n.zh[e.code] else { return e.message }
    return e.params.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
}
