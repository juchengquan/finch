# macOS parity — Phase 3 (menu & window) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** macOS gets a Settings Preferences window (⌘,), a File ▸ Export command + Help menu, and ⌫-delete on the Accounts/Budgets lists.

**Architecture:** Extract `SettingsRootList`; add a macOS `Settings` scene; enrich `FinchCommands`; an `ExportCoordinator` modifier reusing `buildPack`→ShareLink; `.onDeleteCommand` on two lists. No engine change.

Spec: `plans/ios-macos/2026-06-27-macos-parity-phase3-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- Shared shell/command files are actively edited — **re-check `gh pr list` + rebase before pushing**.

---

### Task 1: Settings Preferences window

- [ ] **Step 1 — extract `SettingsRootList`** in `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`. Replace the current `SettingsTab` (the `MoreTabNavigationStack { List { … } .navigationTitle("Settings") }`) with:

```swift
struct SettingsTab: View {
    var body: some View {
        MoreTabNavigationStack { SettingsRootList() }
    }
}

/// The Settings drill-in list — reused by the iOS `SettingsTab` and the macOS
/// Preferences window (which supplies its own `NavigationStack`).
struct SettingsRootList: View {
    var body: some View {
        List {
            Section {
                NavigationLink { SettingsAppearanceView() } label: { Label("Appearance & Language", systemImage: "paintbrush") }
                NavigationLink { SettingsImportExportView() } label: { Label("Import & Export", systemImage: "square.and.arrow.up.on.square") }
                NavigationLink { SettingsSyncBackupView() } label: { Label("Sync & Backup", systemImage: "arrow.triangle.2.circlepath") }
                NavigationLink { SettingsPowerToolsView() } label: { Label("Power Tools", systemImage: "wrench.and.screwdriver") }
                NavigationLink { SettingsNotificationsView() } label: { Label("Notifications", systemImage: "bell") }
                NavigationLink { SettingsSecurityView() } label: { Label("Security", systemImage: "lock") }
                NavigationLink { SettingsAdvancedView() } label: { Label("Advanced", systemImage: "gearshape.2") }
            }
            Section("About") {
                LabeledContent("App version", value: FinchCore.version)
                LabeledContent("Pack format", value: FinchCore.packFormatVersion)
            }
        }
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 2 — add the macOS `Settings` scene** in `ios/FinchApp/Sources/FinchApp/FinchApp.swift`. After the `WindowGroup { … }.commands { … }` scene (the `.commands` block closes around line 98), and still inside `var body: some Scene`, add:

```swift
        #if os(macOS)
        Settings {
            NavigationStack { SettingsRootList() }
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(gate)
                .frame(minWidth: 520, minHeight: 420)
        }
        #endif
```
(`store`/`router`/`gate` are the same App-level objects the `WindowGroup` injects.)

- [ ] **Step 3 — drop the manual ⌘, override** in `ios/FinchApp/Sources/FinchApp/Shell/FinchCommands.swift`: delete the whole `CommandGroup(replacing: .appSettings) { … }` block (lines ~21–26). The `Settings` scene now owns ⌘,.

- [ ] **Step 4 — remove macOS sidebar Settings** in `ios/FinchApp/Sources/FinchApp/Shell/MasterDetailShell.swift`. Replace:

```swift
    private let more: [AppTab] = [.activity, .settings]
```
with:

```swift
    #if os(macOS)
    private let more: [AppTab] = [.activity]            // Settings is a Preferences window (⌘,)
    #else
    private let more: [AppTab] = [.activity, .settings]
    #endif
```

---

### Task 2: Menu bar — Export + Help

- [ ] **Step 1 — router flag** in `ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift`. After `@Published public var showAddTransaction = false` (line ~42), add:

```swift
    @Published public var exportRequested = false       // File ▸ Export .finch… (⌘⇧E)
```

- [ ] **Step 2 — `ExportCoordinator`** appended to `ios/FinchApp/Sources/FinchApp/ImportExport/ExportButton.swift` (reuses `ExportedFile`/`ImportError` already in that file):

```swift
/// Drives the menu-bar Export command: watches `router.exportRequested`, builds a
/// pack, and presents a ShareLink — the `ExportButton` flow, hoisted to the shell.
struct ExportCoordinator: ViewModifier {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @ObservedObject private var router = DeepLinkRouter.shared
    @State private var exportedFile: ExportedFile?
    @State private var exportError: ImportError?

    func body(content: Content) -> some View {
        content
            .onChange(of: router.exportRequested) { _, want in
                guard want else { return }
                router.exportRequested = false
                Task { await run() }
            }
            .sheet(item: $exportedFile) { file in
                ShareLink(item: file.url, preview: SharePreview("finch pack"))
            }
            .alert(item: $exportError) { err in
                Alert(title: Text("Export failed"), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
    }

    private func run() async {
        guard await gate.confirmSensitive() else { return }
        do {
            let data = try await store.buildPack()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("finch-\(UUID().uuidString).finch")
            try data.write(to: tmp)
            exportedFile = ExportedFile(url: tmp)
        } catch { exportError = ImportError(message: String(describing: error)) }
    }
}
```

- [ ] **Step 3 — attach the coordinator** in `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift`. Replace the `AdaptiveShell` body:

```swift
    var body: some View {
        if sizeClass == .compact {
            TabBarShell()
        } else {
            SplitViewShell()
        }
    }
```
with:

```swift
    var body: some View {
        Group {
            if sizeClass == .compact {
                TabBarShell()
            } else {
                SplitViewShell()
            }
        }
        .modifier(ExportCoordinator())
    }
```

- [ ] **Step 4 — commands** in `FinchCommands.swift`. Add an Export item in the File area and a Help menu (e.g. after the `.newItem` group):

```swift
        CommandGroup(after: .importExport) {
            Button("Export .finch…") { router.exportRequested = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Finch Command Palette") { router.showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
        }
```
(If `.importExport` isn't a valid `CommandGroupPlacement`, use `CommandGroup(after: .newItem)` instead.)

---

### Task 3: ⌫-delete on Accounts & Budgets

- [ ] **Step 1 — AccountsTab** (`Tabs/AccountsTab.swift`): on the `List(selection: selection)` in `contentList` (line ~146), add after the list's closing brace/modifiers:

```swift
            #if os(macOS)
            .onDeleteCommand { if let id = selection?.wrappedValue, let a = store.accounts.first(where: { $0.id == id }) { delete(a) } }
            #endif
```

- [ ] **Step 2 — BudgetsTab** (`Tabs/BudgetsTab.swift`): on the `List(selection: selection)` (line ~73), add:

```swift
            #if os(macOS)
            .onDeleteCommand { if let id = selection?.wrappedValue, let b = store.budgets.first(where: { $0.id == id }) { delete(b) } }
            #endif
```

---

### Task 4: Build + commit

- [ ] **Step 1: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
```
Expected: both `** BUILD SUCCEEDED **`. (If a `CommandGroupPlacement` like `.importExport` is unknown, switch that command to `.newItem` per Task 2 Step 4. If `Settings`/scene composition errors, ensure the `Settings` scene sits as a sibling of `WindowGroup` inside `body: some Scene`.)

- [ ] **Step 2: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift \
        ios/FinchApp/Sources/FinchApp/FinchApp.swift \
        ios/FinchApp/Sources/FinchApp/Shell/FinchCommands.swift \
        ios/FinchApp/Sources/FinchApp/Shell/MasterDetailShell.swift \
        ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift \
        ios/FinchApp/Sources/FinchApp/ImportExport/ExportButton.swift \
        ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift
git commit -m "feat(ios): macOS menu & window conventions — Preferences window, File▸Export, ⌫-delete"
```

---

### Task 5: Verify on macOS

**Files:** none.

- [ ] **Step 1: Build + run FinchMac:**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project ios/FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/mn-dd >/dev/null 2>&1
open /tmp/mn-dd/Build/Products/Debug/finch.app
```

- [ ] **Step 2: Verify** (mouse + keyboard):
  - **⌘,** opens a **Preferences window** showing the settings list (drill-ins navigate). The
    sidebar's "More" group no longer lists Settings. Screenshot `/tmp/mn-prefs.png`.
  - The **File menu** has **Export .finch…** (⌘⇧E); invoking it produces a share/save sheet.
    The **Help menu** has the "Finch Command Palette" entry.
  - Select an account (or budget) in the list and press **⌫** → it deletes (confirm via the
    list updating). Screenshot `/tmp/mn-main.png`. Clean up `/tmp/mn-dd` after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: SettingsRootList + Settings scene + ⌘,-override removal + sidebar (T1); router flag + ExportCoordinator + attach + commands (T2); onDeleteCommand ×2 (T3); build (T4); macOS run (T5). ✓
- Consistency: `exportRequested` set by command, consumed by `ExportCoordinator`; `SettingsRootList` used by both `SettingsTab` and the macOS scene; `delete(_:)` reused for ⌫; `store.accounts`/`store.budgets` resolve the selection id. ✓
- No engine change; iOS unaffected (no Settings scene, `more` keeps `.settings`, `onDeleteCommand` is `#if os(macOS)`). ✓
