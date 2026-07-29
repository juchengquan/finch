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

enum ShadowVariant: String, CaseIterable, Identifiable {
    case push0Control
    case cover1Control
    case push2TabBarHidden
    case outer3StackWrapsTabView
    case rootSwap4
    case push5BottomEdgeHidden
    case push6BackgroundExtension
    case push7TabBarMinimize

    var id: String { rawValue }

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
        NavigationStack {
            Group {
                if let v = swapped {
                    // Variant 4: the destination IS the stack's root.
                    VStack(spacing: 0) {
                        HStack {
                            Button("‹ Menu") { withAnimation(.easeInOut) { swapped = nil } }
                            Spacer()
                        }
                        .padding(.horizontal)
                        LabContent(variant: v)
                    }
                    .transition(.move(edge: .trailing))
                } else {
                    menu.transition(.move(edge: .leading))
                }
            }
            .navigationDestination(item: $pushed) { LabDestination(variant: $0) }
        }
        .rightSlideDrill(item: $cover) { v in
            NavigationStack { LabContent(variant: v).rsdBackToolbar("Lab") { cover = nil } }
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
            }
        }
        .navigationTitle("Shadow lab")
    }

    private func open(_ v: ShadowVariant) {
        minimize = (v == .push7TabBarMinimize)
        switch v {
        case .cover1Control:           cover = v
        case .rootSwap4:               withAnimation(.easeInOut) { swapped = v }
        case .outer3StackWrapsTabView: goOuter(v)
        default:                       pushed = v
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
