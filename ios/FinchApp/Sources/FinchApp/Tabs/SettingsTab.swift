import SwiftUI
import FinchCore

/// Settings home — a short menu of drill-in categories (Import/Export, Sync &
/// Backup, Power Tools, Notifications, Security, Advanced) plus an About footer.
/// Ledger switching, Manage ledgers, and display currency live in the Ledger tab
/// now, so they're not duplicated here.
struct SettingsTab: View {
    var body: some View {
        MoreTabNavigationStack {
            SettingsRootList()
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }
                    #endif
                }
                .ledgerPush()
        }
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

/// Settings › Import & Export — the `.finch` pack import/export buttons.
struct SettingsImportExportView: View {
    var body: some View {
        List {
            Section {
                ImportButton()
                ExportButton()
            } footer: {
                Text("Export your whole ledger set as a self-contained .finch file; import to replace your data (audited first).")
            }
        }
        .navigationTitle("Import & Export")
    }
}

/// Settings › Sync & Backup — iCloud (CloudKit) live sync + local/iCloud-Drive
/// backups (both about keeping your data safe across devices).
struct SettingsSyncBackupView: View {
    @EnvironmentObject private var store: FinchStore
    @StateObject private var backups = AutoBackupManager.shared
    @StateObject private var icloud = ICloudSync.shared
    @StateObject private var cloudSync = CloudKitSyncCoordinator.shared
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                Toggle("Sync across devices (iCloud)", isOn: Binding(
                    get: { cloudSync.enabled },
                    set: { on in Task { await cloudSync.setEnabled(on, store: store) } }))
                if cloudSync.isBootstrapping {
                    HStack { ProgressView(); Text("Setting up iCloud sync…").foregroundStyle(.secondary) }
                } else if cloudSync.isSyncing {
                    HStack { ProgressView(); Text("Syncing…").foregroundStyle(.secondary) }
                }
                if cloudSync.enabled {
                    LabeledContent("Status", value: cloudSync.status.accountAvailable
                                   ? "Subscribed to \(cloudSync.status.subscribedLedgers) ledgers"
                                   : "iCloud account required")
                    LabeledContent("Pending changes", value: "\(cloudSync.status.pendingChanges)")
                    LabeledContent("Last sync", value: cloudSync.status.lastSyncAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale)) ?? "—")
                    if let err = cloudSync.status.lastError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                    Button("Resync ledger") { Task { await cloudSync.resync(store: store) } }
                        .disabled(!cloudSync.status.accountAvailable)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Row-level live sync over iCloud (CloudKit). Scaffold — the network layer activates once the CloudKit container is provisioned; without an iCloud account it stays inactive. Your data is always exportable as a .finch file.")
            }

            Section {
                LabeledContent("Last backup", value: backups.lastBackupAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale)) ?? "—")
                Button("Back up now") { Task { await backups.flush() } }
                    .disabled(store.ledgers.isEmpty)
                if let err = backups.lastError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                LabeledContent("iCloud Drive", value: icloud.available ? "On" : "Unavailable")
                if icloud.newerRemotePack != nil {
                    Button("Import newer version from iCloud") {
                        if let data = icloud.dataForImport() {
                            Task {
                                do { try await store.loadPack(from: data); icloud.clearPendingImport() }
                                catch { importError = i18nMessage(error) }
                            }
                        }
                    }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("Automatic local .finch backups after edits (kept: last 14), mirrored to iCloud Drive when signed in. Newer versions from other devices are offered for import (never auto-replaced).")
            }
        }
        .navigationTitle("Sync & Backup")
        .errorAlert($importError, title: "Import failed")
    }
}

/// Settings › Power Tools — the ledger-admin editors.
struct SettingsPowerToolsView: View {
    var body: some View {
        List {
            NavigationLink("Rules") { RulesManagerView() }
            NavigationLink("Categories") { CategoryAdminView() }
            NavigationLink("Tags") { TagAdminView() }
            NavigationLink("Merchants") { CounterpartyAdminView() }
            NavigationLink("Exchange rates") { ExchangeRatesView() }
        }
        .navigationTitle("Power Tools")
    }
}

/// Settings › Notifications — per-kind toggles (+ a denied-permission nudge).
struct SettingsNotificationsView: View {
    @StateObject private var notifications = NotificationService.shared

