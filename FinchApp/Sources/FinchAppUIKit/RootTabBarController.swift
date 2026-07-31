#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// The compact shell's UIKit replacement: a real `UITabBarController` with a
/// `UINavigationController` per tab, each hosting the existing SwiftUI tab root.
///
/// The five slots and their order match `TabBarShell` exactly — Accounts,
/// Budgets, Scheduled, Insights, Settings. Activity is not a slot (it lives
/// inside Accounts) and Ledger is a corner control, as before.
///
/// Two-way binding with `DeepLinkRouter` so App Intents, notifications, Spotlight
/// and the command palette keep driving navigation from outside the view tree.
final class RootTabBarController: UITabBarController {

    private let store = FinchStore.shared
    private let router = DeepLinkRouter.shared
    private var cancellables = Set<AnyCancellable>()

    /// Bar order. `AppTab` has seven cases; only these five are slots.
    private let slots: [AppTab] = [.accounts, .budgets, .scheduled, .insights, .settings]

    /// Tabs whose converted UIKit screens are live. Anything not listed here — and
    /// everything at all while the flag is off — stays a hosted SwiftUI root.
    ///
    /// **Off by default.** Nothing registers a default for this key, so an ordinary
    /// launch is still the all-SwiftUI app; `-uikitActivity YES` opts in.
    ///
    /// **The key's name is historical.** The gate arrived with the Activity feed
    /// (#643) and its original justification was that feed's missing parity — but the
    /// set has long since outgrown that reason. Budgets (#658) and Scheduled (#660)
    /// joined for their own Phase 3b reasons, nothing to do with `ActivityFeedVC`. It
    /// now covers four of the five bar slots; only Insights is untouched. Read it as
    /// "the migration preview", not "the feed".
    ///
    /// `SplitShellVC` reads the same key, so the compact root and the regular-width
    /// column convert together or not at all — see `uikitBudgets` there.
    private static var uikitNavTabs: Set<AppTab> {
        UserDefaults.standard.bool(forKey: "uikitActivity") ? [.accounts, .budgets, .scheduled, .settings] : []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        viewControllers = slots.map { tab in
            // NO UINavigationController wrapper. Each SwiftUI tab root supplies its
            // OWN NavigationStack, so wrapping it double-stacks the bars — two
            // titles, two toolbars. Phase 1 changes the ROOT only and must stay
            // behaviour-identical; a UINavigationController arrives per tab in
            // Phase 2, when that tab's screens are converted and the SwiftUI stack
            // is removed with them.
            // Phase 2: a tab whose screens are being converted gets a real
            // UINavigationController, and its SwiftUI root renders WITHOUT its own
            // NavigationStack (ownsNavigationStack: false) so the bars do not
            // double. Unconverted tabs stay as bare hosted roots.
            // Budgets is native at BOTH widths: the same `BudgetsListVC` is the compact
            // tab root here and the iPad supplementary column in `SplitShellVC`, which
            // is what stops the two from drifting. `TabChromeVC` gives it the FAB and
            // the focused-tx sheet that a hosted root gets for free from `TabChrome`.
            let vc: UIViewController
            if tab == .budgets, Self.uikitNavTabs.contains(tab) {
                let nav = UINavigationController(rootViewController: BudgetsListVC())
                nav.navigationBar.prefersLargeTitles = true
                vc = TabChromeVC(content: nav, tab: tab, store: store, router: router)
            } else if tab == .scheduled, Self.uikitNavTabs.contains(tab) {
                let nav = UINavigationController(rootViewController: ScheduledListVC())
                nav.navigationBar.prefersLargeTitles = true
                vc = TabChromeVC(content: nav, tab: tab, store: store, router: router)
            } else {
                vc = Self.uikitNavTabs.contains(tab)
                    ? navigationTab(tab)
                    : hostedRoot(tab)
            }
            vc.tabBarItem = UITabBarItem(title: tab.title,
                                         image: UIImage(systemName: tab.icon),
                                         tag: slots.firstIndex(of: tab) ?? 0)
            return vc
        }
        bindRouter()
    }

    /// Each tab root is still SwiftUI. The environment objects and the app-wide
    /// section spacing that `AdaptiveShell` applied must be re-attached here —
    /// hosting controllers do not inherit them. (Text size is NOT re-attached: it is
    /// a window-level trait override in `MainSceneDelegate`, which every host
    /// inherits — see `applyTextSizePreference`.)
    private func hostedRoot(_ tab: AppTab) -> UIViewController {
        let host = UIHostingController(rootView:
            TabRootHost(tab: tab)
                .finchSectionSpacing()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(BiometricGate.shared)
        )
        // No `host.title`: the hosted SwiftUI root sets its own navigationTitle.
        return host
    }

