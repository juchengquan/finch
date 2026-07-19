import SwiftUI

/// Cross-platform searchable placement: on iOS the search bar stays visible
/// (`.navigationBarDrawer(displayMode: .always)`); default placement on macOS.
/// Shared by the Categories and Tags admin pages.
struct SearchableModifier: ViewModifier {
    @Binding var text: String
    func body(content: Content) -> some View {
        #if os(iOS)
        content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
        #else
        content.searchable(text: $text)
        #endif
    }
}
