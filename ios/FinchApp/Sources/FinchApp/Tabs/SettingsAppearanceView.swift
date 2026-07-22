import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "", english = "en", chinese = "zh-Hans"
    var id: String { rawValue }
    var label: String {
        switch self { case .system: return "System"; case .english: return "English"; case .chinese: return "简体中文" }
    }
}

/// Settings › Appearance & Language — theme (live) + app language (applied on relaunch).
struct SettingsAppearanceView: View {
    @AppStorage("finch.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage("finch.language") private var languageRaw = AppLanguage.system.rawValue
    @AppStorage(TextSize.systemKey) private var useSystemTextSize = true
    @AppStorage(TextSize.stepKey) private var textSizeStep = TextSize.defaultStep
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    @AppStorage("finch.feed.relativeDates") private var relativeDates = true
    @AppStorage("finch.account.showOpeningBalance") private var showOpeningBalance = true
    @AppStorage("finch.addSheet.showAdjustBalance") private var showAdjustInAddSheet = false
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @AppStorage("finch.fab.enabled") private var fabEnabled = true
    @AppStorage("finch.fab.position") private var fabPositionRaw = FabPosition.right.rawValue
    @State private var showRelaunchNote = false

    var body: some View {
        List {
            Section("Theme") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Use system size", isOn: $useSystemTextSize)
                if !useSystemTextSize {
                    HStack(spacing: 12) {
                        Text("A").font(.footnote).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(textSizeStep) },
                                              set: { textSizeStep = Int($0.rounded()) }),
                               in: 0...Double(TextSize.steps.count - 1), step: 1)
                            .accessibilityLabel("Text size")
                        Text("A").font(.title3).foregroundStyle(.secondary)
                    }
                    Text("Sample — $1,234.56")
                        .dynamicTypeSize(TextSize.size(forStep: textSizeStep))
                }
            } header: {
                Text("Text size")
            } footer: {
                Text(useSystemTextSize ? "Follows the system Text Size setting." : "Overrides the system text size inside finch.")
            }
            Section {
                Picker("Language", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: languageRaw) { _, newValue in
                    let lang = AppLanguage(rawValue: newValue) ?? .system
                    if lang == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                    else { UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages") }
                    showRelaunchNote = true
                }
            } header: {
                Text("Language")
            } footer: {
                Text(showRelaunchNote ? "Relaunch finch to apply the new language."
                                      : "Switches the app's language. Takes effect after relaunch.")
                    .foregroundStyle(showRelaunchNote ? .orange : .secondary)
            }
            Section {
                Toggle("Group by month", isOn: $groupByMonth)
                Toggle("Relative dates", isOn: $relativeDates)
            } header: {
                Text("Activity feed")
            } footer: {
                Text("Group by month also applies to an account's transaction list.")
            }
            Section("Accounts") {
                Toggle("Show opening balance", isOn: $showOpeningBalance)
            }
            #if os(iOS)
            Section {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
            } footer: {
                Text("A gentle tap on saves, errors, and deletes. Also respects your device's System Haptics setting.")
            }
            #endif
            Section {
                Toggle("Adjust Balance in Add sheet", isOn: $showAdjustInAddSheet)
            } footer: {
                Text("Adds an Adjust Balance type to the Add-transaction sheet. It's always available from an account's \u{22EF} menu.")
            }
            Section {
                Toggle("Floating add button", isOn: $fabEnabled)
                if fabEnabled {
                    Picker("Position", selection: $fabPositionRaw) {
                        ForEach(FabPosition.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Quick add button")
            } footer: {
                Text("The floating + for quickly adding a transaction on iPhone. The toolbar and \u{2318}N ways to add are always available.")
            }
        }
        .navigationTitle("Appearance & Language")
    }
}
