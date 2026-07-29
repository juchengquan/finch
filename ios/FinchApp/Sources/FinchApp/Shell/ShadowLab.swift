import SwiftUI

#if DEBUG && os(iOS)

// MARK: - iOS 26 resume-shadow lab (THROWAWAY — never merged)
//
// One build, N navigation structures, same content. Launch with
// `-shadowLab YES` to replace the app shell with this menu.
//
// Procedure per variant: open it, SCROLL the list down, background the app
// (Home), wait ~3s, resume. Watch the area under the top bar for a dark band
// that fades over ~2-3s.
//
// Variants 0 and 1 are CALIBRATION, not candidates: 0 is the pre-#636 shape
// that shadows, 1 is the shipped RightSlideDrill cover that doesn't. Judge the
// rest against those two in the same session — every wrong conclusion in this
// bug's history came from comparing against memory instead of a control.

/// Under-layer treatment for the slide-over variants (13/14/15).
enum SlideOverStyle {
    case parallax               // raw fractional offset
    case parallaxPixelSnapped   // offset aligned to the pixel grid
    case staticDim              // under-page does not move; it dims
}

enum ShadowVariant: String, CaseIterable, Identifiable {
    case push0Control
    case cover1Control
    case push2TabBarHidden
    case outer3StackWrapsTabView
    case rootSwap4
    case push5BottomEdgeHidden
    case push6BackgroundExtension
    case push7TabBarMinimize
    // --- round 2 ---
    case pushInCover8
    case rootSwap9Clean
    case cover10Zoom
    case cover11Plain
    case rootSwap12Draggable
    // --- round 3 ---
    case slideOver13
    // --- round 4 ---
    case slideOver14Snapped
    case slideOver15NoParallax
    // --- round 5 ---
    case hostedShell16
    case sharedBar17
    // --- round 6 ---
    case customBar18
    // --- round 7 ---
    case coverCustomBar19
    // --- round 8 ---
    case uikitRootSwap20
    // --- round 9 ---
    case passthroughCover21
    // --- round 10 ---
    case directCover22
    case directRightSlide23
    // --- round 11: vary the CONTENT, not the structure ---
    case vanillaPush24
    case feedNoSearch25

    var id: String { rawValue }

    /// The three slide-over flavours share one container; this picks the
    /// under-layer treatment being compared.
    var slideOverStyle: SlideOverStyle? {
        switch self {
        case .slideOver13:         return .parallax
        case .sharedBar17:         return .parallaxPixelSnapped
        case .slideOver14Snapped:  return .parallaxPixelSnapped
        case .slideOver15NoParallax: return .staticDim
        default:                   return nil
        }
    }

    var title: String {
        switch self {
        case .push0Control:           return "0 · Plain push (KNOWN BAD)"
        case .cover1Control:          return "1 · RightSlideDrill cover (KNOWN GOOD)"
        case .push2TabBarHidden:      return "2 · Push + tab bar hidden"
        case .outer3StackWrapsTabView:return "3 · NavigationStack wraps TabView"
        case .rootSwap4:              return "4 · Root swap + slide transition"
        case .push5BottomEdgeHidden:  return "5 · Push + bottom edge effect hidden"
        case .push6BackgroundExtension:return "6 · Push + backgroundExtensionEffect"
        case .push7TabBarMinimize:    return "7 · Push + tabBarMinimizeBehavior"
        case .pushInCover8:           return "8 · Push INSIDE a cover"
        case .rootSwap9Clean:         return "9 · Root swap, done properly"
        case .cover10Zoom:            return "10 · fullScreenCover + zoom transition"
        case .cover11Plain:           return "11 · Plain fullScreenCover"
        case .rootSwap12Draggable:    return "12 · Root swap + drag-to-go-back"
        case .slideOver13:            return "13 · SwiftUI slide-over (parallax + edge swipe)"
        case .slideOver14Snapped:     return "14 · Slide-over, pixel-snapped parallax"
        case .slideOver15NoParallax:  return "15 · Slide-over, no parallax (static dim)"
        case .hostedShell16:          return "16 · WHOLE SHELL inside a cover, then native push"
        case .sharedBar17:            return "17 · Slide-over sharing ONE nav bar"
        case .customBar18:            return "18 · NATIVE push, custom bottom bar (no TabView)"
        case .coverCustomBar19:       return "19 · COVER + custom bar + native push"
        case .uikitRootSwap20:        return "20 · UIKit nav, ROOT-REPLACE (not push)"
        case .passthroughCover21:     return "21 · Cover with the REAL tab bar showing through"
        case .directCover22:          return "22 · Native cover, STRAIGHT to the page, no bar"
        case .directRightSlide23:     return "23 · SAME but from the RIGHT (needs UIKit)"
        case .vanillaPush24:          return "24 · Plain push of a VANILLA list (no finch views)"
        case .feedNoSearch25:         return "25 · Vanilla list + .searchable"
        }
    }

