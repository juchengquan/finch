import SwiftUI

/// A button inside `.swipeActions` — the SwiftUI counterpart of `SwipeAction.make`.
///
/// It exists for the haptic **and its order**: the action runs first and the tap
/// follows, because a buzz in front of the work puts the Taptic Engine's warm-up
/// between the gesture and what it does. Keeping that in one type means the rule
/// cannot drift across the swipe actions the SwiftUI screens define.
///
/// Deliberately NOT used for context-menu items, which look identical at the call
/// site: a menu item is chosen from a list that is already open, so there is no
/// gesture to confirm and the menu dismissing is its own feedback.
///
/// `.tint` and `.disabled` stay at the call site — they vary per action and SwiftUI
/// applies them to this view exactly as it would to the `Button` it wraps.
struct SwipeButton: View {
    private let titleKey: LocalizedStringKey
    private let systemImage: String
    private let action: () -> Void

    init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button {
            action()
            // After, never before.
            Haptics.tap()
        } label: {
            Label(titleKey, systemImage: systemImage)
        }
    }
}