    var body: some View {
        List {
            Section {
                if notifications.authorizationDenied {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Notifications are turned off", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Text("Enable them in iOS Settings to receive budget and scheduled alerts.")
                            .font(.caption).foregroundStyle(.secondary)
                        #if os(iOS)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url)
                        }
                        #endif
                    }
                }
                ForEach(NotificationKind.allCases, id: \.rawValue) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { NotificationPrefs.isOn(kind) },
                        set: { on in
                            NotificationPrefs.set(kind, on: on)
                            Task { await NotificationService.shared.refresh() }
                        }))
                }
            }
        }
        .navigationTitle("Notifications")
    }
}

/// Settings › Security — the biometric lock policy, timeout, and the
/// sensitive-actions (export / destructive) gate.
struct SettingsSecurityView: View {
    @EnvironmentObject private var gate: BiometricGate

    var body: some View {
        List {
            Section {
                Picker("App lock", selection: Binding(
                    get: { gate.settings.policy },
                    set: { gate.settings.policy = $0 })) {
                    ForEach(BiometricPolicy.allCases, id: \.rawValue) { Text($0.displayName).tag($0) }
                }
                if gate.settings.policy == .onBackground || gate.settings.policy == .onIdle {
                    Picker("Lock after", selection: Binding(
                        get: { gate.settings.timeoutSeconds },
                        set: { gate.settings.timeoutSeconds = $0 })) {
                        ForEach([60, 300, 900, 1800, 3600], id: \.self) { Text("\($0 / 60) min").tag($0) }
                    }
                }
                if gate.settings.policy != .off {
                    Toggle("Require Face ID for export & destructive actions", isOn: Binding(
                        get: { gate.settings.sensitiveActionsEnabled },
                        set: { gate.settings.sensitiveActionsEnabled = $0 }))
                }
            } footer: {
                Text("Uses Face ID / Touch ID, falling back to your device passcode. finch never stores a passcode of its own.")
            }
        }
        .navigationTitle("Security")
    }
}

/// Settings › Advanced — diagnostics (DB info, audit) and the iOS-only
/// "Force import" override.
struct SettingsAdvancedView: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @State private var importError: String?
    @State private var showForceImportConfirm = false

    var body: some View {
        List {
            Section("Database") {
                LabeledContent("Filename", value: store.dbInfo.filename)
                LabeledContent("Size", value: store.dbInfo.formattedSize)
                LabeledContent("Schema version", value: store.dbInfo.schemaVersion)
                LabeledContent("Last imported", value: store.dbInfo.lastImportedAtDisplay)
                ForEach(store.dbInfo.rowCountsOrdered, id: \.0) { name, count in
                    LabeledContent(name, value: "\(count)")
                }
            }

            Section("Audit") {
                if store.auditProblems.isEmpty {
                    Label("Clean", systemImage: "checkmark.seal")
                } else {
                    NavigationLink {
                        AuditDetailView(problems: store.auditProblems)
                    } label: {
                        Label("\(store.auditProblems.count) problems",
                              systemImage: "exclamationmark.triangle")
                    }
                }
            }

            Section {
                // "Force import" — a DELIBERATE iOS-ONLY DIVERGENCE (D7). The web
                // has NO audit-skip path; only the native app offers this override.
                // It re-projects WITHOUT gating on the audit (the rejected pack's
                // staged DB is swapped in).
                Button("Force import (skip audit — iOS only)", role: .destructive) {
                    showForceImportConfirm = true
                }
            }
        }
        .navigationTitle("Advanced")
        .errorAlert($importError, title: "Import failed")
        .alert("Force import?", isPresented: $showForceImportConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Replace data", role: .destructive) {
                Task {
                    guard await gate.confirmSensitive() else { return }
                    do { try store.forceImportCurrentPack() }
                    catch { importError = i18nMessage(error) }
                }
            }
        } message: {
            Text("This replaces your live database with the audit-rejected pack and cannot be undone.")
        }
    }
}

/// The audit-problem list (reached from Settings › Advanced › Audit when not
/// clean, or after a Force import surfaces the overridden problems).
struct AuditDetailView: View {
    let problems: [Audit.AuditProblem]
    var body: some View {
        List(problems, id: \.self) { problem in
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.code.rawValue).font(.headline)
                if let entryId = problem.entryId {
                    Text("entry: \(entryId)").font(.caption).foregroundStyle(.secondary)
                }
                Text(problem.detail).font(.callout)
            }
        }
        .navigationTitle("Audit problems")
    }
}
