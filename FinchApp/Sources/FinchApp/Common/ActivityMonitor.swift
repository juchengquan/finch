import SwiftUI

/// Resets the biometric idle clock on any user interaction, app-wide, WITHOUT
/// consuming the interaction. The previous approach — a root
/// `.simultaneousGesture(TapGesture())` — swallowed taps on `List` rows /
/// `NavigationLink`s (SwiftUI gesture arbitration let the container's tap win),
/// so tapping an account did nothing while swipes still worked. Observing at the
/// platform layer avoids the conflict entirely.
///
/// Invisible: add it to the view tree (e.g. in the root ZStack) and it wires a
/// passive observer that calls `BiometricGate.shared.noteActivity()`.
struct ActivityMonitor: View {
    var body: some View { Representable().frame(width: 0, height: 0).accessibilityHidden(true) }
}

#if os(iOS)
import UIKit

private struct Representable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView { ProbeView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: UIView, context: Context) {}

    /// A zero-size, non-interactive view that attaches a tap recognizer to its
    /// window once it joins the hierarchy. `cancelsTouchesInView = false` +
    /// simultaneous recognition means it never steals touches from controls.
    final class ProbeView: UIView {
        private let coordinator: Coordinator
        private weak var installedOn: UIWindow?
        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, window !== installedOn else { return }
            installedOn = window
            let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.fire))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = coordinator
            window.addGestureRecognizer(tap)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func fire() { MainActor.assumeIsolated { BiometricGate.shared.noteActivity() } }
        // Recognize alongside everything else — never block a control's own gesture.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
#else
import AppKit

/// macOS: a passive local event monitor. It returns the event unchanged, so it
/// observes clicks/keys without consuming them.
private struct Representable: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { context.coordinator.start(); return NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private var monitor: Any?
        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown, .scrollWheel]) { event in
                MainActor.assumeIsolated { BiometricGate.shared.noteActivity() }
                return event
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}
#endif
