#if os(iOS)
import SwiftUI

/// The month carousel's paging engine: a horizontally-paged `ScrollView` whose pages
/// are months, addressed by absolute month index.
///
/// **What was wrong before.** The carousel was a three-page `TabView` holding a
/// −1/0/+1 window around the anchored month. A settled swipe had to commit the new
/// month and then snap the pager back to centre, and that snap-back raced the page
/// controller's own in-flight completion, which re-emitted its selection write on top
/// of the recentred state — two months per swipe. Pinning `.id(monthIndex)` on the
/// TabView fixed that by recreating the pager after every commit, but identity changes
/// the instant the selection commits, which is when the slide *starts*: SwiftUI tore
/// the pager down mid-animation, so a swipe rendered 15 of 34 frames — motion, a
/// ~50ms freeze holding a half-slid grid, then a jump to the settled month.
///
/// **What changes here.** Every page simply *is* its month, so there is no window to
/// recentre and nothing in flight to re-emit: the double advance has no mechanism
/// rather than being papered over, and no view identity changes during a swipe, so the
/// scroll runs to its end. `scrollPosition` binds straight through to the caller's
/// anchor — there is no second source of truth to disagree with it. Measured on the
/// same swipe as the numbers above: 47 of 52 frames move.
///
/// **Why not `UIPageViewController`.** It reports transition completion precisely,
/// which is tempting here, but it is a `UIViewControllerRepresentable` and the three
/// UIKit screens host this calendar inside a `UIHostingConfiguration` cell, which does
/// not support view-controller representables — the grid renders as SwiftUI's yellow
/// placeholder instead of a calendar. A paged `ScrollView` is plain SwiftUI and hosts
/// anywhere.
///
/// Paging stays lazy: `LazyHStack` builds only the months on screen, which is why a
/// pager spanning a century costs no more than the old three-page window.
///
/// Covered by `MonthPagerUITests`, which asserts one swipe moves exactly one month.
struct MonthPager<Page: View>: View {
    /// The anchored month's absolute index. Writing it pages the carousel; the
    /// carousel writes back to it when a swipe settles. One value, both directions —
    /// the arrangement that made the old double advance possible was having two.
    @Binding var anchorIndex: Int
    /// The months the carousel can reach, as absolute indices.
    let range: ClosedRange<Int>
    /// Builds one month's grid.
    @ViewBuilder let page: (Int) -> Page

    /// `scrollPosition` deals in optionals; the anchor never is. A nil write (which
    /// SwiftUI can emit mid-gesture) leaves the anchor alone rather than resetting it.
    private var scrolled: Binding<Int?> {
        Binding(get: { anchorIndex },
                set: { if let index = $0, index != anchorIndex { anchorIndex = index } })
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(range, id: \.self) { index in
                    page(index)
                        // Exactly one carousel-width per page — what lets the scroll
                        // target behaviour below reason in whole months.
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(OneMonthPerSwipe())
        .scrollIndicators(.hidden)
        .scrollPosition(id: scrolled)
    }
}

/// Lands on the month NEXT TO the one the gesture started on — never further.
///
/// Neither stock behaviour does this on its own. `.paging` lets a flick carry its
/// momentum across several pages, and `.viewAligned(limitBehavior: .always)` — iOS
/// 17's only "limit" option, since `.alwaysByOne` is iOS 18 — still landed two months
/// away on a measured 770pt/s swipe, while reporting one to a UI test's synthetic
/// flick. So the limit is enforced here rather than hoped for: clamp the proposed
/// landing to ±1 page from `originalTarget`, which no gesture can outrun.
///
/// Working in whole pages is exact — every page is one container width and the stack
/// has no spacing, so page *k* sits at *k × width* and no fractional drift accumulates.
private struct OneMonthPerSwipe: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let width = context.containerSize.width
        guard width > 0 else { return }
        let start = (context.originalTarget.rect.minX / width).rounded()
        let proposed = (target.rect.minX / width).rounded()
        target.rect.origin.x = min(max(proposed, start - 1), start + 1) * width
    }
}
#endif
