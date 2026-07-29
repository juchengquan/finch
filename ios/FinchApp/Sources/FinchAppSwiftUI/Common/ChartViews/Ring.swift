import SwiftUI

/// Circular progress ring — track circle + a colored arc (value/max), round cap,
/// starting at the top, optionally wrapping a centered label. Port of the web `Ring`.
struct Ring<Label: View>: View {
    let value: Double
    var max: Double = 100
    var size: CGFloat = 48
    var stroke: CGFloat = 5
    var color: Color = .accentColor
    var track: Color = Color.secondary.opacity(0.25)
    @ViewBuilder var label: () -> Label

    private var pct: Double { Swift.max(0, Swift.min(1, max == 0 ? 0 : value / max)) }

    var body: some View {
        ZStack {
            Circle().inset(by: stroke / 2).stroke(track, lineWidth: stroke)
            Circle().inset(by: stroke / 2)
                .trim(from: 0, to: pct)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((pct * 100).rounded())) percent"))
    }
}

extension Ring where Label == EmptyView {
    init(value: Double, max: Double = 100, size: CGFloat = 48, stroke: CGFloat = 5,
         color: Color = .accentColor, track: Color = Color.secondary.opacity(0.25)) {
        self.init(value: value, max: max, size: size, stroke: stroke,
                  color: color, track: track) { EmptyView() }
    }
}

#Preview("Ring") {
    HStack(spacing: 16) {
        Ring(value: 30) { Text("30%").font(.caption2) }
        Ring(value: 75, color: .orange)
        Ring(value: 100, color: .green, track: .green.opacity(0.2))
    }
    .padding()
}
