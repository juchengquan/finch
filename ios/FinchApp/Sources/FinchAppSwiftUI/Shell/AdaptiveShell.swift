import SwiftUI
import FinchCore

/// Phase 3 — one code base, three platforms. The chrome switches by horizontal
/// size class: iPhone (and iPad Slide Over / 1-3 split) keep the bottom tab bar;
/// iPad regular width + Mac get a sidebar + `NavigationSplitView`. The 6 tabs and
/// all Phase 2 write screens render in both. (Mac distribution target + menu bar
/// are deferred infra — see _PHASES_3_TO_8_OPEN_QUESTIONS.md.)
struct AdaptiveShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        Group {
            if sizeClass == .compact {
                TabBarShell()
            } else {
                SplitViewShell()
            }
        }
        // Global gap between grouped List sections (e.g. account groups) for the main
        // tabs — environment-based, so every descendant (non-sheet) List inherits it.
        // Sheets don't inherit; they apply .finchSectionSpacing() themselves. Tune in Common/Metrics.swift.
        .finchSectionSpacing()
        .modifier(ExportCoordinator())
    }
}

/// The iPhone/compact shell — a five-slot bottom bar (Accounts, Budgets,
/// Scheduled, Insights, Settings). The Ledger is reached from a top-left
/// `books.vertical` corner control on every tab (`LedgerBarButton`) that pushes
/// the two-layer Ledger onto the current tab. `CompactTabRouting` bridges the bar
/// selection to the shared `DeepLinkRouter`; a `.ledger` router target (deep link
/// / ⌘K / intent / corner button) is converted to that push instead of selecting
/// a slot. Launch tab is Accounts.
struct TabBarShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var selected: CompactTab = .accounts

    var body: some View {
        TabView(selection: $selected) {
            tabContent(.accounts).addTransactionFAB()
                // Instant tab switches (kills the iOS 26 cross-dissolve "block"); see
                // DisableTabContentTransition. Hosted in one tab so it can reach the
                // real UITabBarController — one install covers the whole TabView.
                #if os(iOS)
                .background(DisableTabContentTransition())
                #endif
                .tabItem { Label(AppTab.accounts.title, systemImage: AppTab.accounts.icon) }
                .tag(CompactTab.accounts)
            tabContent(.budgets).addTransactionFAB()
                .tabItem { Label(AppTab.budgets.title, systemImage: AppTab.budgets.icon) }
                .tag(CompactTab.budgets)
            tabContent(.scheduled).addTransactionFAB()
                .tabItem { Label(AppTab.scheduled.title, systemImage: AppTab.scheduled.icon) }
                .tag(CompactTab.scheduled)
            tabContent(.insights).addTransactionFAB()
                .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.icon) }
                .tag(CompactTab.insights)
            tabContent(.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(CompactTab.settings)
        }
        // Activity is no longer a bottom-bar tab, but tx deep links / notifications
        // / Spotlight still route to `.activity` with a focused tx id — open that
        // transaction here (the bar lands on Accounts via CompactTabRouting).
        .sheet(item: focusedTx) { EditTransactionSheet(txn: $0) }
        .onAppear { syncFromRouter(router.selectedTab) }
        .onChange(of: router.selectedTab) { _, tab in syncFromRouter(tab) }
        .onChange(of: selected) { _, sel in
            router.showLedger = false
            if let tab = CompactTabRouting.routerTab(forSelected: sel, current: router.selectedTab) {
                router.selectedTab = tab
            }
        }
        #if os(iOS)
        // The Ledger drill as a top-level right-slide cover, presented ONCE here at
        // the compact shell (not per-tab) so the single `router.showLedger` bool
        // drives exactly one cover. LedgerList → LedgerDetail → "View all activity"
        // then push natively *inside* the cover's NavigationStack — native
        // swipe-back and NO resume shadow (only main-tab-stack pushes shadow).
        .rightSlideDrill(isPresented: $router.showLedger) {
            NavigationStack {
                LedgerListView()
                    .rsdBackToolbar { router.showLedger = false }
            }
        }
        #endif
    }

    private func syncFromRouter(_ tab: AppTab) {
        // A `.ledger` route (deep link / ⌘K / intent / corner button) → push the
        // two-layer Ledger on the active tab; settle the bar on a real primary tab.
        if tab == .ledger {
            router.showLedger = true
            router.selectedTab = CompactTabRouting.appTab(for: selected) ?? .accounts
            return
        }
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: [])
        if result.selected != .more, selected != result.selected { selected = result.selected }
    }

    /// A transaction targeted by a deep link / notification / Spotlight tap
    /// (router `.activity` + a focused tx id). Presenting clears the focus and
    /// settles the router on Accounts so the bar state stays consistent.
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

