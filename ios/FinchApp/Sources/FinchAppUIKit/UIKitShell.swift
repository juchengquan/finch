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
    private var cancellables = Set<AnyCancellable>()

    private let store = FinchStore.shared
    private let router = DeepLinkRouter.shared
    private let gate = BiometricGate.shared

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let w = UIWindow(windowScene: windowScene)
        if UserDefaults.standard.bool(forKey: "legacyShell") {
            w.rootViewController = UIHostingController(rootView: AppRootHost())
        } else {
            w.rootViewController = RootTabBarController()
        }
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
        handle(connectionOptions: options)
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
