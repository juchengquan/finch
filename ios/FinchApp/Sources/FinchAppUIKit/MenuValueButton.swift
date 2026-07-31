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
/// behind. One helper instead.
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
}
#endif