/// Set true by a tab whose content has entered multi-select (the Activity/Ledger
/// feed), so the floating add-`+` steps aside while the bulk-action bottom bar
/// occupies the bottom. Flows up from the content to the `AddTransactionFAB`
/// modifier that wraps it.
struct SelectionActiveKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The subject of the page currently under the floating add button. Published
/// upward (same mechanism as `SelectionActiveKey`) by detail pages — Account
/// detail seeds its account, Budget detail its account + category — so the FAB
/// opens the Add-transaction sheet pre-filled the same way the page's own
/// toolbar `+` does. Empty (the default) everywhere else → an unseeded sheet.
struct AddTxContext: Equatable {
    var accountId: String? = nil
    var categoryId: String? = nil
    var isEmpty: Bool { accountId == nil && categoryId == nil }
}

/// The FAB's cover-local Add sheet payload. `.sheet(item:)`, not
/// `.sheet(isPresented:)`: the `isPresented` content closure is captured on an
/// earlier body pass, so it read the page context from BEFORE
/// `onPreferenceChange` delivered it and opened an unseeded sheet (device-verified
/// — the FAB knew `accountId=savings` while the sheet it opened had no account).
private struct AddTxSeed: Identifiable {
    let accountId: String?
    let categoryId: String?
    var id: String { "\(accountId ?? "-")|\(categoryId ?? "-")" }
}

struct AddTxContextKey: PreferenceKey {
    static let defaultValue = AddTxContext()
    // The innermost publisher wins: a pushed detail page's context replaces
    // the (empty) value from the rest of the tab's tree.
    static func reduce(value: inout AddTxContext, nextValue: () -> AddTxContext) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

/// A floating "add transaction" button for the compact primary tabs **and for the
/// right-slide drill covers they open** — quick capture from anywhere (it replaces
/// the prominent `+` the removed Activity tab used to provide). Triggers the same
/// app-root sheet as ⌘N / the command palette (covers present it themselves — see
/// `presentsLocally`). Hidden until at least one account exists (you can't post
/// without one). The overlay sits inside the tab's content area, so it floats just
/// above the bottom bar automatically; a cover has no bottom bar, so there it sits
/// against the safe area. Hidden while the content is in multi-select so it
/// doesn't overlap the bulk-action bar (see `SelectionActiveKey`).
/// User preference for which bottom corner hosts the floating add button
/// (Settings › Appearance › Quick add button). Stored as a raw string so the
/// Settings picker and the FAB read the same key.
enum FabPosition: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .left ? "Bottom left" : "Bottom right" }
}

