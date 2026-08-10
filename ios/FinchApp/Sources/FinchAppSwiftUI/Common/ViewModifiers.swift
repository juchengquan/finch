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

    /// The sheet family's tighter section gap. Same macOS no-op as above.
    @ViewBuilder
    func finchSheetSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(Metrics.sheetSectionSpacing)
        #else
        self
        #endif
    }

    /// Applied to the type-caption `Section` itself, this overrides the sheet's
    /// section gap for that ONE gap (`Metrics.captionSectionSpacing`) so the
    /// caption sits against the card it names. `listSectionSpacing` honours a
    /// per-Section value on top of the List-wide one — measured, iOS 17+.
    /// Same macOS no-op as above.
    @ViewBuilder
    func finchCaptionSection() -> some View {
        #if os(iOS)
        listSectionSpacing(.custom(Metrics.captionSectionSpacing))
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
        finchSheetSectionSpacing()
            .contentMargins(.top, Metrics.sheetTopMargin, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, Metrics.sheetRowMinHeight)
    }
}

extension View {
    /// Pin this row's divider to the card's own leading edge rather than to the row's
    /// text — the SwiftUI half of `Metrics.rowSeparatorInset`.
    ///
    /// By default iOS aligns a divider to where the TEXT above it starts, skipping any
    /// leading icon, so rows with different leading content give different dividers. On
    /// Accounts that produced three (40 / 52 / 68pt) and the 52→68 step inside one card
    /// is what reads as broken. Returning the content's own leading edge puts every
    /// divider at the same place.
    ///
    /// The UIKit screens do this through `UIListSeparatorConfiguration`; this keeps the
    /// SwiftUI screens — macOS, and the `-uikitActivity NO` control — drawing the same,
    /// so the control stays a clean baseline for visual diffs.
    func finchRowDividerInset() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}
