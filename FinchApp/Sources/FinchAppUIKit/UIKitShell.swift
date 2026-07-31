#if os(iOS)
import UIKit
import SwiftUI
import CoreSpotlight
import Combine
import FinchCore

// MARK: - Phase 1 of the UIKit migration: the app's UIKit root
//
// The iOS app's entry point is now UIKit — `UIApplicationDelegate` → `UIWindow` →
// `UITabBarController` → per-tab `UINavigationController`. `FinchMac` keeps the
// SwiftUI `App` (FinchApp.swift, excluded from the iOS target in project.yml).
//
// Every screen is still SwiftUI, hosted. That is deliberate: this phase changes
// the ROOT only, so it must be behaviour-identical. Screens convert in Phase 2.
//
// `-legacyShell YES` falls back to hosting `AdaptiveShell` whole, which is the
// pre-migration behaviour — an escape hatch while the two shells coexist.

@main
final class UIKitAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
    }
}

final class MainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var lockWindow: UIWindow?
    private var idleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let store = FinchStore.shared
    private let router = DeepLinkRouter.shared
    private let gate = BiometricGate.shared

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let w = UIWindow(windowScene: windowScene)
        w.rootViewController = Self.makeRoot(for: w)
        applyAppearancePreference(to: w)
        w.makeKeyAndVisible()
        window = w

        // The SwiftUI entry point ran all of this from `.task`; it is the same work
        // in the same order, just not tied to a view's lifetime.
        Task { @MainActor in
            store.isHydrating = true
            store.bootstrap()
            PhoneWatchLink.shared.activate()
            gate.start()
            if !gate.isLocked {
                await SpotlightIndexer.shared.indexAll(store: store)
            }
            store.isHydrating = false
            NotificationService.shared.configure(store: store, router: router)
            await NotificationService.shared.requestPermissionIfNeeded()
            await NotificationService.shared.refresh()
            AutoBackupManager.shared.configure(store: store)
            ICloudSync.shared.start()
            await CloudKitSyncCoordinator.shared.start()
            PendingAttachmentImporter.importPending(into: store)
        }

        observeLock()
        observeAppearance()
        startIdleTimer()
        installActivityMonitor(on: w)
        installGlobalOverlay(on: w)
        handle(connectionOptions: options)
    }

    /// The old shell switched on `horizontalSizeClass`: compact got the tab bar,
    /// regular got the three-column split. Phase 1 replaced only the compact
    /// branch, so a wide window must keep the SwiftUI shell — otherwise iPad loses
    /// its split view and gets the phone layout, which is a real regression, not a
    /// cosmetic one. Phase 3 replaces this with a UISplitViewController.
    private static func makeRoot(for window: UIWindow) -> UIViewController {
        let wide = window.traitCollection.horizontalSizeClass == .regular
        if wide || UserDefaults.standard.bool(forKey: "legacyShell") {
            return UIHostingController(rootView: AppRootHost())
        }
        return RootTabBarController()
    }

    /// iPad multitasking changes the size class at runtime (Split View, Slide Over),
    /// so the root has to be able to swap. Rebuilding is acceptable here because
    /// all state lives in the store and the router, not in the view tree.
    func windowScene(_ windowScene: UIWindowScene,
                     didUpdate previousCoordinateSpace: UICoordinateSpace,
                     interfaceOrientation: UIInterfaceOrientation,
                     traitCollection previousTraitCollection: UITraitCollection) {
        guard let w = window else { return }
        let wasWide = previousTraitCollection.horizontalSizeClass == .regular
        let isWide = w.traitCollection.horizontalSizeClass == .regular
        guard wasWide != isWide else { return }
        w.rootViewController = Self.makeRoot(for: w)
        installGlobalOverlay(on: w)
    }

    // MARK: Scene phase — the `.onChange(of: scenePhase)` block

    func sceneDidEnterBackground(_ scene: UIScene) {
        gate.didEnterBackground()
        Task { await AutoBackupManager.shared.backupIfDue() }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        gate.didBecomeActive()
        if !gate.isLocked {
            Task { await RateAutoUpdater.refreshIfDue(store: store) }
        }
    }

    // MARK: Deep links, Spotlight, Siri

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { router.handle(url) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if userActivity.activityType == CSSearchableItemActionType,
           let id = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            router.route(to: id)
        }
    }

    private func handle(connectionOptions options: UIScene.ConnectionOptions) {
        if let url = options.urlContexts.first?.url { router.handle(url) }
        for activity in options.userActivities where activity.activityType == CSSearchableItemActionType {
            if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                router.route(to: id)
            }
        }
    }

    // MARK: The biometric lock
    //
    // SECURITY: in SwiftUI the lock was a `ZStack` sibling, so it simply drew over
    // the shell. In UIKit it must be its OWN WINDOW at a higher level — a child
    // view controller would sit below any presented sheet, leaving account data
    // visible over the lock. This is the migration's one genuine security gate.

    private func observeLock() {
        gate.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locked in
                guard let self else { return }
                if locked {
                    self.router.showCommandPalette = false
                    self.router.showAddTransaction = false
                    self.router.pendingAddAccountId = nil
                    self.router.pendingAddCategoryId = nil
                    self.presentLockWindow()
                } else {
                    self.dismissLockWindow()
                }
                Task {
                    if locked { await SpotlightIndexer.shared.clearAll() }
                    else { await SpotlightIndexer.shared.indexAll(store: self.store) }
                }
            }
            .store(in: &cancellables)
    }

    private func presentLockWindow() {
        guard lockWindow == nil, let scene = window?.windowScene else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1        // above every sheet and alert
        w.rootViewController = UIHostingController(rootView: LockView().environmentObject(gate))
        applyAppearancePreference(to: w)
        w.makeKeyAndVisible()
        lockWindow = w
    }

    private func dismissLockWindow() {
        lockWindow?.isHidden = true
        lockWindow = nil
        window?.makeKeyAndVisible()
    }

    // MARK: App-wide behaviours the SwiftUI root used to provide
    //
    // Phase 1 replaced the root but initially dropped these. They are not
    // cosmetic: the idle timer and the activity monitor together are what make
    // the `.onIdle` biometric lock policy fire at all.

    /// `Timer.publish(every: 30) { gate.tick() }` in the SwiftUI root.
    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.gate.tick()
        }
    }

    /// `ActivityMonitor()` — a passive touch observer that resets the idle clock
    /// without consuming the interaction. It is a UIKit probe underneath, so the
    /// SwiftUI wrapper is not needed: attach the same recognizer to the window.
    private func installActivityMonitor(on window: UIWindow) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(noteActivity))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func noteActivity() { gate.noteActivity() }

    /// The app-wide toast layer and the import/hydrate progress HUD, both of which
    /// the SwiftUI root hosted. A transparent, non-interactive hosting controller
    /// over the shell keeps them in one place rather than per tab.
    private func installGlobalOverlay(on window: UIWindow) {
        let host = UIHostingController(rootView: GlobalOverlay().environmentObject(store))
        host.view.backgroundColor = .clear
        guard let root = window.rootViewController else { return }
        root.addChild(host)
        host.view.frame = root.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.isUserInteractionEnabled = false
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
    }

    /// The appearance preference is live in SwiftUI (`preferredColorScheme` reads
    /// `@AppStorage`); here it must be re-applied when the setting changes.
    private func observeAppearance() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let w = self.window else { return }
                self.applyAppearancePreference(to: w)
                self.lockWindow.map { self.applyAppearancePreference(to: $0) }
            }
            .store(in: &cancellables)
    }

    /// `preferredColorScheme` in SwiftUI; `overrideUserInterfaceStyle` here.
    private func applyAppearancePreference(to window: UIWindow) {
        let raw = UserDefaults.standard.string(forKey: "finch.appearance")
        switch AppearancePreference(rawValue: raw ?? "") {
        case .light: window.overrideUserInterfaceStyle = .light
        case .dark:  window.overrideUserInterfaceStyle = .dark
        default:     window.overrideUserInterfaceStyle = .unspecified
        }
    }
}

/// The gesture must observe without consuming, exactly like `ActivityMonitor`.
extension MainSceneDelegate: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
}

/// The app-wide toast layer plus the import/hydrate HUD — the two overlays the
/// SwiftUI root carried in its ZStack.
private struct GlobalOverlay: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .overlay {
                if store.isImporting || store.isHydrating {
                    ProgressView(store.isImporting ? "Importing…" : "Loading…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .toastOverlay()
    }
}

/// `-legacyShell YES`: the pre-migration behaviour, the whole SwiftUI shell hosted.
/// Kept as an escape hatch while both shells coexist.
private struct AppRootHost: View {
    @StateObject private var store = FinchStore.shared
    @StateObject private var router = DeepLinkRouter.shared
    @StateObject private var gate = BiometricGate.shared
    var body: some View {
        AdaptiveShell()
            .environmentObject(store)
            .environmentObject(router)
            .environmentObject(gate)
    }
}
#endif