/// The add-transaction FAB's frame in GLOBAL (window) coordinates, published by the
/// button itself.
///
/// **Why a preference and not a constant.** When a UIKit tab root hosts this modifier
/// over native content (`TabChromeVC`), the host has to let every touch except the
/// button reach the collection view underneath. It cannot ask SwiftUI where the button
/// is: `_UIHostingView.hitTest` returns the hosting view for ANY point in its bounds —
/// verified by logging the hit chain, which was identical for a tap on the FAB and a
/// swipe on empty space — so `.allowsHitTesting(false)` on the backdrop does not make
/// it transparent to touches either. Reading the real rect is what keeps the passthrough
/// honest about the position preference, the hidden states and the button's size,
/// instead of hard-coding a corner that would drift.
///
/// `.zero` means "no FAB right now" (disabled, no accounts, multi-select, ledger cover),
/// in which case the host passes everything through.
struct FABFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct AddTransactionFAB: ViewModifier {
    /// A drill cover (`rightSlideDrill`) is a top-level UIKit modal, so the
    /// app-root Add sheet cannot present over it — SwiftUI tears the cover down
    /// to show it, ejecting the user back to the tab root (verified on device via
    /// `finch://add` from an account page). Inside a cover the FAB therefore
    /// presents its OWN sheet, exactly like the page's toolbar `+` does; on a tab
    /// it keeps routing through the router so ⌘N / palette / FAB stay one path.
    var presentsLocally = false
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var selecting = false
    @State private var context = AddTxContext()
    @State private var localAddSeed: AddTxSeed?
    @AppStorage("finch.fab.enabled") private var fabEnabled = true
    @AppStorage("finch.fab.position") private var fabPositionRaw = FabPosition.right.rawValue
    private var fabLeft: Bool { fabPositionRaw == FabPosition.left.rawValue }
    func body(content: Content) -> some View {
        content.overlay(alignment: fabLeft ? .bottomLeading : .bottomTrailing) {
            // Hidden while the corner-pushed Ledger is up so that screen has the
            // same (FAB-free) chrome no matter which tab it was opened from.
            if fabEnabled, !store.accounts.isEmpty, !selecting, !router.showLedger {
                Button {
                    // Seed the sheet with the page's subject (account/budget
                    // detail) so the FAB matches the page's own toolbar `+`.
                    if presentsLocally {
                        localAddSeed = AddTxSeed(accountId: context.accountId,
                                                 categoryId: context.categoryId)
                    } else {
                        router.pendingAddAccountId = context.accountId
                        router.pendingAddCategoryId = context.categoryId
                        router.showAddTransaction = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .accessibilityLabel("Add Transaction")
                // Publishes the button's own rect so a UIKit host can pass every touch
                // that is NOT on it through to the native content underneath — see
                // FABFrameKey. Measured before the paddings, so it is the 56×56 button.
                // No effect on the pure-SwiftUI path, which never reads the preference.
                .background(GeometryReader { geo in
                    Color.clear.preference(key: FABFrameKey.self, value: geo.frame(in: .global))
                })
                .padding(fabLeft ? .leading : .trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .onPreferenceChange(SelectionActiveKey.self) { selecting = $0 }
        .onPreferenceChange(AddTxContextKey.self) { context = $0 }
        // Cover-local presentation (see `presentsLocally`) — seeded from the same
        // page context the router path passes through `pendingAdd*`.
        .sheet(item: $localAddSeed) { seed in
            AddTransactionSheet(defaultAccountId: seed.accountId,
                                defaultCategoryId: seed.categoryId)
        }
    }
}

extension View {
    /// The floating add-`+` for a compact primary tab (Accounts / Budgets /
    /// Scheduled / Insights). Taps route through `DeepLinkRouter` to the app-root
    /// Add sheet, the same one ⌘N and the command palette open.
    func addTransactionFAB() -> some View { modifier(AddTransactionFAB()) }

    /// The same button for a right-slide drill cover's content. Identical look and
    /// page-context seeding, but the Add sheet is presented by the cover itself —
    /// the app-root sheet would dismiss the cover out from under the user.
    /// Apply INSIDE the cover's `NavigationStack`, on the destination view — that
    /// is the arrangement verified on device, and it keeps the FAB a direct
    /// ancestor of the page publishing `AddTxContextKey`.
    func addTransactionFABInCover() -> some View { modifier(AddTransactionFAB(presentsLocally: true)) }
}

/// The top-left Ledger control on every compact primary tab — sets
/// `router.showLedger`, which `TabBarShell` presents as a top-level Ledger cover.
/// Compact-only, so the iPad/Mac sidebar (which lists Ledger itself) doesn't get a
/// redundant button. Drop one in each tab's `.toolbar`:
/// `ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }`.
struct LedgerBarButton: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        if sizeClass == .compact {
            Button { router.showLedger = true } label: { Image(systemName: "books.vertical") }
                .accessibilityLabel("Ledger")
        }
    }
}

/// The privacy-mode eye toggle shown on every primary tab — one tap masks every
/// rendered amount as "••••" (web parity: #416). Cross-platform (not compact-gated:
/// useful on iPad/Mac toolbars too); state lives on FinchStore.privacyMode.
struct PrivacyToggleButton: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        Button { store.privacyMode.toggle() } label: {
            Image(systemName: store.privacyMode ? "eye.slash" : "eye")
        }
        .accessibilityLabel("Privacy mode")
        .accessibilityValue(store.privacyMode ? "on" : "off")
    }
}

/// The iPad/Mac shell. Accounts, Budgets, Ledger, Activity, and Scheduled get
/// a true three-column master–detail (sidebar │ list │ detail — see
/// MasterDetailShell); the dashboard / sheet-based tabs (Insights, Settings)
/// keep two columns (sidebar │ full-width content), which suits their wide
/// layouts. Selection persists per tab across section switches.
///
/// The split view owns navigation for its columns. Detail views are rendered
/// directly in the detail column rather than wrapped in another
/// `NavigationStack`; the compact tab stacks remain the push-navigation owners
/// for iPhone. This avoids competing navigation contexts and preserves the
/// split view's column-specific navigation behavior.
struct SplitViewShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var accountSelection: String?
    @State private var budgetSelection: String?
    @State private var ledgerSelection: String?
    @State private var txSelection: String?
    @State private var scheduledSelection: String?

