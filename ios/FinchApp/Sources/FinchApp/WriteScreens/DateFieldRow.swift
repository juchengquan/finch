import SwiftUI

/// The shared Date row for the write sheets: the standard date + time
/// `DatePicker` (24-hour wheel) with a small "Today" shortcut to its left —
/// mirroring the Scheduled calendar's Today button. Tapping Today jumps the
/// calendar date to today while KEEPING the picked time-of-day; it's disabled
/// when the date is already today.
struct DateFieldRow: View {
    @Binding var date: Date
    var label: LocalizedStringKey = "Date"

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            // .borderless so the button is its own tap target inside the Form row
            // (default-styled buttons in a List row fire together / not at all).
            Button("Today") { jumpToToday() }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(isToday)
            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .environment(\.locale, AppDate.h24Locale)   // 24-hour wheel regardless of device setting
        }
    }

    /// Move the year/month/day to today's; preserve hour/minute/second.
    private func jumpToToday() {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute, .second], from: date)
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = time.hour; comps.minute = time.minute; comps.second = time.second
        if let d = cal.date(from: comps) { date = d }
    }
}
