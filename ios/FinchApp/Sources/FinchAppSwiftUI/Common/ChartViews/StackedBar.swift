import SwiftUI

/// Horizontal stacked bar of proportional colored segments (2pt gaps, rounded). Port of
/// the web `StackedBar`; width fills the container.
struct StackedBar: View {
    struct Slice: Identifiable { let id = UUID(); let value: Double; let color: Color }
    let slices: [Slice]
    var height: CGFloat = 8
    var cornerRadius: CGFloat = 4
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let total = Swift.max(slices.reduce(0) { $0 + $1.value }, 0.0001)
            let usable = Swift.max(geo.size.width - gap * CGFloat(Swift.max(slices.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(slices) { s in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(s.color)
                        .frame(width: usable * (s.value / total))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview("StackedBar") {
    StackedBar(slices: [
        .init(value: 3, color: .blue),
        .init(value: 2, color: .green),
        .init(value: 1, color: .orange),
    ])
    .frame(width: 280)
    .padding()
}
