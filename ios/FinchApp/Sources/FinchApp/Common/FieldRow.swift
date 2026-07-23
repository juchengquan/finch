import SwiftUI

/// The shared icon-led form-row chrome for the add/edit sheets:
/// `[colored glyph]  content-or-grey-placeholder  ……  [one trailing disclosure]`.
///
/// - The glyph (from `FieldGlyph`) leads in a fixed-width column so values align.
/// - `title` is the grey placeholder shown when the row is empty (picker rows);
///   text-field/menu/date rows always render their `content` and manage their own
///   empty state, so they use the initializer without `isEmpty`.
/// - Exactly one trailing disclosure: a `chevron.right` for sheet-opening rows,
///   or a caller-supplied `trailing` (e.g. a currency menu), or nothing.
/// - Accessibility: `title` is the row's a11y label; the glyph is hidden.
struct FieldRow<Content: View, Trailing: View>: View {
    private let glyph: FieldGlyph
    private let title: LocalizedStringKey
    private let isEmpty: Bool
    private let content: Content
    private let trailing: Trailing

    /// Full initializer.
    init(glyph: FieldGlyph, title: LocalizedStringKey, isEmpty: Bool = false,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.glyph = glyph; self.title = title; self.isEmpty = isEmpty
        self.trailing = trailing(); self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph.symbol)
                .font(.body)
                .foregroundStyle(glyph.tint)
                .frame(width: 24, alignment: .center)
                .accessibilityLabel(title)
            Group {
                if isEmpty {
                    Text(title).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityHidden(isEmpty)
            trailing
        }
    }
}

extension FieldRow where Trailing == EmptyView {
    /// Text-field / date / menu rows: always render `content`, no chevron.
    init(glyph: FieldGlyph, title: LocalizedStringKey, showsDefaultTrailing: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.init(glyph: glyph, title: title, isEmpty: false,
                  trailing: { EmptyView() }, content: content)
    }
}

extension FieldRow where Trailing == FieldRowChevron {
    /// Picker rows that open a sheet: grey `title` placeholder when `isEmpty`,
    /// else `content`, plus a trailing chevron.
    init(glyph: FieldGlyph, title: LocalizedStringKey, isEmpty: Bool,
         @ViewBuilder content: () -> Content) {
        self.init(glyph: glyph, title: title, isEmpty: isEmpty,
                  trailing: { FieldRowChevron() }, content: content)
    }
}

/// The standard trailing disclosure for sheet-opening rows.
struct FieldRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
