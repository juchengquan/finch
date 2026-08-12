import SwiftUI
import FinchCore
import UniformTypeIdentifiers

/// Compact drill-in target: presented as a top-level cover (no resume shadow).
enum SettingsDrill: String, Identifiable {
    case appearance, notifications, security
    case categories, tags
    case merchants, currencies
    case backupsSync, powerTools, about
    var id: String { rawValue }
}

/// Settings home — grouped drill-in sections: **General** (appearance,
/// notifications, security), **Ledger** (categories, tags — per-ledger),
/// **Shared** (merchants, currencies — global, one set across every ledger),
/// **Data** (backup & sync), an unlabeled **Experimental Labs** row (formerly
/// "Power Tools"; holds Rules + the CloudKit sync scaffold), plus an **About**
/// drill-in (version info + the former Advanced diagnostics).
/// Ledger switching, Manage ledgers, and display currency live in the Ledger
/// screen (the top-left corner control) now, so they're not duplicated here.
struct SettingsTab: View {
    #if os(iOS)
    @State private var drill: SettingsDrill?
    #endif
    /// False when a UIKit `UINavigationController` owns the stack (Phase 2 tabs).
    var ownsNavigationStack: Bool = true
    /// Asks the UIKit shell to push a converted screen; false when it is not
    /// converted (or on Mac/iPad), and the cover below handles it as before.
    @Environment(\.nativeRoute) private var nativeRoute

    var body: some View {
        MaybeNavigationStack(enabled: ownsNavigationStack) {
            settingsRoot
                .toolbar { toolbarContent }
                // Compact iOS: rows set `drill`, presented as a right-slide cover
                // (no resume shadow) — state-driven, so router / deep-link entry
                // opens the drill, not just a row tap.
                #if os(iOS)
                .rightSlideDrill(item: $drill) { settingsDrillCover($0) }
                #endif
        }
    }

    #if os(iOS)
    /// Settings drills that a converted view controller can handle. Everything else
    /// returns nil and keeps its SwiftUI cover.
    private static func route(for target: SettingsDrill) -> NativeRoute? {
        switch target {
        case .categories: return .categories
        case .tags: return .tags
        case .merchants: return .merchants
        case .currencies: return .currencies
        case .powerTools: return .powerTools
        case .appearance: return .appearance
        case .notifications: return .notifications
        case .security: return .security
        case .backupsSync: return .backupsSync
        case .about: return .about
        default: return nil
        }
    }

    /// The compact drill-in cover's content (top-level → no resume shadow).
    @ViewBuilder private func settingsDrillCover(_ target: SettingsDrill) -> some View {
        NavigationStack {
            drillContent(target)
                .rsdBackToolbar { drill = nil }
        }
    }
    #endif

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }
        #endif
        ToolbarItem(placement: .primaryAction) { PrivacyToggleButton() }
    }

    // macOS: `SettingsRootList` uses NavigationLink (onDrill == nil); compact iOS
    // routes taps through `drill` instead.
    @ViewBuilder private var settingsRoot: some View {
        #if os(iOS)
        SettingsRootList(onDrill: { target in
            if let route = Self.route(for: target), nativeRoute(route) { return }
            drill = target
        })
        #else
        SettingsRootList()
        #endif
    }

    #if os(iOS)
    @ViewBuilder private func drillContent(_ target: SettingsDrill) -> some View {
        switch target {
        case .appearance:  SettingsAppearanceView()
        case .notifications: SettingsNotificationsView()
        case .security:    SettingsSecurityView()
        case .categories:  CategoriesView()
        case .tags:        TagsView()
        case .merchants:   MerchantsView()
        case .currencies:  CurrenciesView()
        case .backupsSync: SettingsBackupSyncView()
        case .powerTools:  SettingsPowerToolsView()
        case .about:       SettingsAboutView()
        }
    }
    #endif
}

