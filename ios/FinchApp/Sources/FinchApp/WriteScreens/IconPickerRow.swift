import SwiftUI

/// A form row that shows the current category icon and opens a full-height BOTTOM
/// SHEET with the themed icon grid (`CategoryIcon.groups`). Mirrors
/// `SearchablePickerRow`: the sheet STAGES the tapped icon and commits it on
/// Confirm (Cancel discards) — no accidental change on a stray tap. An empty
/// selection ("") means "no icon" (inherit at render); tapping the staged icon
/// again clears it.
struct IconPickerRow: View {
    let title: String
    @Binding var selection: String
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selection.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    Image(systemName: CategoryIcon.symbol(for: selection))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            IconPickerSheet(title: title, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: the themed icon grid, single-select. Tapping stages an icon
/// (tapping it again clears to none); Confirm applies it and dismisses; Cancel
/// discards.
private struct IconPickerSheet: View {
    let title: String
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var staged: String

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    init(title: String, selection: Binding<String>) {
        self.title = title
        self._selection = selection
        self._staged = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(CategoryIcon.groups) { group in
                    Section(group.title) {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.names, id: \.self) { n in
                                Image(systemName: CategoryIcon.symbol(for: n))
                                    .font(.system(size: 18))
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(staged == n ? Color.accentColor.opacity(0.2) : .clear))
                                    .overlay(Circle().stroke(Color.accentColor, lineWidth: staged == n ? 2 : 0))
                                    .contentShape(Circle())
                                    .onTapGesture { staged = (staged == n ? "" : n) }
                                    .accessibilityLabel("Icon \(n)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { selection = staged; dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Confirm").confirmCheckmarkStyle()
                }
            }
        }
    }
}
