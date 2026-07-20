import SwiftUI

/// The section title used by the add/edit sheets' grouped `Form`/`List`
/// sections — used as a section's `header:` so title spacing is driven by
/// `Metrics` instead of the system default:
///
///     Section { … } header: { finchSectionHeader("Tracking") }
///
/// Scope: the five add/edit sheets (14 call sites) — Account, Budget,
/// Add/Edit Transaction, Scheduled. Other screens' `Section("…")` headers
/// still use system rendering, so changing this token only affects these
/// sheets.
///
/// `.textCase(nil)` is required: SwiftUI upper-cases grouped-list headers by
/// default, and these sheets render their titles in title case.
func finchSectionHeader(_ title: LocalizedStringKey) -> some View {
    Text(title)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.top, Metrics.headerTopPadding)
        .padding(.bottom, Metrics.headerBottomPadding)
}