    var body: some View {
        Group {
            switch router.selectedTab {
            case .accounts:
                ThreeColumnShell {
                    AccountsTab(selection: $accountSelection)
                } detail: {
                    // Guard against a stale selection (e.g. after a ledger switch).
                    if let id = accountSelection, store.accounts.contains(where: { $0.id == id }) {
                        AccountDetailView(accountId: id)
                    } else {
                        DetailPlaceholder(systemImage: "creditcard", label: "Select an account")
                    }
                }
            case .budgets:
                ThreeColumnShell {
                    BudgetsTab(selection: $budgetSelection)
                } detail: {
                    if let id = budgetSelection, store.budgets.contains(where: { $0.id == id }) {
                        BudgetDetailView(budgetId: id)
                    } else {
                        DetailPlaceholder(systemImage: "chart.pie", label: "Select a budget")
                    }
                }
            case .ledger:
                ThreeColumnShell {
                    LedgerTab(selection: $ledgerSelection)
                } detail: {
                    // Guard against a stale selection (e.g. a deleted ledger).
                    if let id = ledgerSelection, store.ledgers.contains(where: { $0.id == id }) {
                        LedgerDetailView(ledgerId: id)
                    } else {
                        DetailPlaceholder(systemImage: "books.vertical", label: "Select a ledger")
                    }
                }
            case .activity:
                ThreeColumnShell {
                    ActivityFeedView(consumesPendingFilter: true, selection: $txSelection)
                } detail: {
                    // Guard against a stale selection (deleted tx / ledger switch).
                    if let id = txSelection, store.txns.contains(where: { $0.id == id }) {
                        TransactionDetailView(txId: id)
                    } else {
                        DetailPlaceholder(systemImage: "list.bullet", label: "Select a transaction")
                    }
                }
            case .scheduled:
                ThreeColumnShell {
                    ScheduledTab(selection: $scheduledSelection)
                } detail: {
                    // Guard against a stale selection (deleted template / ledger switch).
                    if let id = scheduledSelection, store.scheduled.contains(where: { $0.id == id }) {
                        ScheduledDetailView(templateId: id)
                    } else {
                        DetailPlaceholder(systemImage: "calendar", label: "Select a scheduled item")
                    }
                }
            default:
                PersistedSplitVisibility(columns: .two) { $visibility in
                    NavigationSplitView(columnVisibility: $visibility) {
                        SectionSidebar()
                    } detail: {
                        tabContent(router.selectedTab)
                    }
                    .navigationSplitViewStyle(.balanced)
                }
            }
        }
        // A ledger switch invalidates the per-tab selections. (`ledgerSelection`
        // deliberately survives — the ledger list is global, and "make active"
        // from the detail column must not eject the selection.)
        .onChange(of: store.activeLedgerId) { _, _ in
            accountSelection = nil
            budgetSelection = nil
            txSelection = nil
            scheduledSelection = nil
        }
        // A `tx:` deep link (Spotlight / notification) on regular width: select
        // the transaction in the Activity detail column (compact shows the edit
        // sheet instead — see TabBarShell.focusedTx).
        .onChange(of: router.focusedId) { _, id in
            guard router.selectedTab == .activity, let id,
                  store.txns.contains(where: { $0.id == id }) else { return }
            txSelection = id
            router.focusedId = nil
        }
        .onAppear {
            if router.selectedTab == .activity, let id = router.focusedId,
               store.txns.contains(where: { $0.id == id }) {
                txSelection = id
                router.focusedId = nil
            }
        }
    }
}

