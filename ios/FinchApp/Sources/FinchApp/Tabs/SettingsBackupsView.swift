import SwiftUI
import FinchCore
import UniformTypeIdentifiers

/// Settings › Backup & Sync › Backups — the merged on-device + iCloud Drive
/// backup history. Swipe a snapshot right to restore it: **replaces all current
/// data**, so it's gated (destructive confirm → Face-ID → auto-backup the current
/// state first, so the restore is reversible → loadPack + audit gate). Swipe left
/// to delete it everywhere it's saved; long-press for the same actions + Share.
struct SettingsBackupsView: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @StateObject private var backups = AutoBackupManager.shared
    @StateObject private var icloud = ICloudSync.shared

    @AppStorage(AutoBackupManager.retentionKey) private var retention = AutoBackupManager.defaultRetention
    @AppStorage(AutoBackupManager.frequencyKey) private var frequencyRaw = BackupFrequency.daily.rawValue
    @State private var pickingFolder = false
    @State private var retentionExpanded = false   // collapsible count wheel (iOS)
    @State private var pendingRestore: BackupEntry?
    @State private var pendingDelete: BackupEntry?
    @State private var restoring: BackupEntry?     // in-flight (download + loadPack)
    @State private var errorMessage: String?
    @State private var auditMessage: String?

    private var entries: [BackupEntry] {
        BackupHistory.merge(local: backups.localBackups(), iCloud: icloud.remoteBackups)
    }

    var body: some View {
        List {
            // On this device — the always-on single latest snapshot: a quick,
            // offline restore point, refreshed at most once a day (forced writes
            // — "Back up now" and the pre-restore safety copy — always refresh it).
            Section {
                LabeledContent("Latest on this device",
                               value: backups.lastBackupAt.map(Self.full) ?? "None yet")
                Button("Back up now") { Task { await backups.flush() } }
                    .disabled(store.ledgers.isEmpty)
                if let err = backups.lastError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            } header: {
                Text("On this device")
            } footer: {
                Text("finch keeps its latest backup on this device, refreshed at most once a day — a quick, offline restore point. “Back up now” always writes a fresh one. Turn on a backup folder to keep a browsable history off-device.")
            }

            // Folder backup — opt-in browsable history in an iCloud Drive folder,
            // synced across devices. Count + frequency scope this folder only.
            Section {
                Toggle("Back up to a folder", isOn: Binding(
                    get: { icloud.designatedFolderName != nil },
                    set: { on in if on { pickingFolder = true } else { icloud.clearFolder() } }))
                .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result { icloud.setFolder(url) }
                }
                if icloud.mirrorFailing {
                    Label("Backup folder unavailable — re-select it. Your latest backup is still saved on this device.", systemImage: "exclamationmark.icloud")
                        .font(.caption).foregroundStyle(.orange)
                }
                if icloud.designatedFolderName != nil {
                    Button { pickingFolder = true } label: {
                        LabeledContent("Folder", value: icloud.designatedFolderName ?? "")
                    }
                    // Count: a collapsible wheel row (the inline date-picker pattern —
                    // ~180pt when open, so it stays collapsed until you're changing it).
                    // macOS has no wheel style; a menu picker is the native equivalent.
                    #if os(macOS)
                    Picker("Number of backups", selection: $retention) {
                        ForEach(AutoBackupManager.retentionRange, id: \.self) { Text("\($0)").tag($0) }
                    }
                    #else
                    // Concrete Colors, not .primary/.secondary: inside a Button the
                    // hierarchical styles resolve against the accent tint, turning
                    // the whole row blue.
                    Button { withAnimation { retentionExpanded.toggle() } } label: {
                        LabeledContent("Number of backups") {
                            Text("\(retention)")
                                .foregroundStyle(retentionExpanded ? Color.accentColor : Color.secondary)
                        }
                        .foregroundStyle(Color.primary)
                    }
                    if retentionExpanded {
                        Picker("Number of backups", selection: $retention) {
                            ForEach(AutoBackupManager.retentionRange, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                    }
                    #endif
                    Picker("Frequency", selection: $frequencyRaw) {
                        ForEach(BackupFrequency.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
            } header: {
                Text("Folder backup")
            } footer: {
                Text(icloud.designatedFolderName != nil
                     ? "Keeps this device's newest \(retention) backups in the folder. Frequency is a minimum interval — at most once per that period, the next time you make a change. “Back up now” always writes."
                     : "Pick an iCloud Drive folder to keep a browsable history off-device and share it across your devices.")
            }

            if entries.isEmpty {
                Section("History") {
                    Text("No backups yet.").foregroundStyle(.secondary).font(.callout)
                }
            } else {
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                        row(e, isLatest: idx == 0)
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("Swipe right on a backup to restore it, left to delete it. Restoring replaces all current data — your current data is backed up first.")
                }
            }
        }
        // Older builds allowed counts up to 50 — snap a stored value into the wheel's range.
        .onAppear { retention = min(max(retention, AutoBackupManager.retentionRange.lowerBound), AutoBackupManager.retentionRange.upperBound) }
        .onChange(of: retention) { _, _ in backups.pruneNow() }
        .navigationTitle("Backups")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .errorAlert($errorMessage, title: "Restore failed")
        .confirmationDialog(
            pendingRestore.map { "Restore the backup from \(Self.full($0.date))?" } ?? "",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible, presenting: pendingRestore) { e in
            Button("Restore", role: .destructive) { Task { await restore(e) } }
        } message: { _ in
            Text("This replaces all current data. Your current data is backed up first, so you can restore it back.")
        }
        .alert("Backup failed its integrity check", isPresented: Binding(
            get: { auditMessage != nil }, set: { if !$0 { auditMessage = nil } }),
            presenting: auditMessage) { _ in Button("OK", role: .cancel) {} } message: { Text($0) }
        .alert("Delete this backup?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { e in
            Button("Delete", role: .destructive) { delete(e) }
            Button("Cancel", role: .cancel) {}
        } message: { e in
            Text("The backup from \(Self.full(e.date)) will be removed everywhere it’s saved. This can’t be undone.")
        }
    }

    /// Remove a snapshot from every store it lives in — the on-device copy and/or
    /// the folder copy (including folder backups made by another device: manual
    /// delete is explicit intent; only AUTOMATIC pruning is device-scoped).
    private func delete(_ e: BackupEntry) {
        if e.onDevice { backups.deleteLocal(name: e.name) }
        if e.inICloud { icloud.delete(name: e.name) }
    }

    /// An inert row (no tap action): swipe right to restore, left to delete;
    /// long-press for the same actions + Share.
    @ViewBuilder private func row(_ e: BackupEntry, isLatest: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.full(e.date)).foregroundStyle(.primary)
                Text(Self.size(e.size)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isLatest {
                Text("Latest").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            locationBadges(e)
            if restoring?.id == e.id { ProgressView() }
        }
        .swipeActions(edge: .leading) {
            Button { pendingRestore = e } label: { Label("Restore", systemImage: "arrow.counterclockwise") }
                .tint(.blue)
                .disabled(restoring != nil)
        }
        .swipeActions(edge: .trailing) {
            Button { pendingDelete = e } label: { Label("Delete", systemImage: "trash") }
                .tint(.red)
                .disabled(restoring != nil)
        }
        .contextMenu {
            Button { pendingRestore = e } label: { Label("Restore", systemImage: "arrow.counterclockwise") }
                .disabled(restoring != nil)
            // iCloud-only snapshots are already in Files › iCloud Drive › finch, so
            // in-app Share only needs to cover on-device packs.
            if e.onDevice {
                ShareLink(item: backups.url(forName: e.name)) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            Button(role: .destructive) { pendingDelete = e } label: { Label("Delete", systemImage: "trash") }
                .disabled(restoring != nil)
        }
    }

    /// 📱 on-device · ☁︎ in iCloud (down-arrow = not yet downloaded).
    @ViewBuilder private func locationBadges(_ e: BackupEntry) -> some View {
        HStack(spacing: 4) {
            if e.onDevice { Image(systemName: "iphone").foregroundStyle(.secondary) }
            if e.inICloud { Image(systemName: e.downloaded ? "folder" : "icloud.and.arrow.down").foregroundStyle(.secondary) }
        }
        .font(.subheadline)
        .accessibilityLabel(e.onDevice && e.inICloud ? "On device and in backup folder" : e.onDevice ? "On device" : "In backup folder")
    }

    /// Restore: confirm (done) → Face-ID → auto-backup current → fetch bytes →
    /// loadPack. On a successful restore the pre-restore state is the new Latest.
    private func restore(_ e: BackupEntry) async {
        pendingRestore = nil
        guard await gate.confirmSensitive() else { return }
        restoring = e
        defer { restoring = nil }
        // Read the target's bytes BEFORE snapshotting the current state — flush()
        // refreshes the single local latest (pruning the previous on-device copy)
        // and re-prunes the folder to its retention, either of which could evict
        // this very snapshot. Read first, then flush.
        let data: Data?
        if e.onDevice {
            data = try? Data(contentsOf: backups.url(forName: e.name))
        } else {
            data = await icloud.download(name: e.name)
        }
        guard let data else { errorMessage = "Couldn't read that backup — it may still be downloading from iCloud."; return }
        await backups.flush()   // reversible: snapshot the current state (now safe — bytes are in hand)
        do {
            try await store.loadPack(from: data)
            Haptics.success()
        } catch PackError.auditFailed(let problems) {
            auditMessage = "\(problems.count) integrity problem(s). Use Settings › Advanced › Force import to override (iOS only)."
        } catch {
            Haptics.warning()
            errorMessage = i18nMessage(error)
        }
    }

    // MARK: formatting
    private static func full(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale))
    }
    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
