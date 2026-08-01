#if os(iOS)
import UIKit

/// The drag grip shown at the trailing edge of a row while reordering, shared by
/// Categories, Accounts and Budgets.
///
/// **Deliberately not a control.** Nothing here starts the drag — the lift is
/// UIKit's long press anywhere on the cell, which each screen's `itemsForBeginning`
/// answers. A `UIButton` in this slot would swallow that long press and make the one
/// region that *looks* draggable the one region that isn't.
///
/// It is also NOT `UICellAccessory.reorder()`. That drives interactive movement via
/// `reorderingHandlers` and can only express linear index moves, which would cost
/// Categories its drag-to-nest outright and would force Accounts and Budgets off the
/// drop math they already have.
///
/// Hidden from VoiceOver: the drag it advertises has no VoiceOver equivalent on any
/// of these screens yet, so exposing it would promise an interaction that cannot be
/// performed.
func reorderGripAccessory(side: CGFloat = Metrics.tapTargetMin) -> UICellAccessory {
    let grip = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
    grip.tintColor = .tertiaryLabel
    // Centre rather than stretch — `AccessorySquare` pins it to all four edges.
    grip.contentMode = .center
    grip.isAccessibilityElement = false
    return .customView(configuration: .init(
        customView: AccessorySquare(side: side, content: grip),
        placement: .trailing(), reservedLayoutWidth: .custom(side)))
}

/// A fixed square for a cell accessory, with its content stretched to fill it.
///
/// **Two obvious ways to size a `customView` accessory both fail, and the failures
/// are silent or fatal rather than helpful — measure, don't assume:**
///
/// - Setting `customView.frame` does nothing. Categories' expand chevron carried
///   `frame = 22×30` from the day it was written and actually rendered at the glyph's
///   own ~15.7×22.3, because `UICellAccessory` sizes the view by Auto Layout and the
///   assigned frame is discarded. Bumping that frame to 44×44 changed nothing on
///   screen — a tap 18pt off the chevron's centre still drilled into the category.
/// - Setting `translatesAutoresizingMaskIntoConstraints = false` and pinning
///   width/height throws from `-[UICellAccessoryCustomView initWithCustomView:
///   placement:]` and takes the app down as the first cell is dequeued.
///
/// What survives both is `intrinsicContentSize`: the view stays autoresizing-mask
/// based, so the accessory accepts it, and Auto Layout gets a definite size to lay
/// out. Content is pinned to all four edges rather than centred, so the whole square
/// is the control's own bounds — a centred child would leave the surrounding margin
/// falling through to the cell, which is the bug this class exists to fix.
final class AccessorySquare: UIView {
    private let side: CGFloat

    /// - Parameter content: the control or glyph to fill the square. `nil` gives the
    ///   empty spacer childless rows reserve so trailing edges stay aligned.
    init(side: CGFloat, content: UIView?) {
        self.side = side
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        guard let content else { return }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: side, height: side) }
}
#endif