    /// A tab backed by a real `UINavigationController`, with the SwiftUI root
    /// rendered stack-less and the native-route seam installed so its drills push
    /// converted view controllers.
    private func navigationTab(_ tab: AppTab) -> UIViewController {
        let nav = UINavigationController()
        let root = UIHostingController(rootView:
            StacklessTabRoot(tab: tab)
                .finchSectionSpacing()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(BiometricGate.shared)
                .environment(\.nativeRoute, { [weak nav] route in
                    guard let nav else { return false }
                    switch route {
                    case .activity:
                        nav.pushViewController(ActivityFeedVC(), animated: true)
                        return true
                    case .account(let id):
                        nav.pushViewController(AccountDetailVC(accountId: id), animated: true)
                        return true
                    case .budget(let id):
                        nav.pushViewController(BudgetDetailVC(budgetId: id), animated: true)
                        return true
                    case .holdings:
                        nav.pushViewController(HoldingsVC(), animated: true)
                        return true
                    case .categories:
                        nav.pushViewController(CategoriesVC(), animated: true)
                        return true
                    case .tags:
                        nav.pushViewController(TagsVC(), animated: true)
                        return true
                    case .merchants:
                        nav.pushViewController(MerchantsVC(), animated: true)
                        return true
                    case .currencies:
                        nav.pushViewController(CurrenciesVC(), animated: true)
                        return true
                    case .powerTools:
                        nav.pushViewController(PowerToolsVC(), animated: true)
                        return true
                    case .appearance:
                        nav.pushViewController(AppearanceSettingsVC(), animated: true)
                        return true
                    case .notifications:
                        nav.pushViewController(NotificationsSettingsVC(), animated: true)
                        return true
                    case .security:
                        nav.pushViewController(SecuritySettingsVC(), animated: true)
                        return true
                    case .backupsSync:
                        nav.pushViewController(BackupSyncSettingsVC(), animated: true)
                        return true
                    case .about:
                        nav.pushViewController(AboutSettingsVC(), animated: true)
                        return true
                    default:
                        // Not converted yet — the screen keeps its own cover.
                        return false
                    }
                })
        )
        nav.setViewControllers([root], animated: false)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }

    // MARK: Router bridge

    /// The ledger cover, natively. Tracked so the router's `showLedger = false` can
    /// dismiss it — the flag is set from several places (the corner button, a `.ledger`
    /// deep link, the tab intercept), and a presentation nobody holds a reference to
    /// cannot be closed by any of them.
    private weak var ledgerNav: UIViewController?

    private func presentLedgers() {
        guard ledgerNav == nil else { return }   // single slot, as the SwiftUI cover had
        let vc = LedgersVC()
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            primaryAction: UIAction { [weak self] _ in self?.router.showLedger = false })
        vc.navigationItem.leftBarButtonItem?.accessibilityLabel = String(localized: "Back")
        RightSlideModal.present(vc, from: self)
        ledgerNav = vc.navigationController
    }

    private func dismissLedgers() {
        guard let nav = ledgerNav else { return }
        ledgerNav = nil
        nav.dismiss(animated: true)
    }

    private func bindRouter() {
        // Router -> bar. A `.ledger` target is not a slot: it is the corner
        // presentation, so the bar settles on a real tab instead (same rule as
        // CompactTabRouting).
        router.$selectedTab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in
                guard let self else { return }
                if tab == .ledger { self.router.showLedger = true; return }
                if let i = self.slots.firstIndex(of: tab), i != self.selectedIndex {
                    self.selectedIndex = i
                }
            }
            .store(in: &cancellables)

        // The ledger flow. It used to be a hosted SwiftUI cover applied in TabChrome —
        // the last hosted scroll view left in this shell. Both of its screens are now
        // UIKit (LedgersVC / LedgerDetailVC), so it presents natively and its pushes
        // are real pushes.
        router.$showLedger
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show { self.presentLedgers() } else { self.dismissLedgers() }
            }
            .store(in: &cancellables)

        // Global sheets, presented from the shell exactly as the SwiftUI root did.
        router.$showAddTransaction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show { self.presentAddTransaction() }
            }
            .store(in: &cancellables)

        router.$showCommandPalette
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show { self.presentCommandPalette() }
            }
            .store(in: &cancellables)

        // A non-recoverable load/migration failure — the SwiftUI `.alert`.
        store.$dataError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self, let message, !message.isEmpty else { return }
                let alert = UIAlertController(title: String(localized: "Data problem"),
                                              message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel) { _ in
                    self.store.dataError = nil
                })
                self.topMost().present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    private func presentAddTransaction() {
        let sheet = UIHostingController(rootView:
            AddTransactionSheet(defaultAccountId: router.pendingAddAccountId,
                                defaultCategoryId: router.pendingAddCategoryId)
                .environmentObject(store)
                .environmentObject(router)
        )
        present(sheet, animated: true)
        // Mirrors the SwiftUI sheet's onDismiss, which cleared the pre-fill.
        sheet.presentationController?.delegate = self
    }

    private func presentCommandPalette() {
        let sheet = UIHostingController(rootView: CommandPalette().environmentObject(router))
        present(sheet, animated: true)
    }

    private func topMost() -> UIViewController {
        var vc: UIViewController = self
        while let p = vc.presentedViewController { vc = p }
        return vc
    }
}

