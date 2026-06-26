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
        }
        .navigationTitle("Appearance & Language")
    }
}
