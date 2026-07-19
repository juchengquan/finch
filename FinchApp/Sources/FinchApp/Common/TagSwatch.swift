import SwiftUI

/// The standard tag color dot — a single definition so every tag surface (the
/// Settings Tags list, the transaction tag picker) renders the same size and
/// style, and they can't drift apart. Falls back to `.secondary` when a tag has
/// no color (matches the Settings list).
struct TagSwatch: View {
    let hex: String?
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(Color(hex: hex ?? "") ?? .secondary)
            .frame(width: size, height: size)
    }
}
