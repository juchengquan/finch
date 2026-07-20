import SwiftUI

/// The app-wide section title for grouped `Form`/`List` sections — used as a
/// section's `header:` so title spacing is driven by `Metrics` instead of the
/// system default:
///
///     Section { … } header: { finchSectionHeader("Tracking") }
///
/// `.textCase(nil)` is required: SwiftUI upper-cases grouped-list headers by
/// default, and these sheets render their titles in title case.
func finchSectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.top, Metrics.headerTopPadding)
        .padding(.bottom, Metrics.headerBottomPadding)
}
