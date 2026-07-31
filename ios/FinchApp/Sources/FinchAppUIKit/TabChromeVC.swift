#if os(iOS)
import UIKit
import SwiftUI
import FinchCore

/// Gives a NATIVE tab root the chrome that hosted roots get from the `TabChrome`
/// SwiftUI modifier: the floating add-transaction button and the focused-tx sheet.
///
/// **Why this exists.** Converting a tab root to a `UINavigationController` silently
/// drops both. That is not hypothetical — the same class of bug already happened once
/// in Phase 2, when `navigationTab` bypassed `TabRootHost` and every converted tab lost
/// its FAB and its ledger control with nothing failing loudly. This is the prerequisite
/// for converting any tab root; without it each converted tab ships missing its `+`.
///
/// **The chrome is hosted, not rebuilt.** `AddTransactionFAB` is far more than a
/// floating button: it honours `finch.fab.enabled` and `finch.fab.position`, hides
/// during multi-select and while the ledger cover is up, and seeds the sheet from the
/// page's `AddTxContext` so it matches that page's own toolbar `+`. Reimplementing all
/// of that in UIKit would be a second copy of rules that must stay in step with the
/// Mac's. So the real modifier is hosted over the native content, and there is one FAB
/// in the app, not two.
final class TabChromeVC: UIViewController {

    private let content: UIViewController
    private let appTab: AppTab   // NOT `tab`: UIViewController.tab is UITab? on iOS 18+
    private let store: FinchStore
    private let router: DeepLinkRouter

    init(content: UIViewController, tab: AppTab, store: FinchStore, router: DeepLinkRouter) {
        self.content = content
        self.appTab = tab
        self.store = store
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)

        // Touches must reach the collection view underneath everywhere except on the
        // FAB itself. A plain hosting view would swallow the whole screen.
        let passthrough = PassthroughView(frame: view.bounds)

        let chrome = UIHostingController(rootView: TabChromeOverlay(
            tab: appTab,
            onFABFrame: { [weak passthrough] rect in passthrough?.fabFrame = rect })
            .environmentObject(store)
            .environmentObject(router)
            .environmentObject(BiometricGate.shared))
        chrome.view.backgroundColor = .clear
        passthrough.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(chrome)
        chrome.view.frame = passthrough.bounds
        chrome.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        passthrough.addSubview(chrome.view)
        view.addSubview(passthrough)
        chrome.didMove(toParent: self)
    }

    /// The tab bar reads this off the container, so it has to forward.
    override var tabBarItem: UITabBarItem! {
        get { content.tabBarItem }
        set { content.tabBarItem = newValue }
    }

    /// Only the FAB is interactive; everything else falls through to the content.
    ///
    /// **Identity cannot decide this, so geometry does.** The obvious test — "did a
    /// descendant claim the touch, rather than the hosting view's own background?" —
    /// does not work: `_UIHostingView.hitTest` returns the hosting view itself for ANY
    /// point inside its bounds. Logging the hit chain during a swipe on empty space and
    /// during a tap on the button produced the *same* view both times, and
    /// `.allowsHitTesting(false)` on the SwiftUI backdrop did not change it. Written the
    /// obvious way, this view swallowed every touch and the native list underneath would
    /// not scroll at all.
    ///
    /// So the button publishes its own rect (`FABFrameKey`) and the test is "is the
    /// point inside it". `.zero` means there is no FAB right now — pass everything
    /// through.
    private final class PassthroughView: UIView {
        var fabFrame: CGRect = .zero

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard fabFrame != .zero, fabFrame.contains(convert(point, to: nil)) else { return nil }
            let hit = super.hitTest(point, with: event)
            return hit === self ? nil : hit
        }
    }
}

/// The chrome itself, in SwiftUI, so both hosts run the same code.
private struct TabChromeOverlay: View {
    let tab: AppTab
    /// Reports the FAB's window rect up to `PassthroughView`, which needs it to decide
    /// which touches are the button's and which belong to the list underneath.
    let onFABFrame: (CGRect) -> Void
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        Group {
            // Settings has no add-transaction affordance, matching `TabChrome`.
            if tab == .settings {
                Color.clear
            } else {
                Color.clear.addTransactionFAB()
            }
        }
        .onPreferenceChange(FABFrameKey.self) { rect in onFABFrame(rect) }
        .sheet(item: focusedTx) { EditTransactionSheet(txn: $0) }
    }

    /// Same binding `TabChrome` uses: a tx targeted from outside the view tree opens
    /// here, and dismissing clears the focus.
    private var focusedTx: Binding<Tx?> {
        Binding(
            get: {
                guard router.selectedTab == .activity, let id = router.focusedId else { return nil }
                return store.txns.first { $0.id == id }
            },
            set: { if $0 == nil { router.focusedId = nil } })
    }
}
#endif
