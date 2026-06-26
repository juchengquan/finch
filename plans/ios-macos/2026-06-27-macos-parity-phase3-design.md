# macOS parity — Phase 3: menu & window conventions

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** Three macOS-conventional additions — a Settings **Preferences window** (⌘,), a richer **menu bar** (File ▸ Export, Help), and **⌫-to-delete** keyboard nav on the primary lists. UI/scene/commands only; no engine change.
**Roadmap:** Phase 3 of `2026-06-27-macos-parity-roadmap-design.md`.

## 1. Settings → Preferences window (⌘,)

Today ⌘, runs `router.selectedTab = .settings` (an in-app tab); the Settings screen is a
`List` of `NavigationLink` drill-ins inside `MoreTabNavigationStack` (which only provides a
`NavigationStack` at regular width — unreliable in a small Settings window).

- **Extract** `SettingsTab`'s drill-in `List` into a reusable `struct SettingsRootList: View`
  (in `SettingsTab.swift`). `SettingsTab` becomes `MoreTabNavigationStack { SettingsRootList() }`.
- **Add a macOS `Settings` scene** in `FinchApp.swift` (after the `WindowGroup`):
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
  SwiftUI auto-binds **⌘,** + the "Settings…" app-menu item to this scene.
- **`FinchCommands.swift`:** remove the manual `CommandGroup(replacing: .appSettings)` ⌘, override
  (the Settings scene owns it now).
- **`MasterDetailShell.swift`:** drop `.settings` from the **macOS** sidebar `more` group
  (`#if os(macOS) [.activity] #else [.activity, .settings]`), so Settings isn't duplicated.
  iPad keeps the in-app Settings.

## 2. Richer menu bar (`FinchCommands.swift` + a coordinator)

- **File ▸ Export .finch… (⌘⇧E).** Add `@Published var exportRequested = false` to
  `DeepLinkRouter`. Add a command:
  ```swift
  CommandGroup(after: .newItem) {
      Button("Export .finch…") { router.exportRequested = true }
          .keyboardShortcut("e", modifiers: [.command, .shift])
  }
  ```
  A new `ExportCoordinator` view modifier (attached to `AdaptiveShell`) watches `exportRequested`
  and reuses the proven `ExportButton` flow — `store.buildPack()` → temp `.finch` → a `ShareLink`
  sheet (works on macOS), gated by `BiometricGate.confirmSensitive()` like `ExportButton`.
- **Help menu.** `CommandGroup(replacing: .help) { Button("Finch Command Palette") { router.showCommandPalette = true } }`
  — points to the discoverability hub (⌘K).

## 3. Keyboard list nav — ⌫ delete (`AccountsTab.swift`, `BudgetsTab.swift`)

The Accounts/Budgets lists already use `List(selection:)` (so ↑/↓ already works on macOS). Add:
```swift
        #if os(macOS)
        .onDeleteCommand { if let id = selection?.wrappedValue, let row = <rows>.first(where: { $0.id == id }) { delete(row) } }
        #endif
```
on each `List`, deleting the selected account/budget via the existing `delete(_:)`.
**Deferred** (finicky SwiftUI focus work): ↵-to-open, ⌫ on other lists.

## Out of scope
- ↵-to-open; keyboard nav beyond Accounts/Budgets; multi-window; a tabbed Preferences layout
  (a NavigationStack prefs window is the v1). Engine changes.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) — both `** BUILD SUCCEEDED **`.
- **macOS run (FinchMac):** ⌘, opens a **Preferences window** (the settings list, drill-ins work);
  the macOS sidebar no longer lists Settings. **File ▸ Export .finch…** (⌘⇧E) produces a share
  sheet. Selecting an account/budget and pressing **⌫** deletes it. Help menu shows the entry.
- **iOS:** unchanged (no Settings scene/menu bar; in-app Settings tab intact).

## Notes
- Collision: touches shell/command/tab files (actively edited) — re-check `gh pr list` + rebase
  before pushing; keep diffs additive. PR → `feat/frontend`.
- Risk areas (verify on macOS): the Settings scene's env injection + `SettingsRootList` rendering
  in a window; `onDeleteCommand` firing only when the list has focus.
