#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 3: the iPad (regular-width) root, in UIKit.
///
/// Phase 1 replaced only the compact branch, so `UIKitShell.makeRoot` handed a wide
/// window back to the hosted SwiftUI `AdaptiveShell` — meaning iPhone and iPad have
/// been running *different shells* ever since. Anything verified on one had to be
/// re-verified on the other. This closes that.
///
/// **Behaviour-identical by construction.** The columns are still the same SwiftUI
/// views, hosted; only the container is UIKit. That is deliberate and mirrors how
/// Phase 1 was done — change the container, prove it, convert the contents later.
/// The seam this creates is the point: a column can be swapped for a native
/// `UIViewController` one at a time, without touching the shell again.
///
/// **Why a container rather than one split view.** `SplitViewShell` shows three
/// columns for the tabs with a real list→detail relationship and two for the
/// dashboard tabs. `UISplitViewController.style` is fixed at init, and a
/// triple-column split view has no display mode meaning "primary + secondary, no
/// supplementary" — the modes run `.oneBesideSecondary` (supplementary + secondary)
/// through `.twoBesideSecondary` (all three), with no way to drop the middle column
/// while keeping the sidebar. So the arity change needs a different split view, and
/// this container swaps between them. The SwiftUI version effectively does the same
/// thing: its `switch` builds a different `NavigationSplitView` per tab group.
final class SplitShellVC: UIViewController {

    private let store: FinchStore
    private let router: DeepLinkRouter
    private let gate: BiometricGate
    /// Selection per tab, shared between the supplementary column that writes it and
    /// the secondary column that reads it. Outlives the split-view swaps, which is why
    /// it is owned here rather than by either column.
    private let selection = SplitSelection()
    private var cancellables = Set<AnyCancellable>()

    /// Which arity the current child was built for, so a tab change only rebuilds when
    /// it actually crosses the boundary.
    private var currentArity: Arity?
    private var child: UISplitViewController?
    /// The native ledger list, when it is the current supplementary column — held so
    /// its highlight can follow a selection changed from elsewhere (a deep link, or
    /// the detail column deleting the ledger it was showing).
    private weak var ledgerList: LedgersVC?
    /// The native budget list, when it is the current supplementary column — held so its
    /// highlight can follow a selection changed from elsewhere (a `budget:` deep link, or
    /// a ledger switch clearing it).
    private weak var budgetList: BudgetsListVC?
    /// The native Activity feed, when it is the current supplementary column — held so
    /// its highlight can follow a selection changed from elsewhere (a `tx:` deep link
    /// from Spotlight or a notification, or a ledger switch clearing it).
    private weak var activityList: ActivityFeedVC?

    /// Same switch `RootTabBarController.uikitNavTabs` uses — literally the same read
    /// now — so the compact root and the regular-width column convert together or not
    /// at all.
    private static var uikitBudgets: Bool { UIKitScreens.isEnabled }

    private enum Arity { case three, two }

    /// The tabs with a real list→detail relationship. Everything else is a dashboard
    /// or sheet-based screen that reads better full width — squeezing Insights into a
    /// middle column would be worse, which is the same call `MasterDetailShell` makes.
    private static let threeColumnTabs: Set<AppTab> = [.accounts, .budgets, .ledger, .activity, .scheduled]

    init(store: FinchStore, router: DeepLinkRouter, gate: BiometricGate) {
        self.store = store
        self.router = router
        self.gate = gate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildIfNeeded(for: router.selectedTab)

        router.$selectedTab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in self?.rebuildIfNeeded(for: tab) }
            .store(in: &cancellables)

