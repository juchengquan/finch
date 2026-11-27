#if os(iOS)
import UIKit

/// The trailing value button on a menu-style settings row — "System ⌄", "Off ⌄".
///
/// The chevron is the affordance, not decoration: without it the row reads as a
/// plain value label and nothing says it opens a menu. SwiftUI's
/// `.pickerStyle(.menu)` draws one, so the converted rows have to as well.
///
/// Four screens built this button by hand — Appearance, Security, Ledger detail
/// and Backups — and none drew the chevron, so fixing one screen left three
/// behind. One helper instead, and one for the cell accessory around it, which
/// three screens had also copied.
enum MenuValueButton {
    static func make(value: String) -> UIButton {
        var conf = UIButton.Configuration.plain()
        conf.title = value
        conf.image = UIImage(systemName: "chevron.up.chevron.down")
        conf.imagePlacement = .trailing
        conf.imagePadding = 5
        conf.contentInsets = .zero
        conf.baseForegroundColor = .secondaryLabel
        conf.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption2)
        conf.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .preferredFont(forTextStyle: .body)
            return out
        }
        let button = UIButton(type: .system)
        button.configuration = conf
        button.showsMenuAsPrimaryAction = true
        return button
    }

    /// The row's trailing accessory: `value` with a menu of `options` (title shown,
    /// raw value passed to `onPick`), the current one ticked.
    ///
    /// `onPick` is stored in the cell's menu, and the cell lives in the screen's own
    /// collection view, so it must not hold the screen strongly.
    static func accessory(value: String, options: [(title: String, raw: String)],
                          onPick: @escaping (String) -> Void) -> UICellAccessory {
        let button = make(value: value)
        button.menu = UIMenu(children: options.map { option in
            UIAction(title: option.title, state: option.title == value ? .on : .off) { _ in onPick(option.raw) }
        })
        return .customView(configuration: .init(customView: button, placement: .trailing()))
    }
}
#endif
