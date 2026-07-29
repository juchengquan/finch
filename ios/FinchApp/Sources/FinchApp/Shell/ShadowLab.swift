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

    var id: String { rawValue }

    /// The three slide-over flavours share one container; this picks the
    /// under-layer treatment being compared.
    var slideOverStyle: SlideOverStyle? {
        switch self {
        case .slideOver13:         return .parallax
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

/// Per-variant modifier applied to the PUSHED destination.
private struct LabDestination: View {
    let variant: ShadowVariant
    var body: some View {
        switch variant {
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
        if outerVariant != nil {
            // Variant 3: one stack ABOVE the whole TabView.
            OuterStackLab(active: $outerVariant)
        } else {
            NormalLab(goOuter: { outerVariant = $0 })
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

                if let v = slideOver {
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

    private func open(_ v: ShadowVariant) {
        minimize = (v == .push7TabBarMinimize)
        dragX = 0
        switch v {
        case .cover1Control, .pushInCover8:                       cover = v
        case .rootSwap4, .rootSwap9Clean, .rootSwap12Draggable:   withAnimation(.easeInOut) { swapped = v }
        case .cover10Zoom, .cover11Plain:                         fsCover = v
        case .slideOver13, .slideOver14Snapped, .slideOver15NoParallax:
            withAnimation(.easeOut(duration: 0.3)) { slideOver = v }
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
