import UIKit
import Combine
import FinchCore

/// The app-wide Undo banner for transaction deletes.
///
/// One instance per scene, driven by `FinchStore.deleteUndo` — so every delete
/// path (the edit sheet, a swipe, a context menu, the bulk bar, on any screen)
/// gets it without the screen doing anything.
///
/// It lives in its OWN window rather than in the global overlay: that overlay is
/// non-interactive by design (it must never eat a touch meant for the app), and
/// a delete from the edit sheet happens while a sheet is up. A window just above
/// `.normal` sits over sheets but under alerts and the lock screen (`.alert + 1`),
/// and lets every touch outside the capsule fall through to the app.
///
/// UIKit, not a hosted SwiftUI view: a pass-through window decides by hit-testing
/// subviews, and a SwiftUI button is not a subview of its hosting view.
@MainActor
final class UndoBannerController {
    private let window: PassthroughWindow
    private let banner = UndoBannerView()
    private let store: FinchStore
    private var cancellable: AnyCancellable?

    init(scene: UIWindowScene, store: FinchStore) {
        self.store = store
        window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.passthroughTarget = banner
        banner.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(banner)
        let guide = root.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -16),
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            banner.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -Self.clearance),
        ])
        banner.onUndo = { [weak self] in self?.undo() }
        cancellable = store.$deleteUndo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] offer in self?.render(offer) }
    }

    /// Clear of the floating tab bar AND of the add button that floats 20pt above
    /// it (56pt, on whichever side the user put it) — so the banner sits one row
    /// up, measured on an iPhone 17 Pro: the button's top is 125pt above the safe
    /// area's bottom edge, and this leaves 12pt between them.
    private static let clearance: CGFloat = 137

    /// For the scene's appearance + text-size preferences, which every window takes.
    var bannerWindow: UIWindow { window }

    private func render(_ offer: DeleteUndo?) {
        guard let offer else { return hide() }
        banner.message = offer.message
        if window.isHidden {
            window.isHidden = false   // NOT makeKey — the app's window keeps focus
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: 24)
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
                self.banner.alpha = 1
                self.banner.transform = .identity
            }
        }
        // Spoken, and the button is reachable: VoiceOver gets a longer window
        // (`FinchStore.undoWindow`) to get there.
        UIAccessibility.post(notification: .announcement, argument: offer.message)
    }

    private func hide() {
        guard !window.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: {
            self.banner.alpha = 0
            self.banner.transform = CGAffineTransform(translationX: 0, y: 24)
        }, completion: { _ in
            // A newer offer may have arrived while this one faded.
            if self.store.deleteUndo == nil { self.window.isHidden = true }
            else { self.banner.alpha = 1; self.banner.transform = .identity }
        })
    }

    private func undo() {
        do {
            try store.undoDelete()
            Haptics.success()
        } catch {
            let alert = UIAlertController(title: String(localized: "Couldn't undo"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            Self.topmost(window.windowScene)?.present(alert, animated: true)
        }
    }

    /// The front-most controller of the scene's app window — where the alert goes.
    private static func topmost(_ scene: UIWindowScene?) -> UIViewController? {
        let app = scene?.windows.first { $0.windowLevel == .normal && !$0.isHidden }
        var vc = app?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }
}

/// A window that only takes touches landing on `passthroughTarget`.
final class PassthroughWindow: UIWindow {
    weak var passthroughTarget: UIView?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let target = passthroughTarget, target.alpha > 0.01,
              let hit = super.hitTest(point, with: event), hit.isDescendant(of: target) else { return nil }
        return hit
    }
}

/// The capsule: "N transactions deleted" · Undo.
final class UndoBannerView: UIView {
    var onUndo: (() -> Void)?
    var message: String = "" { didSet { label.text = message } }

    private let label = UILabel()
    private let button = UIButton(configuration: .plain())

    override init(frame: CGRect) {
        super.init(frame: frame)
        let background: UIVisualEffectView
        if #available(iOS 26.0, *) {
            background = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        }
        background.translatesAutoresizingMaskIntoConstraints = false
        background.clipsToBounds = true
        background.layer.cornerCurve = .continuous
        addSubview(background)

        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        // One line, at its full width: the capsule hugs its text, and a short
        // message truncated to "2 transa…" (seen on the sim) is worse than a wider pill.
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.required - 1, for: .horizontal)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        var config = UIButton.Configuration.plain()
        config.title = String(localized: "Undo")
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFontMetrics(forTextStyle: .subheadline)
                .scaledFont(for: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold))
            return a
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        button.configuration = config
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.onUndo?() }, for: .primaryActionTriggered)
        button.accessibilityIdentifier = "undoDelete"
        // A confirmation popover fading out in the app window would otherwise dim
        // this to grey exactly when the banner appears.
        button.tintAdjustmentMode = .normal

        let row = UIStackView(arrangedSubviews: [label, button])
        row.alignment = .center
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -2),
            row.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        self.background = background
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    private var background: UIVisualEffectView?

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        background?.layer.cornerRadius = bounds.height / 2
    }
}
