import Foundation
import FinchCore

/// Map a thrown error to a user-facing string: an `I18nError`'s localized
/// `message`, or any other error's description. This is the catch arm every
/// write screen repeated verbatim (`catch let e as I18nError { … } catch { … }`).
func i18nMessage(_ error: Error) -> String { (error as? I18nError)?.message ?? "\(error)" }