    var blurb: String {
        switch self {
        case .push0Control:           return "Pushed on the tab's own stack — the pre-#636 shape. Expect a shadow."
        case .cover1Control:          return "Top-level cover. Expect NO shadow."
        case .push2TabBarHidden:      return "Native push, but the tab bar is hidden on the pushed page."
        case .outer3StackWrapsTabView:return "Push happens on a stack ABOVE the TabView; native push + swipe-back."
        case .rootSwap4:              return "Not a push at all — the stack's ROOT is swapped. No native back-swipe."
        case .push5BottomEdgeHidden:  return "Only the bottom (tab-bar) scroll-edge effect is suppressed."
        case .push6BackgroundExtension:return "iOS 26 backgroundExtensionEffect on the pushed page."
        case .push7TabBarMinimize:    return "Tab bar minimises on scroll, changing its glass."
        case .pushInCover8:           return "Open the cover, THEN push inside it. Shipped code assumes this is clean."
        case .rootSwap9Clean:         return "Like 4 but the List is the root itself — should keep transparent bars."
        case .cover10Zoom:            return "Native SwiftUI cover, zoom transition instead of slide-up. No UIKit."
        case .cover11Plain:           return "Native SwiftUI cover, default slide-up. Feel baseline."
        case .rootSwap12Draggable:    return "Variant 9 plus a drag-right-to-go-back gesture. Judge the FEEL."
        case .slideOver13:            return "Previous page STAYS underneath and parallaxes. Edge-swipe back. Pure SwiftUI."
        case .slideOver14Snapped:     return "Same, but the under-page offset snaps to whole PIXELS — should kill the text jitter."
        case .slideOver15NoParallax:  return "Under-page does not move at all, just dims. Nothing to jitter."
        case .hostedShell16:          return "Tab bar + stacks live INSIDE a permanent cover. If pushes are clean here, everything is native."
        case .sharedBar17:            return "Only the CONTENT slides; the bar and search stay put and swap contents."
        case .customBar18:            return "One NavigationStack, no TabView; the bottom bar is drawn by us. Fully native push."
        case .coverCustomBar19:       return "Variant 8's clean structure (presented, no TabView) PLUS a drawn bottom bar."
        case .uikitRootSwap20:        return "Real UINavigationController + real tab bar. setViewControllers, so the page is a ROOT."
        case .passthroughCover21:     return "#8's clean cover, but the bottom strip is transparent AND tappable — the REAL bar."
        case .directCover22:          return "One tap in. No bottom bar. Deeper levels still push natively. Compare with #1."
        case .directRightSlide23:     return "One tap in, slides from the right, no bar, deeper push native. This is the shipped shape."
        case .vanillaPush24:          return "Same structure as #0, but 100 plain rows. If THIS is clean, the cause is in our page, not the push."
        case .feedNoSearch25:         return "Same vanilla list as 24 plus a search field in the bar — the likeliest content co-factor."
        }
    }

    /// Variant 3 needs a different ROOT arrangement, so it re-roots the lab
    /// rather than pushing inside the normal shell.
    var needsOuterStack: Bool { self == .outer3StackWrapsTabView }
}

