import SwiftUI
import FinchCore

/// The filter state for the transaction feed. Value type; `fromYMD`/`toYMD` convert
/// the picked dates to the strings `ListOptions` expects — "yyyy-MM-dd", or
/// "yyyy-MM-dd HH:mm" once a bound carries a time of day.
struct TxFilter: Equatable, Codable {
    var direction: String? = nil       // nil = all, "in", "out"
    var accountId: String? = nil
    var categoryId: String? = nil
    var tagIds: Set<String> = []
    var tagsMatchAll: Bool = false
    var counterpartyId: String? = nil
    var status: String? = nil          // nil = all, "pending", "confirmed"
    var from: Date? = nil
    var to: Date? = nil
    var minAmount: Double? = nil
    var maxAmount: Double? = nil

    var isActive: Bool {
        direction != nil || accountId != nil || categoryId != nil || !tagIds.isEmpty
            || counterpartyId != nil
            || status != nil || from != nil || to != nil || minAmount != nil || maxAmount != nil
    }

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
    }()

    /// Midnight means "no time given", so a bound left at 00:00 sends a bare date.
    ///
    /// It has to: the picker always produces a time, and "to 2026-08-01 00:00" would
    /// exclude everything after midnight on the closing day — a range that silently
    /// loses a day compared with what it does today. Whereas a bare "to 2026-08-01"
    /// includes the whole day, which is what a range picked by day means.
    private static func stamp(_ d: Date) -> String {
        let time = hm.string(from: d)
        return time == "00:00" ? ymd.string(from: d) : "\(ymd.string(from: d)) \(time)"
    }
    var fromYMD: String? { from.map { Self.stamp($0) } }
    var toYMD: String? { to.map { Self.stamp($0) } }
}

/// Edits a `TxFilter` in a sheet (apply on Done; Cancel discards).
struct TransactionFilterSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TxFilter

    @State private var draft: TxFilter
    @State private var minText: String
    @State private var maxText: String
    @State private var useFrom: Bool
    @State private var useTo: Bool
    @State private var fromDate: Date
    @State private var toDate: Date

    init(filter: Binding<TxFilter>) {
        _filter = filter
        let f = filter.wrappedValue
        _draft = State(initialValue: f)
        _minText = State(initialValue: f.minAmount.map { String(format: "%g", $0) } ?? "")
        _maxText = State(initialValue: f.maxAmount.map { String(format: "%g", $0) } ?? "")
        _useFrom = State(initialValue: f.from != nil)
        _useTo = State(initialValue: f.to != nil)
        _fromDate = State(initialValue: f.from ?? Date())
        _toDate = State(initialValue: f.to ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $draft.direction) {
                        Text("All").tag(String?.none)
                        Text("Money in").tag(String?.some("in"))
                        Text("Money out").tag(String?.some("out"))
                    }
                }
                Section {
                    Picker("Account", selection: $draft.accountId) {
                        Text("Any").tag(String?.none)
                        ForEach(store.accounts) { Text($0.name ?? "—").tag(String?.some($0.id)) }
                    }
                    Picker("Category", selection: $draft.categoryId) {
                        Text("Any").tag(String?.none)
                        ForEach(store.pickableCategories) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    if !store.tags.isEmpty {
                        ForEach(store.tags) { tag in
                            Button {
                                if draft.tagIds.contains(tag.id) { draft.tagIds.remove(tag.id) }
                                else { draft.tagIds.insert(tag.id) }
                            } label: {
                                HStack {
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if draft.tagIds.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                        if draft.tagIds.count >= 2 {
                            Picker("Match", selection: $draft.tagsMatchAll) {
                                Text("Any tag").tag(false)
                                Text("All tags").tag(true)
                            }
                        }
                    }
                    if !store.merchants.isEmpty {
                        Picker("Merchant", selection: $draft.counterpartyId) {
                            Text("Any").tag(String?.none)
                            ForEach(store.merchants) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
                    Picker("Status", selection: $draft.status) {
                        Text("All").tag(String?.none)
                        Text("Pending").tag(String?.some("pending"))
                        Text("Confirmed").tag(String?.some("confirmed"))
                    }
                }
                Section("Date range") {
                    Toggle("From", isOn: $useFrom).switchOnlyToggles()
                    if useFrom { DatePicker("From date", selection: $fromDate, displayedComponents: [.date, .hourAndMinute]).labelsHidden().environment(\.locale, AppDate.h24Locale) }
                    Toggle("To", isOn: $useTo).switchOnlyToggles()
                    if useTo { DatePicker("To date", selection: $toDate, displayedComponents: [.date, .hourAndMinute]).labelsHidden().environment(\.locale, AppDate.h24Locale) }
                }
                Section("Amount range") {
                    HStack { Text("Min"); Spacer(); TextField("0", text: $minText).numericInput($minText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Max"); Spacer(); TextField("∞", text: $maxText).numericInput($maxText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
                Section {
                    Button("Clear all", role: .destructive) {
                        draft = TxFilter(); minText = ""; maxText = ""; useFrom = false; useTo = false
                    }
                }
            }
            .navigationTitle("Filter")
            .finchSectionSpacing()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button { apply(); dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Done").confirmCheckmarkStyle()
                }
            }
        }
    }

    private func apply() {
        draft.from = useFrom ? fromDate : nil
        draft.to = useTo ? toDate : nil
        draft.minAmount = DecimalInput.parse(minText)
        draft.maxAmount = DecimalInput.parse(maxText)
        filter = draft
    }
}
