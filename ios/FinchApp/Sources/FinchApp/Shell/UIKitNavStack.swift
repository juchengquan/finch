#if os(iOS)
import SwiftUI
import UIKit

/// Resolves the active UINavigationController from the window hierarchy.
func resolveUIKitNav() -> UINavigationController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.keyWindow?.rootViewController
    else { return nil }
    var top: UIViewController? = root
    if let tab = root as? UITabBarController { top = tab.selectedViewController }
    while let vc = top {
        if let nav = vc as? UINavigationController { return nav }
        top = vc.children.first
    }
    return root as? UINavigationController
}

/// Pushes `view` onto the active UINavigationController with env injected.
func pushViaUIKit<Content: View>(_ view: Content,
                                  store: FinchStore,
                                  router: DeepLinkRouter,
                                  gate: BiometricGate) {
    guard let nav = resolveUIKitNav() else { return }
    let vc = UIHostingController(rootView: view
        .environmentObject(store)
        .environmentObject(router)
        .environmentObject(gate))
    nav.pushViewController(vc, animated: true)
}

/// Drop-in NavigationLink replacement that pushes via UIKit.
struct UIKitNavLink<Label: View, Destination: View>: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var gate: BiometricGate
    private let destination: () -> Destination
    private let label: () -> Label

    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination; self.label = label
    }

    var body: some View {
        Button {
            pushViaUIKit(destination(), store: store, router: router, gate: gate)
        } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

// MARK: - UIKitNavStack

/// Replaces SwiftUI `NavigationStack` on compact iOS. Wraps a
/// `UINavigationController` + `UIHostingController` so ALL pushes go through
/// UIKit `pushViewController` — avoiding the iOS 26 resume shadow entirely.
struct UIKitNavStack<Root: View>: UIViewControllerRepresentable {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var gate: BiometricGate

    private let root: Root
    private let navTitle: String
    private let trailingItems: [UIBarButtonItem]

    init(title: String,
         trailingItems: [UIBarButtonItem] = [],
         @ViewBuilder root: () -> Root) {
        self.root = root()
        self.navTitle = title
        self.trailingItems = trailingItems
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UINavigationController {
        let c = context.coordinator
        c.store = store; c.router = router; c.gate = gate
        let rootVC = UIHostingController(rootView: root)
        rootVC.title = navTitle
        c.installToolbar(on: rootVC, extras: trailingItems)
        let nav = UINavigationController(rootViewController: rootVC)
        nav.navigationBar.prefersLargeTitles = true
        c.nav = nav
        return nav
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {
        context.coordinator.store = store
        context.coordinator.router = router
        context.coordinator.gate = gate
        if let top = vc.topViewController {
            context.coordinator.installToolbar(on: top, extras: trailingItems)
        }
    }

    final class Coordinator {
        weak var nav: UINavigationController?
        var store: FinchStore?; var router: DeepLinkRouter?; var gate: BiometricGate?

        func push(_ view: AnyView) {
            guard let store, let router, let gate else { return }
            let vc = UIHostingController(rootView: view
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(gate))
            nav?.pushViewController(vc, animated: true)
        }

        func popToRoot() { nav?.popToRootViewController(animated: true) }

        @objc func openLedger() { DispatchQueue.main.async { [weak self] in self?.router?.showLedger = true } }
        @objc func togglePrivacy() { DispatchQueue.main.async { [weak self] in self?.store?.privacyMode.toggle() } }

        func installToolbar(on vc: UIViewController, extras: [UIBarButtonItem]) {
            vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "books.vertical"), style: .plain,
                target: self, action: #selector(Coordinator.openLedger))
            vc.navigationItem.leftBarButtonItem?.accessibilityLabel = "Ledger"

            DispatchQueue.main.async { [weak self] in
                guard let self, let store = self.store else { return }
                let eyeIcon = store.privacyMode ? "eye.slash" : "eye"
                var items = extras
                items.append(UIBarButtonItem(
                    image: UIImage(systemName: eyeIcon), style: .plain,
                    target: self, action: #selector(Coordinator.togglePrivacy)))
                items.last?.accessibilityLabel = "Privacy mode"
                vc.navigationItem.rightBarButtonItems = items
            }
        }
    }
}

// MARK: - Ledger push

struct LedgerPushUIKitModifier: ViewModifier {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var gate: BiometricGate

    func body(content: Content) -> some View {
        content.onChange(of: router.showLedger) { _, show in
            if show { pushViaUIKit(LedgerListView(), store: store, router: router, gate: gate); router.showLedger = false }
        }
    }
}

extension View {
    func ledgerPushUIKit() -> some View { modifier(LedgerPushUIKitModifier()) }
}
#endif
