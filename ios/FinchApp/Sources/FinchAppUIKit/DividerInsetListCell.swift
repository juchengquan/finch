#if os(iOS)
import UIKit

/// A list cell whose divider starts at a fixed inset instead of under the row's text.
///
/// Setting `separatorConfiguration` on the list configuration does NOT achieve this, which
/// cost a round of measurement to discover: a content configuration owns the cell's
/// `separatorLayoutGuide` and aligns it to its own content, so the per-cell guide wins over
/// anything set list-wide. Every row on these screens is a `UIHostingConfiguration`, so
/// every row overrode it — the list-level setting measured as having no effect at all.
///
/// Constraining the guide is Apple's documented lever for this, and it has to happen ONCE
/// per cell instance: a `CellRegistration` handler re-runs on every configure and on every
/// reuse, so activating the constraint there would stack a fresh identical constraint each
/// time. `init` runs once, which is why this is a subclass rather than a line in the
/// handler.
///
/// See `Metrics.rowSeparatorInset` for why the inset is what it is.
final class DividerInsetListCell: UICollectionViewListCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        separatorLayoutGuide.leadingAnchor
            .constraint(equalTo: leadingAnchor, constant: Metrics.rowSeparatorInset)
            .isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
