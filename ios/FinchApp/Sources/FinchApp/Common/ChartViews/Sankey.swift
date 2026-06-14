import SwiftUI

/// Income → category flow. A full ribbon Sankey is heavy in SwiftUI; this renders
/// the same information as a proportional flow bar (income split into category
/// segments + what's saved) with a legend. Port of the web Insights income Sankey.
struct Sankey: View {
    struct Segment: Identifiable { let id: String; let label: String; let value: Double; let color: Color }
    let total: Double          // income
    let segments: [Segment]    // categories + "Saved"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments) { seg in
                        Rectangle().fill(seg.color)
                            .frame(width: max(2, geo.size.width * width(seg.value)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 22)

            // Legend
            ForEach(segments) { seg in
                HStack(spacing: 8) {
                    Circle().fill(seg.color).frame(width: 9, height: 9)
                    Text(seg.label).font(.caption)
                    Spacer()
                    Text("\(Int((width(seg.value) * 100).rounded()))%")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func width(_ v: Double) -> Double { total > 0 ? max(0, v / total) : 0 }
}
