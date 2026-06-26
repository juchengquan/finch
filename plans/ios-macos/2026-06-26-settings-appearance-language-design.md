# Settings: theme toggle + language picker

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** An "Appearance & Language" Settings page — a Theme toggle (System/Light/Dark, live) and a Language picker (System/English/简体中文, applied on relaunch). UI-only, no engine change.

## Problem

iOS has no in-app theme override (it always follows the system appearance — no
`preferredColorScheme`/`@AppStorage` anywhere) and no language picker, though the String
Catalog ships **en + zh-Hans** (325 strings). The web has both (parity inventory, Tier 3).

## Design

### 1. Preferences (new file `Tabs/SettingsAppearanceView.swift`)

```swift
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
```
Storage keys: `finch.appearance` (theme), `finch.language` (the picker's remembered choice).

### 2. Theme — applied live at the app root

In `FinchApp.swift` (the `App` struct), add:

```swift
    @AppStorage("finch.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
```
and apply it to the root `ZStack` in the `WindowGroup` (after its existing modifiers):

```swift
            .preferredColorScheme((AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme)
```
`@AppStorage` observes `UserDefaults`, so changing the theme in the picker re-renders the
root and flips the whole app instantly (no restart).

### 3. Language — `AppleLanguages` override (relaunch to apply)

The picker writes `finch.language` (its remembered value) and, on change, sets the
standard **`AppleLanguages`** override so iOS resolves *all* strings (SwiftUI `Text`
**and** imperative `String(localized:)`/`ErrorL10n`) in the chosen language on next
launch:
- **System** → `UserDefaults.standard.removeObject(forKey: "AppleLanguages")`
- **English / 简体中文** → `UserDefaults.standard.set([code], forKey: "AppleLanguages")`

`AppleLanguages` is read by the system at launch, so the change is shown with a
**"Relaunch finch to apply the new language"** note. (Chosen over `.environment(\.locale)`,
which would switch `Text` live but leave `String(localized:)` strings untranslated — an
inconsistent half-switch.)

### 4. `SettingsAppearanceView`

```swift
struct SettingsAppearanceView: View {
    @AppStorage("finch.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage("finch.language") private var languageRaw = AppLanguage.system.rawValue
    @State private var showRelaunchNote = false

    var body: some View {
        List {
            Section("Theme") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.segmented)
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
            } header: { Text("Language") } footer: {
                Text(showRelaunchNote ? "Relaunch finch to apply the new language."
                                      : "Switches the app's language. Takes effect after relaunch.")
                    .foregroundStyle(showRelaunchNote ? .orange : .secondary)
            }
        }
        .navigationTitle("Appearance & Language")
    }
}
```

### 5. Entry point

In `SettingsTab.swift`, add to the menu `Section` (first item):

```swift
                    NavigationLink { SettingsAppearanceView() } label: { Label("Appearance & Language", systemImage: "paintbrush") }
```

## Out of scope
- Adding new languages (the catalog's en + zh-Hans are the set); a separate
  number/date *formatting-region* picker (the app uses a fixed h24 locale + per-ledger
  display currency); any engine/parity change.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) — `preferredColorScheme` + `AppleLanguages` are cross-platform.
- **Manual (sim):** Theme → switch **Dark** → the whole app flips dark **live**; **System** follows the simulator appearance. Language → pick **简体中文** → the relaunch note appears and `AppleLanguages` is written; relaunch → UI strings render in Chinese; back to **System** clears it.

No engine test — pure App-layer preferences.

## Notes
- `@AppStorage` in the `App` struct drives `preferredColorScheme`; the same key in the
  picker keeps them in sync (live theme).
- PR targets `feat/frontend`.
