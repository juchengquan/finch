#if os(iOS)
import SwiftUI

/// A month section header: label on the left, figures right-aligned, and an
/// optional second line. Shared by the converted screens.
///
/// It is a hosted SwiftUI leaf rather than constraints because
/// `UIListContentConfiguration` has no trailing-aligned text slot, and the header
/// is exactly where the SwiftUI original put a right-aligned figure.
///
/// `Text(verbatim:)` throughout: the strings arrive already composed and
/// localized, and a plain `Text("…")` here would mint new string-catalog keys.
struct MonthSectionHeader: View {
    let label: String
    let trailing: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: label)
                Spacer()
                Text(verbatim: trailing)
            }
            if let subtitle {
                Text(verbatim: subtitle).font(.caption2)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
#endif