/// The page under test — the real Activity feed, the exact view the post-mortem
/// bisected. A synthetic list would risk "my mock doesn't reproduce it".
private struct LabContent: View {
    let variant: ShadowVariant
    var body: some View {
        ActivityFeedView()
            .navigationTitle(variant.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Round 11 — vary the CONTENT while holding the structure at #0 (plain push).
///
/// Every variant up to 23 pushed the real `ActivityFeedView`, so a content-side
/// cause would have been invisible to all of them. Mainstream apps (Messages,
/// WhatsApp, Files) push into scrolled lists under glass all day without this
/// artifact, which is strong evidence that "any push shadows" is too broad.
private struct VanillaList: View {
    var body: some View {
        List(0..<100, id: \.self) { i in
            VStack(alignment: .leading, spacing: 2) {
                Text("Row \(i)").font(.body)
                Text("Subtitle for row \(i)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Vanilla list")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The same vanilla list PLUS a search field. `.searchable` installs a control in
/// the nav-bar area — exactly where the shadow forms — and finch's drilled pages
/// (account detail, the feed) all have one. If 24 is clean and this shadows, the
/// trigger is the search field, not the push.
private struct VanillaListWithSearch: View {
    @State private var query = ""
    var body: some View {
        List(0..<100, id: \.self) { i in
            VStack(alignment: .leading, spacing: 2) {
                Text("Row \(i)").font(.body)
                Text("Subtitle for row \(i)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle("Vanilla + search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Per-variant modifier applied to the PUSHED destination.
private struct LabDestination: View {
    let variant: ShadowVariant
    var body: some View {
        switch variant {
        case .vanillaPush24:
            VanillaList()
        case .feedNoSearch25:
            VanillaListWithSearch()
        case .push2TabBarHidden:
            LabContent(variant: variant).toolbar(.hidden, for: .tabBar)
        case .push5BottomEdgeHidden:
            if #available(iOS 26.0, *) {
                LabContent(variant: variant).scrollEdgeEffectHidden(true, for: .bottom)
            } else {
                LabContent(variant: variant)
            }
        case .push6BackgroundExtension:
            if #available(iOS 26.0, *) {
                LabContent(variant: variant).backgroundExtensionEffect()
            } else {
                LabContent(variant: variant)
            }
        default:
            LabContent(variant: variant)
        }
    }
}

/// Entry point: `-shadowLab YES`.
struct ShadowLabRoot: View {
    @State private var outerVariant: ShadowVariant?

    var body: some View {
        switch outerVariant {
        case .some(.hostedShell16):
            HostedShellLab(active: $outerVariant)
        case .some(.customBar18):
            CustomBarLab(active: $outerVariant)
        case .some(.coverCustomBar19):
            CoverCustomBarLab(active: $outerVariant)
        case .some(.uikitRootSwap20):
            RootSwapNavLab(active: $outerVariant)
        case .some:
            // Variant 3: one stack ABOVE the whole TabView.
            OuterStackLab(active: $outerVariant)
        case nil:
            NormalLab(goOuter: { outerVariant = $0 })
        }
    }
}

/// Variant 18 — the rule that fits every observation so far is "a push shadows
/// iff a TabView exists in the hierarchy hosting it": #8 (cover, no TabView) is
/// clean while #16 (cover WITH a TabView) shadows, and #2 shows hiding the bar
/// is not enough because the TabView still exists.
///
/// So: drop the TabView. One NavigationStack, a bottom bar we draw ourselves, and
/// an ordinary native push. If the rule holds this is clean — and it is the only
/// structure that can satisfy all three wants at once: native push (so the nav bar
/// behaves natively and swipe-back is Apple's), a visible bottom bar, and no
/// shadow.
///
/// The cost, if it works: our bar is a replica. It would not inherit the real tab
/// bar's scroll-to-top on re-tap, minimise-on-scroll, keyboard avoidance, or its
/// accessibility behaviour — those become ours to build and maintain.
private struct CustomBarLab: View {
    @Binding var active: ShadowVariant?
    @State private var path: [ShadowVariant] = []
    @State private var selected = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack(path: $path) {
                List {
                    Section {
                        Text("No TabView anywhere. Push, scroll, Home, resume.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink(value: ShadowVariant.customBar18) {
                        Text("Push the Activity feed (native push)")
                    }
                    Button("‹ Back to the menu") { active = nil }
                }
                .navigationTitle("Custom bar")
                .navigationDestination(for: ShadowVariant.self) { LabContent(variant: $0) }
            }
            ReplicaBar(selected: $selected)
        }
    }
}

// MARK: - Variant 21: a cover that lets the REAL tab bar through
//
// #8 and #19 were both presented from a shell that HAS a TabView, and their
// pushes were clean — so a TabView is only poison as an ANCESTOR of the push,
// not when it merely sits behind the presentation. #19 then showed a bottom bar
// can coexist with a clean cover, but only as a replica.
//
// This tries for the real thing: present the drill `.overFullScreen` (so the
// presenter, tab bar included, stays visible behind), keep the bottom strip
// TRANSPARENT, and make it touch-transparent too, so taps land on the real tab
// bar underneath. If it works: real Apple tab bar, visible and tappable, with
// native pushes inside a clean cover.

private var _pt_presented: UIViewController?
private func _pt_dismiss() { _pt_presented?.dismiss(animated: true); _pt_presented = nil }

/// Returns nil for touches in the bottom strip so they fall through to whatever
/// is behind the cover — here, the real tab bar.
private final class PassthroughView: UIView {
    var passthroughHeight: CGFloat = 100
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if point.y > bounds.height - passthroughHeight { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Hosts the cover's SwiftUI content above the passthrough strip.
private final class PassthroughContainer: UIViewController {
    private let host: UIViewController
    private let stripHeight: CGFloat

    init(host: UIViewController, stripHeight: CGFloat) {
        self.host = host; self.stripHeight = stripHeight
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    override func loadView() {
        let v = PassthroughView()
        v.passthroughHeight = stripHeight
        v.backgroundColor = .clear
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            // Stop short of the bar so it stays visible AND hittable.
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -stripHeight),
        ])
        host.didMove(toParent: self)
    }
}

// MARK: - Variant 20: UIKit nav container that ROOT-REPLACES instead of pushing
//
// The premise: a UIKit clone of NavigationStack that PUSHES would shadow exactly
// like SwiftUI's (UIKitNavStack was built and device-refuted on
// feat/uikit-device-build; #8 is a clean SwiftUI push, #16/#18 are shadowing
// SwiftUI pushes — the framework is not the axis). But `setViewControllers`
// animates like a push while leaving the destination as the stack's ROOT, and
// every root variant (#4/#9/#14) is clean.
//
// If this works it is the only arrangement that gives all of: real UINavigation
// bar (so the bar stays put and its CONTENTS transition, the thing SwiftUI's
// slide-over cannot do), UIKit-quality animation and interactive gesture, the
// REAL tab bar still visible, and no shadow.
//
// Note what this file already demonstrates about the cost: to get a backwards
// animation and an interactive back out of a root replace, we have to supply our
// own animator and percent-driven interaction — i.e. rebuild the machinery
// RightSlideDrill already contains, per navigation level.

/// Slides the outgoing page to the right and the incoming one back in from the
/// left — the inverse of a push, used when root-replacing "backwards".
private final class RootSwapBackAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }
    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        let container = ctx.containerView
        let bounds = container.bounds
        guard let to = ctx.view(forKey: .to) else { ctx.completeTransition(false); return }
        let from = ctx.view(forKey: .from)
        to.frame = bounds.offsetBy(dx: -bounds.width * 0.25, dy: 0)
        container.insertSubview(to, belowSubview: from ?? to)
        UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0, options: .curveEaseInOut) {
            to.frame = bounds
            from?.frame = bounds.offsetBy(dx: bounds.width, dy: 0)
        } completion: { _ in
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }
}

private final class RootSwapCoordinator: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    weak var nav: UINavigationController?
    var onExit: () -> Void = {}
    private var goingBack = false
    private var interactor: UIPercentDrivenInteractiveTransition?

    /// Environment has to be re-attached to EVERY hosted level — the cost noted above.
    private func host<V: View>(_ view: V) -> UIHostingController<AnyView> {
        UIHostingController(rootView: AnyView(
            view.environmentObject(FinchStore.shared)
                .environmentObject(DeepLinkRouter.shared)
                .environmentObject(BiometricGate.shared)
        ))
    }

    func makeList() -> UIViewController {
        let vc = host(
            List {
                Section {
                    Text("Real UINavigationController inside the real tab bar. Root-REPLACE, not push.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Open the Activity feed (root replace)") { [weak self] in self?.goForward() }
                Button("‹ Back to the menu") { [weak self] in self?.onExit() }
            }
            .navigationTitle("UIKit root-swap")
        )
        return vc
    }

    func goForward() {
        let detail = host(LabContent(variant: .uikitRootSwap20))
        // The SwiftUI page's own .navigationTitle / .toolbar / .searchable do NOT
        // reach a hosting controller's navigationItem here — the feed lost its
        // title, its Select/filter/sort buttons and its search field. Setting the
        // title by hand so the BAR TRANSITION is judgeable; the rest would each
        // need mapping to UIBarButtonItem / UISearchController by hand, per screen.
        detail.navigationItem.title = "Activity"
        detail.navigationItem.leftBarButtonItem =
            UIBarButtonItem(title: "‹ Menu", style: .plain, target: self, action: #selector(goBack))
        goingBack = false
        nav?.setViewControllers([detail], animated: true)
    }

    @objc func goBack() {
        goingBack = true
        nav?.setViewControllers([makeList()], animated: true)
    }

    // Default (native, push-direction) animation forward; our reverse animator back.
    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        goingBack ? RootSwapBackAnimator() : nil
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning)
    -> UIViewControllerInteractiveTransitioning? {
        interactor
    }

    /// A stack of one has no interactivePopGestureRecognizer, so the back swipe is
    /// ours to drive — again, machinery a real push gives away for free.
    @objc func handleEdge(_ g: UIScreenEdgePanGestureRecognizer) {
        guard let view = g.view else { return }
        let progress = min(max(g.translation(in: view).x / max(view.bounds.width, 1), 0), 1)
        switch g.state {
        case .began:
            interactor = UIPercentDrivenInteractiveTransition()
            goBack()
        case .changed:
            interactor?.update(progress)
        case .ended, .cancelled, .failed:
            if progress > 0.35 || g.velocity(in: view).x > 800 { interactor?.finish() } else { interactor?.cancel() }
            interactor = nil
        default:
            break
        }
    }
}

private struct UIKitRootSwapNav: UIViewControllerRepresentable {
    let onExit: () -> Void

    func makeCoordinator() -> RootSwapCoordinator {
        let c = RootSwapCoordinator(); c.onExit = onExit; return c
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let nav = UINavigationController()
        nav.delegate = context.coordinator
        context.coordinator.nav = nav
        nav.setViewControllers([context.coordinator.makeList()], animated: false)
        let edge = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator, action: #selector(RootSwapCoordinator.handleEdge(_:)))
        edge.edges = .left
        nav.view.addGestureRecognizer(edge)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

/// Hosts variant 20 inside the REAL tab bar, so the configuration under test is
/// TabView > UINavigationController > root-replaced page.
private struct RootSwapNavLab: View {
    @Binding var active: ShadowVariant?
    var body: some View {
        TabView {
            UIKitRootSwapNav(onExit: { active = nil })
                .ignoresSafeArea()
                .tabItem { Label("Lab", systemImage: "testtube.2") }
            Text("filler").tabItem { Label("Two", systemImage: "2.circle") }
            Text("filler").tabItem { Label("Three", systemImage: "3.circle") }
            Text("filler").tabItem { Label("Four", systemImage: "4.circle") }
            Text("filler").tabItem { Label("Five", systemImage: "5.circle") }
        }
    }
}

/// The replica bottom bar, shared by variants 18 and 19. A stand-in: enough to
/// judge layout and the shadow question, not a faithful iOS 26 tab bar.
private struct ReplicaBar: View {
    @Binding var selected: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                Button { selected = i } label: {
                    VStack(spacing: 3) {
                        Image(systemName: ["testtube.2", "2.circle", "3.circle", "4.circle", "5.circle"][i])
                            .font(.system(size: 20))
                        Text(["Lab", "Two", "Three", "Four", "Five"][i]).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selected == i ? Color.accentColor : Color.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

/// Variant 19 — the last configuration that could satisfy everything at once.
///
/// #8 (presented, no TabView) is the ONLY clean push found in 19 variants; #18
/// showed dropping the TabView alone is not enough, and #16 showed presenting
/// alone is not enough either. So take #8's exact structure and add a drawn
/// bottom bar, which is not a TabView and by the evidence should not matter.
///
/// If this is clean: native pushes, native bar behaviour, native swipe-back, a
/// visible bottom bar, and no shadow. The bill is BOTH of the costs we have
/// already priced — a replica bar (scroll-to-top on re-tap, minimise-on-scroll,
/// keyboard avoidance, accessibility all become ours) AND hosting the entire app
/// inside a permanently presented cover.
private struct CoverCustomBarLab: View {
    @Binding var active: ShadowVariant?
    @State private var presented = true
    @State private var path: [ShadowVariant] = []
    @State private var selected = 0

    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .fullScreenCover(isPresented: $presented, onDismiss: { active = nil }) {
                ZStack(alignment: .bottom) {
                    NavigationStack(path: $path) {
                        List {
                            Section {
                                Text("Presented cover, NO TabView, drawn bar. Push, scroll, Home, resume.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            NavigationLink(value: ShadowVariant.coverCustomBar19) {
                                Text("Push the Activity feed (native push)")
                            }
                            Button("‹ Back to the menu") { presented = false }
                        }
                        .navigationTitle("Cover + drawn bar")
                        .navigationDestination(for: ShadowVariant.self) { LabContent(variant: $0) }
                    }
                    ReplicaBar(selected: $selected)
                }
            }
    }
}

/// Variant 16 — the whole shell (tab bar AND each tab's NavigationStack) lives
/// inside a permanently-presented `fullScreenCover`, and navigation inside it is
/// an ordinary native push.
///
/// The reasoning: variant 8 showed a push INSIDE a presentation is clean, while
/// variants 0/2/3/5/7 showed every push OUTSIDE one shadows. If that immunity is
/// a property of the presented hierarchy rather than of the cover's own root,
/// then hosting the entire app this way makes every push in every tab clean —
/// native bar behaviour, native swipe-back, tab bar visible, and no custom
/// transition code anywhere.
private struct HostedShellLab: View {
    @Binding var active: ShadowVariant?
    @State private var presented = true

    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .fullScreenCover(isPresented: $presented, onDismiss: { active = nil }) {
                TabView {
                    NavigationStack {
                        List {
                            Section {
                                Text("The tab bar and this stack are INSIDE a cover. Push, scroll, Home, resume.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            NavigationLink("Push the Activity feed (native push)") {
                                LabContent(variant: .hostedShell16)
                            }
                            Button("‹ Back to the menu") { presented = false }
                        }
                        .navigationTitle("Hosted shell")
                    }
                    .tabItem { Label("Lab", systemImage: "testtube.2") }
                    Text("filler").tabItem { Label("Two", systemImage: "2.circle") }
                    Text("filler").tabItem { Label("Three", systemImage: "3.circle") }
                    Text("filler").tabItem { Label("Four", systemImage: "4.circle") }
                    Text("filler").tabItem { Label("Five", systemImage: "5.circle") }
                }
            }
    }
}

/// The app's real shape: TabView { NavigationStack { … } } — pushes land on the
/// tab's own stack, which is the configuration that shadows.
private struct NormalLab: View {
    let goOuter: (ShadowVariant) -> Void
    @State private var pushed: ShadowVariant?
    @State private var cover: ShadowVariant?
    @State private var swapped: ShadowVariant?
    @State private var minimize = false
    @State private var fsCover: ShadowVariant?
    @State private var dragX: CGFloat = 0
    @State private var slideOver: ShadowVariant?
    @Namespace private var zoomNS
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TabView {
            tab1
                .tabItem { Label("Lab", systemImage: "testtube.2") }
            Text("filler").tabItem { Label("Two", systemImage: "2.circle") }
            Text("filler").tabItem { Label("Three", systemImage: "3.circle") }
            Text("filler").tabItem { Label("Four", systemImage: "4.circle") }
            Text("filler").tabItem { Label("Five", systemImage: "5.circle") }
        }
        .modifier(MinimizeBehavior(on: minimize))
    }

    @ViewBuilder private var tab1: some View {
        GeometryReader { geo in
            ZStack {
                tab1Base
                    // Parallax: the page behind a native push moves at ~25% of the
                    // incoming page's travel. THIS is what variants 9 and 12 were
                    // missing — a root swap has only one root, so there was nothing
                    // behind the detail and the back-drag revealed bare background.
                    //
                    // A raw fractional offset re-rasterises the under-page's text at
                    // sub-pixel positions every frame, which reads as JITTER (v13).
                    // v14 snaps the offset to the physical pixel grid; v15 doesn't
                    // move the under-page at all.
                    .offset(x: baseOffset(width: geo.size.width))
                    .geometryGroup()
                    .overlay {
                        if slideOver?.slideOverStyle == .staticDim, slideOver != nil {
                            Color.black.opacity(0.18 * (1 - min(dragX / max(geo.size.width, 1), 1)))
                                .allowsHitTesting(false)
                                .ignoresSafeArea()
                        }
                    }
                    .disabled(slideOver != nil)

                if let v = slideOver, v == .sharedBar17 {
                    // Variant 17: NO inner NavigationStack. The detail's own
                    // .navigationTitle/.toolbar/.searchable therefore attach to the
                    // TAB's existing bar, so the bar is persistent chrome whose
                    // CONTENTS swap — the way a real push behaves — while only the
                    // content area slides.
                    LabContent(variant: v)
                        .frame(width: geo.size.width)
                        .offset(x: snap(dragX))
                        .geometryGroup()
                        .transition(.move(edge: .trailing))
                        .simultaneousGesture(backSwipe(width: geo.size.width))
                } else if let v = slideOver {
                    NavigationStack {
                        LabContent(variant: v)
                            .toolbar { ToolbarItem(placement: .topBarLeading) {
                                Button("‹ Menu") { withAnimation(.easeOut(duration: 0.3)) { slideOver = nil } } } }
                    }
                    .frame(width: geo.size.width)
                    .offset(x: snap(dragX))
                    .geometryGroup()
                    // The thin dark edge a real push casts on the page beneath.
                    .shadow(color: .black.opacity(0.18), radius: 8, x: -3)
                    .transition(.move(edge: .trailing))
                    .simultaneousGesture(backSwipe(width: geo.size.width))
                }
            }
        }
    }

    /// Snap a point value to the physical pixel grid (3x on this class of device).
    /// Sub-pixel offsets are what make the under-page's text shimmer while dragging.
    private func snap(_ v: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return v }
        return (v * displayScale).rounded() / displayScale
    }

    private func baseOffset(width: CGFloat) -> CGFloat {
        guard let style = slideOver?.slideOverStyle else { return 0 }
        switch style {
        case .staticDim:
            return 0
        case .parallax:
            return -width * 0.25 + dragX * 0.25            // raw — jitters
        case .parallaxPixelSnapped:
            return snap(-width * 0.25 + dragX * 0.25)      // grid-aligned
        }
    }

    /// Interactive back: begins only near the leading edge, like the system pop
    /// gesture, so it doesn't fight the list's scrolling or row swipe-actions.
    private func backSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { g in
                guard g.startLocation.x < 32, g.translation.width > 0 else { return }
                dragX = g.translation.width
            }
            .onEnded { g in
                guard g.startLocation.x < 32 else { return }
                let far = g.translation.width > width * 0.3
                let flick = g.predictedEndTranslation.width > width * 0.6
                withAnimation(.easeOut(duration: 0.25)) {
                    if far || flick { slideOver = nil }
                    dragX = 0
                }
            }
    }

    @ViewBuilder private var tab1Base: some View {
        NavigationStack {
            Group {
                if let v = swapped {
                    swappedRoot(v)
                } else {
                    menu.transition(.move(edge: .leading))
                }
            }
            .navigationDestination(item: $pushed) { LabDestination(variant: $0) }
            .toolbar {
                if slideOver == .sharedBar17 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("‹ Menu") { withAnimation(.easeOut(duration: 0.3)) { slideOver = nil } }
                    }
                }
            }
        }
        .rightSlideDrill(item: $cover) { v in
            NavigationStack {
                if v == .pushInCover8 {
                    // Variant 8: the cover's root is a plain list; the page under
                    // test is PUSHED inside the cover. Shipped code (Ledger flow,
                    // Settings 2nd level) assumes this arrangement is clean.
                    List {
                        NavigationLink("Push the Activity feed INSIDE this cover") {
                            LabContent(variant: v)
                        }
                    }
                    .navigationTitle("Cover root")
                    .rsdBackToolbar("Lab") { cover = nil }
                } else if v == .directRightSlide23 {
                    // One tap in, no intermediate list, no bottom bar — and a
                    // deeper level that pushes natively INSIDE the cover (#8).
                    LabContent(variant: v)
                        .rsdBackToolbar("Lab") { cover = nil }
                        .navigationDestination(for: String.self) { _ in
                            LabContent(variant: v).navigationTitle("Second level (native push)")
                        }
                        .safeAreaInset(edge: .bottom) {
                            NavigationLink(value: "deeper") {
                                Text("Go one level deeper (native push)")
                                    .font(.footnote)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(.ultraThinMaterial)
                            }
                        }
                } else {
                    LabContent(variant: v).rsdBackToolbar("Lab") { cover = nil }
                }
            }
        }
        .fullScreenCover(item: $fsCover) { v in
            NavigationStack {
                LabContent(variant: v)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("‹ Lab") { fsCover = nil }
                        }
                    }
                    // Variant 22: the cover lands STRAIGHT on the page (one tap in,
                    // no intermediate list as in #19), carries NO bottom bar, and a
                    // deeper level still pushes natively inside the cover — the
                    // arrangement #8 proved stays clean.
                    .navigationDestination(for: String.self) { _ in
                        LabContent(variant: v)
                            .navigationTitle("Second level (native push)")
                    }
                    .safeAreaInset(edge: .bottom) {
                        if v == .directCover22 {
                            NavigationLink(value: "deeper") {
                                Text("Go one level deeper (native push)")
                                    .font(.footnote)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(.ultraThinMaterial)
                            }
                        }
                    }
            }
            .modifier(ZoomIn(id: v.rawValue, ns: zoomNS, enabled: v == .cover10Zoom))
        }
    }

    /// Variants 4 / 9 / 12 — the destination replaces the stack's ROOT.
    /// 4 keeps the original VStack wrapper (which cost the List its scroll-edge
    /// effect, hence the opaque top bar); 9 and 12 put the List back as the root
    /// and move the back control into the toolbar.
    @ViewBuilder private func swappedRoot(_ v: ShadowVariant) -> some View {
        switch v {
        case .rootSwap4:
            VStack(spacing: 0) {
                HStack { Button("‹ Menu") { withAnimation(.easeInOut) { swapped = nil } }; Spacer() }
                    .padding(.horizontal)
                LabContent(variant: v)
            }
            .transition(.move(edge: .trailing))
        case .rootSwap12Draggable:
            LabContent(variant: v)
                .toolbar { ToolbarItem(placement: .topBarLeading) {
                    Button("‹ Menu") { withAnimation(.easeInOut) { swapped = nil } } } }
                .offset(x: dragX)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { g in if g.translation.width > 0 { dragX = g.translation.width } }
                        .onEnded { g in
                            if g.translation.width > 120 {
                                withAnimation(.easeOut) { swapped = nil; dragX = 0 }
                            } else {
                                withAnimation(.easeOut) { dragX = 0 }
                            }
                        }
                )
                .transition(.move(edge: .trailing))
        default:
            LabContent(variant: v)
                .toolbar { ToolbarItem(placement: .topBarLeading) {
                    Button("‹ Menu") { withAnimation(.easeInOut) { swapped = nil } } } }
                .transition(.move(edge: .trailing))
        }
    }

    private var menu: some View {
        List {
            Section {
                Text("Open a variant, SCROLL DOWN, press Home, wait ~3s, reopen. Watch under the top bar.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(ShadowVariant.allCases) { v in
                Button { open(v) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title).font(.body)
                        Text(v.blurb).font(.caption).foregroundStyle(.secondary)
                    }
                }
                // The zoom transition animates FROM the tapped row (variant 10).
                .modifier(ZoomSource(id: v.rawValue, ns: zoomNS, enabled: v == .cover10Zoom))
            }
        }
        .navigationTitle("Shadow lab")
    }

    /// Variant 21 — present over the shell, leaving the real tab bar exposed.
    private func presentPassthroughCover() {
        let content = NavigationStack {
            List {
                Section {
                    Text("The bar below is the REAL tab bar, showing through this cover. Try tapping it. Then push, scroll, Home, resume.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink("Push the Activity feed (native push)") {
                    LabContent(variant: .passthroughCover21)
                }
                Button("Close") { _pt_dismiss() }
            }
            .navigationTitle("Passthrough cover")
        }
        .environmentObject(FinchStore.shared)
        .environmentObject(DeepLinkRouter.shared)
        .environmentObject(BiometricGate.shared)

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .systemBackground
        let container = PassthroughContainer(host: host, stripHeight: 100)

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.first?.keyWindow?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        _pt_presented = container
        top.present(container, animated: true)
    }

    private func open(_ v: ShadowVariant) {
        minimize = (v == .push7TabBarMinimize)
        dragX = 0
        switch v {
        case .cover1Control, .pushInCover8, .directRightSlide23:  cover = v
        case .passthroughCover21:     presentPassthroughCover()
        case .rootSwap4, .rootSwap9Clean, .rootSwap12Draggable:   withAnimation(.easeInOut) { swapped = v }
        case .cover10Zoom, .cover11Plain, .directCover22:         fsCover = v
        case .slideOver13, .slideOver14Snapped, .slideOver15NoParallax, .sharedBar17:
            withAnimation(.easeOut(duration: 0.3)) { slideOver = v }
        case .hostedShell16, .customBar18, .coverCustomBar19, .uikitRootSwap20:
            goOuter(v)
        case .outer3StackWrapsTabView:                            goOuter(v)
        default:                                                  pushed = v
        }
    }
}

/// Variant 3: `NavigationStack { TabView { … } }`. The pushed page is not inside
/// any tab's stack, and the tab bar goes away for the push — the same thing a
/// cover achieves, but with a real push and native swipe-back.
private struct OuterStackLab: View {
    @Binding var active: ShadowVariant?
    @State private var path: [ShadowVariant] = []

    var body: some View {
        NavigationStack(path: $path) {
            TabView {
                List {
                    Section {
                        Text("Variant 3 — the stack wraps the TabView. Push, scroll, Home, resume.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Push the Activity feed on the OUTER stack") {
                        path = [.outer3StackWrapsTabView]
                    }
                    Button("‹ Back to the menu") { active = nil }
                }
                .navigationTitle("Outer stack")
                .tabItem { Label("Lab", systemImage: "testtube.2") }
                Text("filler").tabItem { Label("Two", systemImage: "2.circle") }
                Text("filler").tabItem { Label("Three", systemImage: "3.circle") }
                Text("filler").tabItem { Label("Four", systemImage: "4.circle") }
                Text("filler").tabItem { Label("Five", systemImage: "5.circle") }
            }
            .navigationDestination(for: ShadowVariant.self) { LabDestination(variant: $0) }
        }
    }
}

/// Variant 10 — a native SwiftUI cover that zooms from the tapped row instead of
/// sliding up. Covers are shadow-free; the only complaint about `.fullScreenCover`
/// was the slide-up feel, and this is Apple's own alternative to it (no UIKit).
private struct ZoomSource: ViewModifier {
    let id: String
    let ns: Namespace.ID
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled, #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}

private struct ZoomIn: ViewModifier {
    let id: String
    let ns: Namespace.ID
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled, #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            content
        }
    }
}

/// `tabBarMinimizeBehavior` is iOS 26-only and lives on the TabView, so it is a
/// modifier on the whole shell rather than on the destination.
private struct MinimizeBehavior: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(on ? .onScrollDown : .automatic)
        } else {
            content
        }
    }
}

#endif
