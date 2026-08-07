import SwiftUI

/// A date + time field that always reads in 24-hour time and **does not move when a
/// sheet opens**.
///
/// The obvious spelling — `DatePicker(…).labelsHidden().environment(\.locale,
/// AppDate.h24Locale)` — reads correctly but glides. A compact `DatePicker` is a
/// bridged `UIDatePicker`, and a `UIDatePicker` whose `locale` differs from the
/// device's re-measures its label a beat after its first layout. Forcing 24-hour on a
/// 12-hour device is exactly that difference. A sheet presentation is an open
/// animation transaction, so UIKit interpolates the correction and the Date row —
/// alone among the fields, being the only UIKit-backed one — slides ~23pt left as the
/// sheet settles.
///
/// Measured on a 12-hour simulator, tracking the pill's x through the sheet open:
/// 69px of travel with the override, 1px without it. It is **not** fixed by
/// `.fixedSize()`, by hiding/showing the label, by hoisting the override to the
/// sheet's root, by `.transaction { $0.animation = nil }`, by `AppleICUForce24HourTime`,
/// nor by wrapping `UIDatePicker` ourselves and setting `locale` in `makeUIView`
/// (with or without `performWithoutAnimation` around `layoutSubviews`) — the
/// re-measure happens inside UIKit either way. The only thing that removes it is not
/// putting a differently-localed `UIDatePicker` in the row at all, which is what this
/// type does: the row is plain SwiftUI text, and the system picker appears in a sheet
/// on tap, where there is no row to drag along with it.
struct H24DatePicker: View {
    private let title: LocalizedStringResource
    @Binding private var selection: Date
    /// Most callers sit in a `FieldRow`, which already draws the label; the two that
    /// sit in a plain `Section` want the ordinary label-left/control-right Form row.
    private let labelsHidden: Bool

    init(_ title: LocalizedStringResource, selection: Binding<Date>, labelsHidden: Bool = true) {
        self.title = title
        self._selection = selection
        self.labelsHidden = labelsHidden
    }

    var body: some View {
        if labelsHidden {
            field
        } else {
            LabeledContent { field } label: { Text(title) }
        }
    }

    #if os(iOS)
    @State private var editing: Part?

    /// Which half of the field the tap opened, mirroring the system control's two pills.
    private enum Part: String, Identifiable { case date, time; var id: String { rawValue } }

    private var field: some View {
        HStack(spacing: 8) {
            pill(Self.dateText(selection)) { editing = .date }
                .accessibilityLabel(Text(title))
                .accessibilityValue(Self.dateText(selection))
            pill(Self.timeText(selection)) { editing = .time }
                .accessibilityValue(Self.timeText(selection))
        }
        .sheet(item: $editing) { part in editor(part) }
    }

    private func pill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func editor(_ part: Part) -> some View {
        NavigationStack {
            Group {
                switch part {
                case .date:
                    DatePicker(title, selection: $selection, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                case .time:
                    DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
            }
            .environment(\.locale, AppDate.h24Locale)
            .padding(.horizontal)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { editing = nil }
                }
            }
        }
        .presentationDetents([part == .date ? .medium : .height(280)])
    }
    #else
    // No `UIDatePicker` off iOS, so no re-measure to design around.
    private var field: some View {
        DatePicker(title, selection: $selection, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .environment(\.locale, AppDate.h24Locale)
    }
    #endif

    private static func dateText(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppDate.h24Locale))
    }

    private static func timeText(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppDate.h24Locale))
    }
}
