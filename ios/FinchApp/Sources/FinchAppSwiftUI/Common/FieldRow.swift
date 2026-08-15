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
/// - `help` is an optional one-line caption UNDER the field, for the rows whose label
///   does not carry its own meaning — "Currency" does not say that it is fixed once the
///   account exists. Give it only to those rows: a caption on Name reading "the
///   account's name" is noise, and noise teaches people to skip captions, which is what
///   makes the one that matters invisible.
/// - Accessibility: `title` is the row's a11y label; the glyph is hidden. `help` is an
///   accessibility HINT, not part of the label — spoken after the value, after a pause,
///   and switchable off system-wide. In the label it would be unskippable, and every
///   swipe through the form would read a full sentence.
struct FieldRow<Content: View, Trailing: View>: View {
    private let glyph: FieldGlyph
    private let title: LocalizedStringKey
    private let isEmpty: Bool
    private let content: Content
    private let trailing: Trailing
    private let help: LocalizedStringKey?

    /// Full initializer.
    init(glyph: FieldGlyph, title: LocalizedStringKey, isEmpty: Bool = false,
         help: LocalizedStringKey? = nil,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.glyph = glyph; self.title = title; self.isEmpty = isEmpty; self.help = help
        self.trailing = trailing(); self.content = content()
    }

    var body: some View {
        // No caption: the row stays exactly the single-line HStack it has always been,
        // so rows without help keep the 48pt floor and nothing else moves.
        if let help {
            VStack(alignment: .leading, spacing: 2) {
                row
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // Indented to the CONTENT column, not the row's leading edge: the
                    // glyph column stays a clean gutter and the caption reads as
                    // belonging to this field rather than to the section.
                    .padding(.leading, Self.contentInset)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(help))
        } else {
            row
        }
    }

    /// The glyph column's width plus the `HStack` spacing — what the content is already
    /// inset by, so the caption lines up with the field above it.
    private static var contentInset: CGFloat { 24 + 12 }

    private var row: some View {
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
            // Pin the row separator to the content column instead of letting SwiftUI
            // infer it. Left to itself it aligns most rows to their leading text but
            // falls back to the list's default inset for rows whose leading content is
            // a `TextField` — so the Amount row's separator started 36pt left of every
            // other row's in the Add and Edit sheets. Anchoring to the content's own
            // leading edge keeps that in step if the glyph column ever changes width.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            trailing
        }
    }
}

extension FieldRow where Trailing == EmptyView {
    /// Text-field / date / menu rows: always render `content`, no chevron.
    init(glyph: FieldGlyph, title: LocalizedStringKey, showsDefaultTrailing: Bool = false,
         help: LocalizedStringKey? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(glyph: glyph, title: title, isEmpty: false, help: help,
                  trailing: { EmptyView() }, content: content)
    }
}

extension FieldRow where Trailing == FieldRowChevron {
    /// Picker rows that open a sheet: grey `title` placeholder when `isEmpty`,
    /// else `content`, plus a trailing chevron.
    init(glyph: FieldGlyph, title: LocalizedStringKey, isEmpty: Bool,
         help: LocalizedStringKey? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(glyph: glyph, title: title, isEmpty: isEmpty, help: help,
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