/// The Settings drill-in list — reused by the iOS `SettingsTab` and the macOS
/// Preferences window (which supplies its own `NavigationStack`).
struct SettingsRootList: View {
    /// Compact iOS: row taps call this closure instead of pushing via NavigationLink.
    /// Nil on macOS (NavigationLinks work directly).
    var onDrill: ((SettingsDrill) -> Void)? = nil

    var body: some View {
        List {
            Section("General") {
                drillRow(.appearance)  { SettingsAppearanceView() }  label: { Label("Appearance & Language", systemImage: "paintbrush") }
                drillRow(.notifications) { SettingsNotificationsView() } label: { Label("Notifications", systemImage: "bell") }
                drillRow(.security)    { SettingsSecurityView() }    label: { Label("Security", systemImage: "lock") }
            }
            Section("Ledger") {
                drillRow(.categories)  { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }
                drillRow(.tags)        { TagsView() }       label: { Label("Tags", systemImage: "tag") }
            }
            Section("Shared") {
                drillRow(.merchants)   { MerchantsView() }  label: { Label("Merchants", systemImage: "storefront") }
                drillRow(.currencies)  { CurrenciesView() } label: { Label("Currencies", systemImage: "dollarsign.circle") }
            }
            Section("Data") {
                drillRow(.backupsSync) { SettingsBackupSyncView() } label: { Label("Backup & Sync", systemImage: "arrow.triangle.2.circlepath") }
            }
            Section {
                drillRow(.powerTools)  { SettingsPowerToolsView() } label: { Label("Experimental Labs", systemImage: "flask") }
            }
            Section {
                drillRow(.about)       { SettingsAboutView() }    label: { Label("About", systemImage: "info.circle") }
            }
        }
        .navigationTitle("Settings")
    }

    /// A row that uses the compact drill closure (Button) on iOS, or a standard
    /// NavigationLink on macOS (where onDrill is nil).
    @ViewBuilder private func drillRow<Destination: View, RowLabel: View>(
        _ target: SettingsDrill,
        @ViewBuilder dest: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> RowLabel
    ) -> some View {
        if let onDrill {
            // .plain so the row reads as a normal (black) settings row, not a blue
            // accent-tinted button — matches the Accounts/Budgets row convention.
            Button { onDrill(target) } label: {
                label().frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: dest, label: label)
        }
    }
}

/// Settings › Backup & Sync — everything about keeping your data safe and
/// portable: local/iCloud-Drive backups and the `.finch` pack / CSV
/// import-export buttons (merged from the former Import & Export page).
/// CloudKit live sync moved to Experimental Labs — it's inert scaffold
/// (unprovisioned container) and under reconsideration, so it shouldn't sit
/// beside the always-working backups.
struct SettingsBackupSyncView: View {
    @EnvironmentObject private var store: FinchStore
    @StateObject private var backups = AutoBackupManager.shared
    @StateObject private var icloud = ICloudSync.shared

    var body: some View {
        List {
            Section {
                LabeledContent("Last backup", value: backups.lastBackupAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale)) ?? "—")
                NavigationLink {
                    SettingsBackupsView()
                } label: {
                    LabeledContent("Backups", value: "\(BackupHistory.merge(local: backups.localBackups(), iCloud: icloud.remoteBackups).count)")
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("finch always keeps your latest backup on this device. Open Backups to add a folder history (count, frequency), browse backups, and restore an earlier version.")
            }

            Section {
                ImportButton()
                ExportButton()
                ExportCsvButton()
            } header: {
                Text("Import & Export")
            } footer: {
                Text("Export your whole ledger set as a self-contained .finch file; import to replace your data (audited first). The CSV export covers the active ledger's full transaction history.")
            }
        }
        .navigationTitle("Backup & Sync")
    }
}

/// Settings › Experimental Labs (formerly "Power Tools") — power-user / beta
/// features: Rules, plus the CloudKit sync scaffold (moved out of Backup &
/// Sync while it's inert/under reconsideration).
struct SettingsPowerToolsView: View {
    @EnvironmentObject private var store: FinchStore
    @StateObject private var cloudSync = CloudKitSyncCoordinator.shared

