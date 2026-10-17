import SwiftUI
import FinchCore

/// The Undo banner for transaction deletes, SwiftUI edition — the root this
/// hosts it in is the macOS app (`FinchApp`). iOS draws the same offer with
/// `UndoBannerController` (FinchAppUIKit), in its own pass-through window so it
/// can sit over sheets and still take a tap.
///
/// Driven by `FinchStore.deleteUndo`, so every delete path gets it for free;
/// the store owns the timing and the expiry rules.
private struct UndoBannerOverlay: ViewModifier {
    @EnvironmentObject private var store: FinchStore
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let offer = store.deleteUndo {
                    HStack(spacing: 4) {
                        Text(offer.message)
                            .font(.subheadline)
                            .lineLimit(2)
                        Button("Undo") { undo() }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .accessibilityIdentifier("undoDelete")
                    }
                    .padding(.leading, 18).padding(.trailing, 4)
                    .frame(minHeight: 48)
                    .background(.thickMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary))
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(offer.id)
                }
            }
            .animation(.spring(duration: 0.3), value: store.deleteUndo?.id)
            .alert("Couldn't undo", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private func undo() {
        do { try store.undoDelete(); Haptics.success() } catch { failure = i18nMessage(error) }
    }
}

extension View {
    /// Host the transaction-delete Undo banner. Apply once, at the root.
    func undoBannerOverlay() -> some View { modifier(UndoBannerOverlay()) }
}
