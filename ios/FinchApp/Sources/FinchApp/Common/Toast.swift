import SwiftUI

/// A transient, non-blocking confirmation banner — the counterpart to
/// `errorAlert` for things that went RIGHT and don't warrant a dismissal tap.
///
/// Presented once at app root (`.toastOverlay()` in `FinchApp`), driven from
/// anywhere via `ToastCenter.shared.show(...)`. Deliberately not part of
/// `FinchStore`: this is view feedback, not ledger state, and it must not ride
/// the projection republish.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var message: LocalizedStringKey?

    /// How long a toast stays up. Long enough to read a short count, short
    /// enough that it never sits over content the user is trying to act on.
    private static let visibleFor = Duration.milliseconds(2200)

    private var dismissal: Task<Void, Never>?

    private init() {}

    /// Show `message`, replacing any toast already on screen (the newest event
    /// is the relevant one) and restarting the dismissal clock.
    func show(_ message: LocalizedStringKey) {
        self.message = message
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }   // superseded by a newer toast
            self?.message = nil
        }
    }
}

/// Renders the active toast above everything else. Applied ONCE, at app root.
private struct ToastOverlay: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = center.message {
                    Text(message)
                        .font(.subheadline)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.quaternary))
                        // Just enough to lift the capsule off scrolling content.
                        // The material and the hairline already draw the edge, so a
                        // heavier shadow (this was radius 8 at SwiftUI's default 33%
                        // black) only added a halo on top of work already done.
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                        // Clear of the compact tab bar, which the overlay sits over.
                        .padding(.bottom, 92)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        // Spoken on appear; not focusable, since it self-dismisses
                        // and there is nothing to interact with.
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .animation(.spring(duration: 0.3), value: center.message != nil)
    }
}

extension View {
    /// Host the app-wide toast. Apply once, at the root.
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
