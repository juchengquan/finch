import SwiftUI
import FinchCore

/// Import/export, the active-ledger picker (switching re-projects), DB info,
/// the audit summary, and the iOS-only "Force import" override (D7).
struct SettingsTab: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @StateObject private var backups = AutoBackupManager.shared
    @StateObject private var icloud = ICloudSync.shared
    @StateObject private var notifications = NotificationService.shared
    @StateObject private var cloudSync = CloudKitSyncCoordinator.shared
    @State private var importError: String?
    @State private var showForceImportConfirm = false

    var body: some View {
        MoreTabNavigationStack {
            List {
                Section {
                    ImportButton()
                    ExportButton()
                }

                Section("Active Ledger") {
                    Picker("Active ledger", selection: $store.activeLedgerId) {
                        ForEach(store.ledgers) { ledger in
                            Text(ledger.name).tag(ledger.id)
                        }
                    }
                    Picker("Display currency", selection: Binding(
                        get: { store.displayCurrency },
                        set: { store.setDisplayCurrency($0) })) {
                        ForEach(store.availableDisplayCurrencies, id: \.self) { Text($0).tag($0) }
                    }
                    NavigationLink("Manage ledgers") { LedgerManagementView() }
                }

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
                        LabeledContent("Last sync", value: cloudSync.status.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                        if let err = cloudSync.status.lastError {
                            Text(err).foregroundStyle(.red).font(.caption)
                        }
                        Button("Resync ledger") { Task { await cloudSync.resync(store: store) } }
                            .disabled(!cloudSync.status.accountAvailable)
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Row-level live sync over iCloud (CloudKit). Scaffold — the network layer activates once the CloudKit container is provisioned; without an iCloud account it stays inactive. Your data is always exportable as a .finch file below.")
                }

                Section {
                    LabeledContent("Last backup", value: backups.lastBackupAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
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

                Section("Power tools") {
                    NavigationLink("Rules") { RulesManagerView() }
                    NavigationLink("Categories") { CategoryAdminView() }
                    NavigationLink("Tags") { TagAdminView() }
                    NavigationLink("Merchants") { CounterpartyAdminView() }
                    NavigationLink("Exchange rates") { ExchangeRatesView() }
                }

                Section("Database") {
                    LabeledContent("Filename", value: store.dbInfo.filename)
                    LabeledContent("Size", value: store.dbInfo.formattedSize)
                    LabeledContent("Schema version", value: store.dbInfo.schemaVersion)
                    LabeledContent("Last imported", value: store.dbInfo.lastImportedAtDisplay)
                    ForEach(store.dbInfo.rowCountsOrdered, id: \.0) { name, count in
                        LabeledContent(name, value: "\(count)")
                    }
                }

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
                } header: {
                    Text("Security")
                } footer: {
                    Text("Uses Face ID / Touch ID, falling back to your device passcode. finch never stores a passcode of its own.")
                }

                Section("Notifications") {
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
                    DisclosureGroup("Advanced") {
                        // "Force import" — a DELIBERATE iOS-ONLY DIVERGENCE (D7).
                        // The web has NO audit-skip path; only the native app
                        // offers this override. It re-projects WITHOUT gating on
                        // the audit (the rejected pack's staged DB is swapped in).
                        Button("Force import (skip audit — iOS only)", role: .destructive) {
                            showForceImportConfirm = true
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App version", value: FinchCore.version)
                    LabeledContent("Pack format", value: FinchCore.packFormatVersion)
                }
            }
            .navigationTitle("Settings")
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
}

/// The audit-problem list (reached from Settings › Audit when not clean, or
/// after a Force import surfaces the overridden problems).
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
