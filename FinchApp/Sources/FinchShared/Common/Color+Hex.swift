import SwiftUI

extension Color {
    /// Parse a `#rrggbb` (or `rrggbb`) hex string into 0...1 RGB components.
    /// Returns nil on anything that isn't exactly 6 hex digits. Pure + testable.
    static func rgb(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xff) / 255.0,
                Double((v >> 8) & 0xff) / 255.0,
                Double(v & 0xff) / 255.0)
    }

    /// Failable init from a `#rrggbb` hex string.
    init?(hex: String) {
        guard let c = Color.rgb(fromHex: hex) else { return nil }
        self.init(red: c.r, green: c.g, blue: c.b)
    }
}

/// The shared 8-swatch category palette (parity with web `lib/colors.ts`).
enum CategoryPalette {
    static let hexes = ["#d16b7a", "#d1714f", "#ae8a0d", "#31a773",
                        "#00a6ae", "#00a0c5", "#8085dc", "#b273c0"]
    static let defaultHex = "#00a0c5"
}

/// The shared 8-swatch tag palette (parity with web `lib/colors.ts` `tagHex`,
/// chroma 0.18 — distinct from `CategoryPalette`).
enum TagPalette {
    static let hexes = ["#e75572", "#e65f2a", "#ba8600", "#00af67",
                        "#00adba", "#00a5da", "#7d7df9", "#be64d2"]
    static let defaultHex = "#00a5da"
}