    var body: some View {
        List {
            Section {
                NavigationLink("Rules") { RulesManagerView() }
            }

            Section {
                Toggle("Sync across devices (iCloud)", isOn: Binding(
                    get: { cloudSync.enabled },
                    set: { on in Task { await cloudSync.setEnabled(on, store: store) } })).switchOnlyToggles()
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
        }
        .navigationTitle("Experimental Labs")
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
                        })).switchOnlyToggles()
                }
            }
            // Mirrors the timing section on `NotificationsSettingsVC`. Both screens must
            // carry it: macOS renders this one, and `NavigationUITests` runs its suite
            // once per implementation.
            Section {
                hourPicker("Quiet from", hour: Binding(
                    get: { NotificationPrefs.quietHours.startHour },
                    set: { NotificationPrefs.quietHours = QuietHours(startHour: $0,
                                                                    endHour: NotificationPrefs.quietHours.endHour) }))
                hourPicker("Quiet until", hour: Binding(
                    get: { NotificationPrefs.quietHours.endHour },
                    set: { NotificationPrefs.quietHours = QuietHours(startHour: NotificationPrefs.quietHours.startHour,
                                                                    endHour: $0) }))
                hourPicker("Delivery time", hour: Binding(
                    get: { NotificationPrefs.deliveryHour },
                    set: { NotificationPrefs.deliveryHour = $0 }))
            } footer: {
                Text("Alerts raised during quiet hours arrive when it ends, rather than waking you.")
            }
        }
        .navigationTitle("Notifications")
    }

    /// The 24 hours, labelled through the user's own locale so a 12-hour region reads
    /// "10 PM" rather than a bare 22, which looks like a duration.
    private func hourPicker(_ title: LocalizedStringKey, hour: Binding<Int>) -> some View {
        Picker(title, selection: hour) {
            ForEach(0..<24, id: \.self) { h in
                Text(NotificationsSettingsHour.label(h)).tag(h)
            }
        }
        .onChange(of: hour.wrappedValue) { _, _ in
            // The preference alone changes nothing already scheduled.
            Task { await NotificationService.shared.refresh() }
        }
    }
}

/// One hour-label rule for both settings screens — the UIKit one renders the same
/// strings, and two formatters is how they drift apart.
enum NotificationsSettingsHour {
    static func label(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        guard let d = Calendar.current.date(from: c) else { return "\(hour)" }
        return d.formatted(.dateTime.hour().minute())
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
                        set: { gate.settings.sensitiveActionsEnabled = $0 })).switchOnlyToggles()
                }
            } footer: {
                Text("Uses Face ID / Touch ID, falling back to your device passcode. finch never stores a passcode of its own.")
            }
        }
        .navigationTitle("Security")
    }
}

/// Settings › About (formerly "Advanced") — version info, plus diagnostics
/// (DB info, audit) and the iOS-only "Force import" override.
struct SettingsAboutView: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @State private var importError: String?
    @State private var showForceImportConfirm = false

    var body: some View {
        List {
            Section {
                LabeledContent("App version", value: FinchCore.version)
                LabeledContent("Pack format", value: FinchCore.packFormatVersion)
                // Which commit this build came from — Debug builds only, and only
                // when the build phase actually stamped it. `Text(verbatim:)` on
                // both sides keeps this DEBUG-only developer string out of the
                // string catalog; this file IS compiled into the iOS target, so a
                // LocalizedStringKey here would reach extraction. See `BuildInfo`.
                #if DEBUG
                if let hash = BuildInfo.gitHash {
                    LabeledContent { Text(verbatim: hash) } label: { Text(verbatim: "Hash") }
                }
                #endif
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
        .navigationTitle("About")
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

/// The audit-problem list (reached from Settings › About › Audit when not
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
