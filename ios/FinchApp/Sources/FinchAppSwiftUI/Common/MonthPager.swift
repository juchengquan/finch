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
    /// DISPLAY ONLY: the month the carousel is over right now, updated mid-drag as each
    /// halfway point is crossed. The header reads it so the month name can follow the
    /// finger; nothing that redraws the day list or moves the scroll may depend on it.
    var visible: Binding<Int?>? = nil

    /// Drives PROGRAMMATIC paging only — the chevrons, Today, the month-year wheels —
    /// by reporting where the carousel should be.
    ///
    /// Its write-back is deliberately dropped. SwiftUI reports the new month the moment
    /// the scroll passes the halfway point, which is mid-gesture with the finger still
    /// down; committing there re-rendered the calendar and the day list beneath it and
    /// made SwiftUI re-assert the very offset it was bound to, tugging the content.
    /// Measured: the largest single-frame jump in a slow drag was 3.23 against a 1.36
    /// average, and removing this write alone dropped it to 2.11. The commit now comes
    /// from `OneMonthPerSwipe`, which runs once, when the gesture ends.
    private var scrolled: Binding<Int?> {
        Binding(get: { anchorIndex },
                // The write goes to `visible`, never to the anchor. This is the month
                // the carousel is currently OVER, which SwiftUI reports as the scroll
                // passes each halfway point — useful for a label that follows the
                // finger, and exactly the wrong moment to tell the rest of the app the
                // month has changed.
                set: { if let index = $0 { visible?.wrappedValue = index } })
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
        .scrollTargetBehavior(OneMonthPerSwipe(firstPage: range.lowerBound) { landed in
            guard landed != anchorIndex else { return }
            // Off the scroll callback: this runs while the scroll view is choosing its
            // landing point, and mutating observed state inside that is a state-change-
            // during-update warning waiting to happen.
            DispatchQueue.main.async { anchorIndex = landed }
        })
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
///
/// It is also WHERE THE MONTH IS COMMITTED, because it is the one place that knows the
/// answer at the right time: it runs once per gesture, as the scroll picks the page it
/// will settle on. Everything else that could report a month change — `scrollPosition`
/// especially — reports it halfway through the drag instead.
private struct OneMonthPerSwipe: ScrollTargetBehavior {
    /// Absolute month index of the carousel's first page, so a page ordinal can be
    /// turned back into a month.
    let firstPage: Int
    /// The month the scroll is about to settle on.
    let onLand: (Int) -> Void

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let width = context.containerSize.width
        guard width > 0 else { return }
        let start = (context.originalTarget.rect.minX / width).rounded()
        let proposed = (target.rect.minX / width).rounded()
        let page = min(max(proposed, start - 1), start + 1)
        target.rect.origin.x = page * width
        onLand(firstPage + Int(page))
    }
}
#endif
