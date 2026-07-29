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
            let vc = hostedRoot(tab)
            vc.tabBarItem = UITabBarItem(title: tab.title,
                                         image: UIImage(systemName: tab.icon),
                                         tag: slots.firstIndex(of: tab) ?? 0)
            return vc
        }
        bindRouter()
    }

    /// Each tab root is still SwiftUI. The environment objects and the app-wide
    /// section spacing that `AdaptiveShell` applied must be re-attached here —
    /// hosting controllers do not inherit them.
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

    // MARK: Router bridge

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
private struct TabRootHost: View {
    let tab: AppTab
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter

    var body: some View {
        Group {
            if tab == .settings {
                tabContent(tab)
            } else {
                tabContent(tab).addTransactionFAB()
            }
        }
        .sheet(item: focusedTx) { EditTransactionSheet(txn: $0) }
        .rightSlideDrill(isPresented: $router.showLedger) {
            NavigationStack {
                LedgerListView().rsdBackToolbar { router.showLedger = false }
            }
        }
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
