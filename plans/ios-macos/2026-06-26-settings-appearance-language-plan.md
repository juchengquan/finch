# Settings appearance + language — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An "Appearance & Language" Settings page — a live Theme toggle and a Language picker (applied on relaunch).

**Architecture:** New `SettingsAppearanceView` + two preference enums; `FinchApp` applies `preferredColorScheme` from `@AppStorage` at the root; the language picker sets the `AppleLanguages` override. UI-only, no engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-26-settings-appearance-language-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds (a new file is added).
- Builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Appearance view + enums + root theme + Settings link

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsAppearanceView.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/FinchApp.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`

- [ ] **Step 1: Create `SettingsAppearanceView.swift`** (enums + view)

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
```

- [ ] **Step 2: Apply the theme at the app root**

In `FinchApp.swift`, add the stored preference to the `App` struct (near the other properties):

```swift
    @AppStorage("finch.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
```
Apply it to the root `ZStack` — insert immediately **before** the existing
`.onReceive(idleTimer) { _ in gate.tick() }` modifier:

```swift
            .preferredColorScheme((AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme)
```

- [ ] **Step 3: Add the Settings menu link**

In `SettingsTab.swift`, in the first menu `Section`, **before**:

```swift
                    NavigationLink { SettingsImportExportView() } label: { Label("Import & Export", systemImage: "square.and.arrow.up.on.square") }
```
add:

```swift
                    NavigationLink { SettingsAppearanceView() } label: { Label("Appearance & Language", systemImage: "paintbrush") }
```

- [ ] **Step 4: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/SettingsAppearanceView.swift \
        ios/FinchApp/Sources/FinchApp/FinchApp.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift
git commit -m "feat(ios): Settings — theme toggle + language picker"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install "$SIM" "$APP"; xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl launch "$SIM" com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Settings → **Appearance & Language**. Theme → **Dark** → the whole app flips to dark **immediately**; **Light** → light; **System** → follows the sim. Screenshot a dark + light state to `/tmp/appearance.png`.
  - Language → **简体中文** → the **relaunch note** appears; confirm the override is written:
    `xcrun simctl spawn "$SIM" defaults read com.juchengquan.finch AppleLanguages` → shows `zh-Hans`.
  - (Optional) relaunch → UI strings render in Chinese; set back to **System** → note clears + the key is removed.
  - The Settings gear/nav is AX-flaky; if the page can't be reached under automation, drive theme via the same `@AppStorage` (`defaults write com.juchengquan.finch finch.appearance dark` then relaunch) to confirm the root applies it.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: enums + view (T1 S1), root theme application (T1 S2), Settings link (T1 S3), cross-platform build (T1 S4), manual theme + language (T2). ✓
- Type consistency: `AppearancePreference.colorScheme: ColorScheme?`, `@AppStorage("finch.appearance"/"finch.language")`, `AppleLanguages` key consistent across FinchApp + the view. ✓
- No engine change; theme live via shared `@AppStorage`, language via `AppleLanguages` (relaunch). ✓