/// iOS 26 cross-dissolves tab content for ~130ms, which reads as a flashing block
/// when the outgoing list is scrolled (see ios26-liquid-glass-artifacts.md, issue 1).
/// The SwiftUI shell had to reach the backing UITabBarController through a
/// forwarding delegate proxy (`DisableTabContentTransition`) to suppress it. We own
/// the controller now, so it is just a delegate method — the proxy can be deleted
/// with the SwiftUI shell.
private final class InstantTabTransition: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0 }
    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        if let to = ctx.view(forKey: .to) { ctx.containerView.addSubview(to) }
        ctx.completeTransition(!ctx.transitionWasCancelled)
    }
}

extension RootTabBarController {
    func tabBarController(_ tabBarController: UITabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        InstantTabTransition()
    }
}

extension RootTabBarController: UITabBarControllerDelegate {
    /// Bar -> router, so external navigation and the bar never disagree.
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        router.showLedger = false
        let tab = slots[selectedIndex]
        if router.selectedTab != tab { router.selectedTab = tab }
    }
}

extension RootTabBarController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        router.showAddTransaction = false
        router.showCommandPalette = false
        router.pendingAddAccountId = nil
        router.pendingAddCategoryId = nil
    }
}
#endif


/// What `TabBarShell` wrapped around each tab, reproduced so Phase 1 is
/// behaviour-identical: the floating add-`+` on the four content tabs (not
/// Settings), the Ledger cover presented once, and the focused-transaction sheet
/// that tx deep links / notifications / Spotlight open.
/// A tab's SwiftUI root rendered WITHOUT its own `NavigationStack`, for the tabs a
/// `UINavigationController` now owns. Only converted tabs reach here; the rest go
/// through `TabRootHost`, which keeps its stack.
private struct StacklessTabRoot: View {
    let tab: AppTab
    var body: some View {
        stackless.modifier(TabChrome(tab: tab))
    }

    @ViewBuilder private var stackless: some View {
        switch tab {
        case .accounts: AccountsTab(ownsNavigationStack: false)
        case .budgets: BudgetsTab(ownsNavigationStack: false)
        case .settings: SettingsTab(ownsNavigationStack: false)
        default: TabRootHost(tab: tab)
        }
    }
}

private struct TabRootHost: View {
    let tab: AppTab
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter

    var body: some View {
        tabContent(tab).modifier(TabChrome(tab: tab))
    }
}

/// The per-tab chrome `AdaptiveShell` used to supply: the floating add button, the
/// sheet for a transaction targeted from OUTSIDE the view tree (deep link, Spotlight,
/// an App Intent), and the Ledger cover behind the top-left corner control.
///
/// It lives in a modifier both tab hosts apply because it silently went missing
/// otherwise. `navigationTab` built its SwiftUI root directly, bypassing
/// `TabRootHost`, so every CONVERTED tab lost all three at once — verified on the
/// simulator: the ledger corner control on a converted tab did nothing at all, and
/// the tab root had no floating add button. Nothing failed loudly; the features were
/// simply absent.
private struct TabChrome: ViewModifier {
    let tab: AppTab
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter

    func body(content: Content) -> some View {
        Group {
            if tab == .settings {
                content
            } else {
                content.addTransactionFAB()
            }
        }
        .sheet(item: focusedTx) { EditTransactionSheet(txn: $0) }

    }

    /// Same binding as TabBarShell: a tx targeted from outside the view tree opens
    /// here, and dismissing clears the focus and settles the bar on Accounts.
    private var focusedTx: Binding<Tx?> {
        Binding(
            get: {
                guard router.selectedTab == .activity, let id = router.focusedId else { return nil }
                return store.txns.first { $0.id == id }
            },
            set: { newValue in
                if newValue == nil {
                    router.focusedId = nil
                    if router.selectedTab == .activity { router.selectedTab = .accounts }
                }
            }
        )
    }
}


// `AppTextSize` used to live here — a per-host SwiftUI modifier re-attached at each
// hosted root. It reached only those roots, so converted screens, presented covers
// and `-legacyShell` all ignored the setting. Replaced by the window trait override
// in `MainSceneDelegate.applyTextSizePreference`.
