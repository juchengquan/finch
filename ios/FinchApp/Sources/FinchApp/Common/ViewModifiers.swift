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
}
