# Backup & Sync merge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline; single task). Checkbox steps.

**Goal:** One Settings page "Backup & Sync" holding Sync, Backups, and Import & Export sections; root rows collapse 8 → 7.

**Architecture:** Pure view consolidation in `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`: rename `SettingsSyncBackupView` → `SettingsBackupSyncView` + retitle, append the Import & Export section verbatim, delete `SettingsImportExportView`, rewire the root list.

## Global Constraints
- Worktree `/tmp/finch-bs`, branch `feat/ios-backup-sync`; commands from `/tmp/finch-bs/ios` with `DEVELOPER_DIR` set; both FinchApp + FinchMac builds must pass; no Co-Authored-By; PR → `feat/frontend`.

### Task 1 (single): consolidate views

- [ ] In `SettingsRootList` (SettingsTab.swift ~line 137): replace the two rows
  `NavigationLink { SettingsImportExportView() } label: { Label("Import & Export", systemImage: "square.and.arrow.up.on.square") }` and
  `NavigationLink { SettingsSyncBackupView() } label: { Label("Sync & Backup", systemImage: "arrow.triangle.2.circlepath") }`
  with the single row (at the Import & Export position):
  `NavigationLink { SettingsBackupSyncView() } label: { Label("Backup & Sync", systemImage: "arrow.triangle.2.circlepath") }`
- [ ] Delete `SettingsImportExportView` (~lines 53–66) entirely; keep `ImportButton`/`ExportButton`/`ExportCsvButton` (defined elsewhere) untouched.
- [ ] Rename `struct SettingsSyncBackupView` → `SettingsBackupSyncView`; `.navigationTitle("Sync & Backup")` → `"Backup & Sync"`; update its doc comment; append after the Backups section:

```swift
            Section {
                ImportButton()
                ExportButton()
                ExportCsvButton()
            } header: {
                Text("Import & Export")
            } footer: {
                Text("Export your whole ledger set as a self-contained .finch file; import to replace your data (audited first). The CSV export covers the active ledger's full transaction history.")
            }
```
- [ ] `grep -rn "SettingsImportExportView\|SettingsSyncBackupView" ios/` → no matches.
- [ ] Build both: FinchApp (iPhone sim ios-finch2) + FinchMac (`CODE_SIGNING_ALLOWED=NO`) — clean.
- [ ] Run FinchAppTests once (`-only-testing:FinchAppTests`) — no regressions.
- [ ] Commit: `feat(ios): merge Import & Export into Backup & Sync — one Settings data page`
- [ ] Sim: install/launch → root shows Backup & Sync (second row), old rows gone, three sections render.
