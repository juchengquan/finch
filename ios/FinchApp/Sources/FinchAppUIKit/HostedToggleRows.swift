#if os(iOS)
import SwiftUI

/// Settings rows whose switch is drawn by SwiftUI rather than by `UISwitch`.
///
/// WHY THIS EXISTS. UIKit cannot draw iOS 26's switch appearance. `UISwitchStyle`
/// offers only `.automatic`, `.checkbox` (Catalyst) and `.sliding` — the classic
/// look — and `UIGlassEffect` is a `UIVisualEffect` for `UIVisualEffectView`
/// backdrops, not a way to restyle a control's thumb and track. So a `UISwitch`
/// accessory sits next to SwiftUI's glass switch looking visibly older, which is
/// exactly what a side-by-side comparison on a device surfaced.
///
/// Letting SwiftUI draw the switch is the only way to match, and it costs nothing:
/// these rows carry no behaviour beyond the toggle itself.
struct HostedToggleRow: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: onChange))
    }
}

/// A row that BOTH navigates and carries a toggle — the Currencies and Rules rows.
///
/// SwiftUI does exactly this natively (a `NavigationLink` whose label contains a
/// `Toggle`), so the two coexist happily. The important part on the UIKit side is
/// that the cell must be NON-selectable: the tap is handled by the button in here,
/// because a selectable cell would swallow the switch's touches — the same trap the
/// Categories mode picker hit.
struct HostedToggleNavigationRow<Label: View>: View {
    let isOn: Bool
    /// Announced by the SWITCH only. Applying it to the whole row leaks it onto the
    /// navigation button as well, so VoiceOver reads two "Activate CAD" elements.
    let toggleLabel: String
    let onChange: (Bool) -> Void
    let onTap: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: toggleLabel))
        }
    }
}
#endif
