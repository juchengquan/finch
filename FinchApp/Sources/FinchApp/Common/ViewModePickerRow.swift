import SwiftUI

/// The Calendar|List segmented mode toggle as a list row (clear background, no
/// separator) — shared by the Scheduled and Activity tabs so the row styling
/// (and any future localization fix for the titles) lives in exactly one place.
struct ViewModePickerRow<Mode: Hashable>: View {
    @Binding var selection: Mode
    let options: [(value: Mode, title: String)]

    var body: some View {
        Picker("View", selection: $selection) {
            ForEach(options, id: \.value) { o in Text(o.title).tag(o.value) }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
