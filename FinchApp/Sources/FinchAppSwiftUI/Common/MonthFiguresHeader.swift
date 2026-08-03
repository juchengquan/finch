import SwiftUI

/// A month section header whose figures sit BELOW the month name: net, in, out, told
/// apart by sign and reinforced by colour.
///
/// Replaces the old "net after the month name, Income · Spent underneath" shape on the
/// transaction feeds. `MonthSectionHeader` (FinchAppUIKit) stays as it is for Budget
/// detail, which shows a single trailing figure and no breakdown.
///
/// The row is ONE accessibility element with a spoken label, because everything that
/// separates these three figures visually — sign, colour, position — is either invisible
/// or meaningless to VoiceOver, which would otherwise read three bare amounts in a row.
struct MonthFiguresHeader: View {
    let label: String
    let figures: [MonthHeaderFigures.Figure]
    /// Spoken in place of the figures, e.g. "net −$1,234.56, income $8,964.99, spent $3,999.12".
    let accessibilityText: String

    private func color(_ role: MonthHeaderFigures.Role) -> Color {
        switch role {
        case .net: return .secondary
        case .income: return .green
        case .expense: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                    Text(verbatim: figure.text).foregroundStyle(color(figure.role))
                }
            }
            // Smaller than the month name, so the header still reads as a header.
            .font(.caption2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label + ", " + accessibilityText))
    }
}