/// The content view for a tab — shared by both shells.
@ViewBuilder
func tabContent(_ tab: AppTab) -> some View {
    switch tab {
    case .ledger: LedgerTab()
    case .accounts: AccountsTab()
    case .activity: ActivityTab()
    case .budgets: BudgetsTab()
    case .insights: InsightsTab()
    case .scheduled: ScheduledTab()
    case .settings: SettingsTab()
    }
}

#if os(iOS)
// MARK: - Instant tab switch (kills the iOS 26 tab-content cross-dissolve)
//
// iOS 26 cross-dissolves the OUTGOING tab over the incoming one for ~130ms. When
// the outgoing list is scrolled, its dense rows fill the top region where the
// incoming page shows only its large title, so the overlap reads as a flashing
// "block". The dissolve lives in the backing `UITabBarController` — SwiftUI's
// own `.transaction`/animation controls don't reach it — so we suppress it
// through the tab controller's PUBLIC delegate hook:
// `animationControllerForTransitionFrom` returning a zero-duration animator makes
// the swap instant (the pre-iOS-26 behaviour). SwiftUI's own delegate is kept and
// every other call forwarded, so tab-selection observation is unaffected.
// REMOVE if Apple makes the dissolve content-aware / offers an opt-out.

/// A zero-duration `UIViewControllerAnimatedTransitioning` — swaps the tab's view
/// in with no animation, so there is nothing to double-expose.
private final class InstantTabTransition: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0 }
    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        if let to = ctx.view(forKey: .to) { ctx.containerView.addSubview(to) }
        ctx.completeTransition(!ctx.transitionWasCancelled)
    }
}

/// Forwards every `UITabBarControllerDelegate` call to SwiftUI's original delegate
/// (ObjC message forwarding), overriding only the transition animator. Holding the
/// original means selection observation keeps working and can be restored on teardown.
private final class TabTransitionProxy: NSObject, UITabBarControllerDelegate {
    weak var original: UITabBarControllerDelegate?
    weak var tabController: UITabBarController?
    private let instant = InstantTabTransition()
    func tabBarController(_ tabBarController: UITabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? { instant }
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? { original }
}

/// Installs `TabTransitionProxy` on the enclosing `UITabBarController`. Placed
/// INSIDE a tab's content (not on the `TabView`) so `.tabBarController` resolves
/// to SwiftUI's real controller rather than a hosting layer above it.
private struct DisableTabContentTransition: UIViewControllerRepresentable {
    func makeCoordinator() -> TabTransitionProxy { TabTransitionProxy() }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            // Walk the parent chain — `.tabBarController` alone can miss it across
            // SwiftUI's hosting layers. Degrades gracefully (no-op) if not found.
            var node: UIViewController? = uiViewController
            var found: UITabBarController?
            while let n = node {
                if let t = n as? UITabBarController { found = t; break }
                found = found ?? n.tabBarController
                node = n.parent
            }
            guard let tab = found, tab.delegate !== context.coordinator else { return }
            context.coordinator.original = tab.delegate
            context.coordinator.tabController = tab
            tab.delegate = context.coordinator
        }
    }
    /// `UITabBarController.delegate` is `weak`; if this representable is torn down,
    /// hand the delegate back to SwiftUI's coordinator rather than leaving it nil.
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: TabTransitionProxy) {
        if coordinator.tabController?.delegate === coordinator {
            coordinator.tabController?.delegate = coordinator.original
        }
    }
}
#endif
