import SwiftUI

extension View {
    /// Standard error alert bound to an optional message string. Replaces the
    /// repeated `.alert(title, isPresented: Binding(get/set)) { Button("OK") }
    /// message: { Text(msg) }` boilerplate across the write screens — set the
    /// bound `String?` to a message to present, it clears itself on dismiss.
    func errorAlert(_ message: Binding<String?>,
                    title: LocalizedStringKey = "Couldn't complete that") -> some View {
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// Accent-filled prominent styling for a toolbar confirm/save ✓ button.
    /// `.borderedProminent` is iOS 15+/macOS 12+ safe; on iOS 26 the system
    /// auto-upgrades a prominent toolbar button to prominent Liquid Glass.
    func confirmCheckmarkStyle() -> some View {
        buttonStyle(.borderedProminent).tint(.accentColor)
    }

    /// Restores a full 44×44 tap target on a bare-glyph toolbar button. iOS 26 draws a
    /// toolbar button's glass capsule larger than the glyph's default hit area, and
    /// inside a `.rightSlideDrill` cover the system's automatic hit-target enlargement
    /// isn't applied — so a *click* near the visual (glass) edge misses the action (the
    /// button highlights but doesn't fire). Apply to the button's icon/label.
    ///
    /// PAIR with `.toolbarCircleClip()` on the enclosing `Button`/`Menu`: the 44×44
    /// frame otherwise makes iOS render the glass as a rounded-rect instead of the
    /// circle it uses for a small glyph (`.buttonBorderShape(.circle)` does NOT
    /// override the toolbar glass; a clip does). Grouped buttons stay a pill either
    /// way. iOS-only; macOS toolbars size differently.
    @ViewBuilder
    func toolbarTapTarget() -> some View {
        #if os(iOS)
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
        #else
        self
        #endif
    }

    /// The circle clip that pairs with `toolbarTapTarget()` — see it. Applied to the
    /// enclosing `Button`/`Menu`. iOS-only: on macOS `toolbarTapTarget()` adds no
    /// frame, so there's no rounded-rect to correct and clipping would only crop the
    /// natural toolbar button.
    @ViewBuilder
    func toolbarCircleClip() -> some View {
        #if os(iOS)
        clipShape(.circle)
        #else
        self
        #endif
    }

    /// The app-wide gap between grouped `List`/`Form` sections (`Metrics.sectionSpacing`) —
    /// tune it in one place (`Common/Metrics.swift`). Set once at `AdaptiveShell` for the
    /// main tabs (inherited via the environment); `.sheet` content does NOT inherit that,
    /// so apply this explicitly on each multi-section sheet's `Form`. iOS-only —
    /// `listSectionSpacing` is unavailable on macOS, so this no-ops there (callers don't
    /// need their own `#if os(iOS)`).
    @ViewBuilder
    func finchSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(Metrics.sectionSpacing)
        #else
        self
        #endif
    }

    /// The standard add/edit-sheet `Form` treatment: the app-wide section gap plus a
    /// pinned top margin under the nav bar. Without the explicit margin, SwiftUI gives
    /// these sheets different default top insets (Budget/Scheduled/Account render ~29pt
    /// lower than the transaction sheets), which is why the family looked inconsistent.
    /// Tune both values in `Common/Metrics.swift`.
    func finchSheetForm() -> some View {
        finchSectionSpacing()
            .contentMargins(.top, Metrics.sheetTopMargin, for: .scrollContent)
    }
}
