import SwiftUI

/// A merchant's name + verified-seal badge — one definition so the Settings
/// Merchants list, its merge picker, and the transaction merchant picker render
/// verified merchants identically and can't drift. Trailing accessories (count
/// pill, chevron, selection checkmark) are added by each caller. The badge
/// inherits the ambient font, matching the existing Settings row verbatim.
struct MerchantLabel: View {
    let name: String
    let isVerified: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.primary)
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Verified")
            }
        }
    }
}
