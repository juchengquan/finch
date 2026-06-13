#if os(macOS)
import SwiftUI

/// Phase 3 (Mac) — shims the iOS-only SwiftUI modifiers the shared views use so
/// they compile unchanged for the macOS target. Each is a no-op or the nearest
/// macOS equivalent; no call-site edits required. Compiled ONLY on macOS.

public enum UIKeyboardTypeShim { case `default`, decimalPad, numberPad, emailAddress, URL, asciiCapable, numbersAndPunctuation }
public enum TextInputAutocapitalizationShim { case never, characters, words, sentences }
public struct NavBarTitleDisplayModeShim { public static let inline = NavBarTitleDisplayModeShim(); public static let large = NavBarTitleDisplayModeShim(); public static let automatic = NavBarTitleDisplayModeShim() }

public extension View {
    func keyboardType(_ : UIKeyboardTypeShim) -> some View { self }
    func textInputAutocapitalization(_ : TextInputAutocapitalizationShim?) -> some View { self }
    func navigationBarTitleDisplayMode(_ : NavBarTitleDisplayModeShim) -> some View { self }
}

public extension ToolbarItemPlacement {
    static var bottomBar: ToolbarItemPlacement { .automatic }
    static var topBarLeading: ToolbarItemPlacement { .navigation }
}
#endif
