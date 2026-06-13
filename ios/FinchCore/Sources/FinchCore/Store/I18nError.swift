import Foundation

/// Structured, translatable error thrown by the write chokepoint — a port of
/// the web's `lib/i18n-error.ts::I18nError`. Carries a translation `code`, string
/// `params`, and an English fallback `message` (so untranslated surfaces still
/// show something human-readable). The web allows numeric params too; here they
/// are stringified at the call site.
public struct I18nError: Error, Equatable, Sendable {
    public let code: String
    public let params: [String: String]
    public let message: String

    public init(_ code: String, _ params: [String: String] = [:], _ fallbackEnglish: String? = nil) {
        self.code = code
        self.params = params
        self.message = fallbackEnglish ?? code
    }
}