        // A ledger switch invalidates the per-tab selections — a selected account id
        // means nothing in another ledger. `ledger` deliberately survives: the ledger
        // list is global, and "make active" from the detail column must not eject the
        // selection that triggered it.
        store.$activeLedgerId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.selection.clearForLedgerSwitch() }
            .store(in: &cancellables)

        // Ledger selection drives its detail column. Only meaningful while Ledger is
        // the visible tab; `installLedgerDetail` no-ops elsewhere because the split
        // view it targets has already been rebuilt for another tab.
        selection.$ledger
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self, self.router.selectedTab == .ledger, let child = self.child else { return }
                self.ledgerList?.selectedID = id
                self.installLedgerDetail(into: child)
            }
            .store(in: &cancellables)

        // Budget selection changed from somewhere other than the list — a ledger switch
        // clearing it, or the detail column deleting what it was showing. The hosted
        // detail column re-reads `selection` on its own; only the native list's highlight
        // has to be told.
        selection.$budget
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self, self.router.selectedTab == .budgets else { return }
                self.budgetList?.selectedID = id
            }
            .store(in: &cancellables)

        // Transaction selection changed from somewhere other than the feed — the
        // `tx:` deep link below, or a ledger switch clearing it. The hosted detail
        // column re-reads `selection` itself; only the native list needs telling.
        selection.$tx
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self, self.router.selectedTab == .activity else { return }
                self.activityList?.selectedID = id
            }
            .store(in: &cancellables)

        // A `tx:` deep link (Spotlight / notification) at regular width selects the
        // transaction in the Activity detail column. Compact shows the edit sheet
        // instead — see TabBarShell.focusedTx.
        router.$focusedId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self, self.router.selectedTab == .activity, let id,
                      self.store.txns.contains(where: { $0.id == id }) else { return }
                self.selection.tx = id
                self.router.focusedId = nil
            }
            .store(in: &cancellables)
    }

    // MARK: - Building the split view

    private func rebuildIfNeeded(for tab: AppTab) {
        let arity: Arity = Self.threeColumnTabs.contains(tab) ? .three : .two
        // Within an arity the columns are rebuilt in place, so only a boundary
        // crossing needs a new split view controller.
        if arity == currentArity, let child {
            install(columns: tab, into: child, arity: arity)
            return
        }
        currentArity = arity

        child?.willMove(toParent: nil)
        child?.view.removeFromSuperview()
        child?.removeFromParent()

        let svc = UISplitViewController(style: arity == .three ? .tripleColumn : .doubleColumn)
        svc.preferredSplitBehavior = .tile          // `.balanced` in NavigationSplitView terms
        svc.primaryBackgroundStyle = .sidebar
        svc.delegate = self
        // Matches `.navigationSplitViewColumnWidth` on the SwiftUI columns. Without the
        // supplementary bound, `.tile` gives the list roughly half the content area.
        svc.minimumPrimaryColumnWidth = 180
        svc.preferredPrimaryColumnWidth = 220
        svc.maximumPrimaryColumnWidth = 280
        if arity == .three {
            svc.minimumSupplementaryColumnWidth = 300
            svc.preferredSupplementaryColumnWidth = 340
            svc.maximumSupplementaryColumnWidth = 420
        }
        svc.preferredDisplayMode = SplitDisplayMode.preferred(collapsed: SplitDisplayMode.storedCollapsed,
                                                             arity: arity == .three ? .three : .two)

        install(columns: tab, into: svc, arity: arity)

        addChild(svc)
        svc.view.frame = view.bounds
        svc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(svc.view)
        svc.didMove(toParent: self)
        child = svc
    }

    /// (Re)populate the columns for `tab`.
    private func install(columns tab: AppTab, into svc: UISplitViewController, arity: Arity) {
        svc.setViewController(host(SectionSidebar()), for: .primary)

        guard arity == .three else {
            // Sidebar │ full-width content, as the SwiftUI two-column branch does.
            svc.setViewController(host(TabContentColumn(tab: tab)), for: .secondary)
            return
        }
        // Ledger is the first column converted (Phase 3b step 1): both its screens are
        // native, so the column can be too. The rest still host their SwiftUI screens —
        // that is the point of the seam, one column at a time.
        if tab == .ledger {
            let list = LedgersVC(onSelect: { [weak self] id in self?.selection.ledger = id })
            list.selectedID = selection.ledger
            ledgerList = list
            svc.setViewController(UINavigationController(rootViewController: list), for: .supplementary)
            installLedgerDetail(into: svc)
            return
        }
        ledgerList = nil
        // Budgets is the second column converted (Phase 3b step 2). The SAME
        // `BudgetsListVC` is the compact tab root, so there is one list serving both
        // widths rather than a native column beside a hosted iPhone screen. Its detail
        // stays hosted: at regular width the detail is a sibling COLUMN, not a push, so
        // a hosted SwiftUI scroll view there cannot shadow.
        //
        // Gated on the same `-uikitActivity YES` flag as the tab root, so the app is
        // never half-converted — flag off means SwiftUI at both widths, which is what
        // `NavigationUITests` exercises as the control implementation.
        if tab == .budgets, Self.uikitBudgets {
            let list = BudgetsListVC(onSelect: { [weak self] id in self?.selection.budget = id })
            list.selectedID = selection.budget
            budgetList = list
            svc.setViewController(UINavigationController(rootViewController: list), for: .supplementary)
            svc.setViewController(host(SplitDetailColumn(tab: tab, selection: selection)), for: .secondary)
            return
        }
        budgetList = nil
        if tab == .scheduled, Self.uikitBudgets {
            let list = ScheduledListVC(onSelect: { [weak self] id in self?.selection.scheduled = id })
            list.selectedID = selection.scheduled
            svc.setViewController(UINavigationController(rootViewController: list), for: .supplementary)
            // Detail stays hosted: `ScheduledDetailView` is a sibling COLUMN here, not a
            // push, so it is not at navigation depth and cannot shadow.
            svc.setViewController(host(SplitDetailColumn(tab: tab, selection: selection)), for: .secondary)
            return
        }
        // Activity is the odd one in Phase 3b: it has no compact tab ROOT to convert
        // (the feed lives inside Accounts and is reached by a push, native since
        // Phase 2), so this step adds the column only — there is no root/column pair
        // to keep in step, and `ActivityFeedVC` already serves both.
        if tab == .activity, Self.uikitBudgets {
            let list = ActivityFeedVC(onSelect: { [weak self] id in self?.selection.tx = id })
            list.selectedID = selection.tx
            activityList = list
            svc.setViewController(UINavigationController(rootViewController: list), for: .supplementary)
            // Detail stays hosted: `TransactionDetailView` is a sibling COLUMN here,
            // not a push, so it is not at navigation depth and cannot shadow.
            svc.setViewController(host(SplitDetailColumn(tab: tab, selection: selection)), for: .secondary)
            return
        }
        activityList = nil
        svc.setViewController(host(SplitListColumn(tab: tab, selection: selection)), for: .supplementary)
        svc.setViewController(host(SplitDetailColumn(tab: tab, selection: selection)), for: .secondary)
    }

    /// The ledger detail column: the selected ledger, or the placeholder.
    ///
    /// Swapped imperatively rather than by a SwiftUI `if`, because the column is now a
    /// real `UIViewController` and a split view holds one per column.
    private func installLedgerDetail(into svc: UISplitViewController) {
        if let id = selection.ledger, store.ledgers.contains(where: { $0.id == id }) {
            svc.setViewController(UINavigationController(rootViewController: LedgerDetailVC(ledgerId: id)),
                                  for: .secondary)
        } else {
            // The same placeholder the SwiftUI column shows — a stale or deleted id
            // must land here, not on a detail for a ledger that is gone.
            svc.setViewController(host(DetailPlaceholder(systemImage: "books.vertical",
                                                         label: "Select a ledger")),
                                  for: .secondary)
        }
    }

    /// Host a column, re-attaching the environment. Hosting controllers do NOT inherit
    /// environment objects from anywhere — the same trap that crashed
    /// `BackupSyncSettingsVC` in Phase 2 — so every hosted column re-declares them.
    /// (Text size is the exception: it is a window-level trait override, which every
    /// host DOES inherit — see `MainSceneDelegate.applyTextSizePreference`.)
    private func host(_ view: some View) -> UIViewController {
        UIHostingController(rootView:
            view
                .finchSectionSpacing()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(gate)
        )
    }
}

// MARK: - Column visibility persistence

extension SplitShellVC: UISplitViewControllerDelegate {
    /// Record the user's sidebar preference — but only when it is really theirs.
    ///
    /// iPadOS auto-collapses columns on rotation to portrait. Persisting every change
    /// would record that auto-collapse as a preference and pin the sidebar shut, which
    /// is the trap `PersistedSplitVisibility` was written to avoid; the rule is
    /// carried over unchanged — persist only while landscape.
    func splitViewController(_ svc: UISplitViewController,
                             willChangeTo displayMode: UISplitViewController.DisplayMode) {
        let landscape = view.bounds.width > view.bounds.height
        guard landscape, let arity = currentArity else { return }
        guard let collapsed = SplitDisplayMode.collapsed(from: displayMode,
                                                         arity: arity == .three ? .three : .two)
        else { return }
        SplitDisplayMode.storedCollapsed = collapsed
    }
}
#endif
