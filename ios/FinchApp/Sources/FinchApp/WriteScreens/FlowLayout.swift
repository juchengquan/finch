import SwiftUI

/// A wrapping layout: places subviews left-to-right, breaking to a new row when
/// the next subview would overflow the proposed width. iOS 17 `Layout`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + s.width > maxWidth {
                totalHeight += rowHeight + rowSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = s.width; rowHeight = s.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + s.width
                rowHeight = max(rowHeight, s.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxX = bounds.maxX
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > maxX {
                x = bounds.minX; y += rowHeight + rowSpacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
