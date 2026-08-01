import SwiftUI

#if os(iOS)
/// A `Toggle` whose LABEL is not a hit target — only the switch itself flips it.
///
/// WHY. SwiftUI's stock `Toggle` makes the whole row the control, so tapping anywhere on
/// "Group by month" flips it. Settings.app does not do this: tapping the text of a switch
/// row does nothing, and the row does not even highlight. iOS matches Settings.app now —
/// the converted UIKit screens gave up their row-tap at the same time — their switch rows
/// simply stopped being selectable, see `ToggleAccessory`. A switch already shows its own state and
/// its own hit target, so the extra invisible target is untidy rather than helpful.
///
/// iOS ONLY, deliberately. FinchMac keeps the stock behaviour, because macOS renders these
/// rows as a leading CHECKBOX (measured, not assumed — an early version of this style used
/// the iOS arrangement on both platforms and visibly moved FinchMac's checkbox across the
/// row), and an AppKit checkbox counting its title as part of its hit area IS the macOS
/// convention. `switchOnlyToggles()` is a no-op off iOS, so the call sites stay uniform.
///
/// ACCESSIBILITY is preserved by `accessibilityRepresentation`: assistive tech still sees
/// one standard `Toggle` — label, on/off value, toggle trait, activation — rather than the
/// two loose elements the hand-rolled `HStack` would otherwise expose. The inner toggles
/// are pinned to `.automatic` so they resolve to the stock switch instead of recursing
/// back into this style.
///
/// Apply it only to toggles with a VISIBLE label. One already using `labelsHidden()` has
/// no label to tap, so it is switch-only already, and the `Spacer` here would just push
/// its switch out of place (`RulesManagerView`, `CurrenciesView`, `InsightsCustomizeSheet`).
struct SwitchOnlyToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.automatic)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.automatic)
        }
    }
}
#endif

extension View {
    /// Apply to a labelled `Toggle` so it is flipped by its switch ONLY — see
    /// `SwitchOnlyToggleStyle`. No-op off iOS.
    func switchOnlyToggles() -> some View {
        #if os(iOS)
        toggleStyle(SwitchOnlyToggleStyle())
        #else
        self
        #endif
    }
}
