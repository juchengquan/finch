# Backup & Sync — merge Import & Export into Sync & Backup

**Date:** 2026-07-18
**Status:** Design approved in discussion (name "Backup & Sync" user-chosen); plan below in
`2026-07-18-backup-sync-merge-plan.md`.
**Scope:** One-file UI consolidation in `SettingsTab.swift`. No store/engine change, no web
change.

## Decisions

1. Settings root: the "Import & Export" and "Sync & Backup" rows collapse into one —
   `Label("Backup & Sync", systemImage: "arrow.triangle.2.circlepath")` — at the
   Import & Export position (second row, after Appearance & Language). Root shrinks
   8 → 7 rows; macOS Preferences inherits via shared `SettingsRootList`.
2. Combined page: `SettingsSyncBackupView` renamed `SettingsBackupSyncView`, nav title
   "Backup & Sync", sections in order **Sync** (master toggle + live status leads),
   **Backups**, **Import & Export** (the three buttons + footer moved verbatim from
   `SettingsImportExportView`, which is deleted).
3. All existing copy/footers carry over verbatim; only new string is "Backup & Sync"
   (→ zh-Hans batch). No deep-link/command-palette references exist to these views.

## Testing

No unit-testable logic. Both platform builds; sim pass: new row present, three sections
render, "Import & Export" and "Sync & Backup" rows gone.
