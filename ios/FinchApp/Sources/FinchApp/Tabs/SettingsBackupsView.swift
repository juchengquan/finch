import SwiftUI
import FinchCore
import UniformTypeIdentifiers

/// Settings › Backup & Sync › Backups — the merged on-device + iCloud Drive
/// backup history. Tap a snapshot to restore it: **replaces all current data**,
/// so it's gated (destructive confirm → Face-ID → auto-backup the current state
/// first, so the restore is reversible → loadPack + audit gate). On-device
/// snapshots can be shared off-device; iCloud ones are already in Files.
struct SettingsBackupsView: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @StateObject private var backups = AutoBackupManager.shared
    @StateObject private var icloud = ICloudSync.shared

    @AppStorage(AutoBackupManager.retentionKey) private var retention = AutoBackupManager.defaultRetention
    @AppStorage(AutoBackupManager.frequencyKey) private var frequencyRaw = BackupFrequency.daily.rawValue
    @State private var pickingFolder = false
    @State private var pendingRestore: BackupEntry?
    @State private var restoring: BackupEntry?     // in-flight (download + loadPack)
    @State private var errorMessage: String?
    @State private var auditMessage: String?

    private var entries: [BackupEntry] {
        BackupHistory.merge(local: backups.localBackups(), iCloud: icloud.remoteBackups)
    }

    var body: some View {
        List {
            // On this device — the always-on single latest snapshot: a quick,
            // offline restore point, refreshed after every change.
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
                Text("finch always keeps the latest backup on this device — a quick, offline restore point. Turn on a backup folder to keep a browsable history off-device.")
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
                    Stepper(value: $retention, in: 3...50) {
                        LabeledContent("Number of backups", value: "\(retention)")
                    }
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
                    Text("Tap a backup to restore it — this replaces all current data, and your current data is backed up first.")
                }
            }
        }
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
    }

    @ViewBuilder private func row(_ e: BackupEntry, isLatest: Bool) -> some View {
        Button { pendingRestore = e } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.relative(e.date)).foregroundStyle(.primary)
                    Text("\(Self.full(e.date)) · \(Self.size(e.size))")
                        .font(.caption).foregroundStyle(.secondary)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(restoring != nil)
        .contextMenu {
            // iCloud-only snapshots are already in Files › iCloud Drive › finch, so
            // in-app Share only needs to cover on-device packs.
            if e.onDevice {
                ShareLink(item: backups.url(forName: e.name)) { Label("Share", systemImage: "square.and.arrow.up") }
            }
        }
    }

    /// 📱 on-device · ☁︎ in iCloud (down-arrow = not yet downloaded).
    @ViewBuilder private func locationBadges(_ e: BackupEntry) -> some View {
        HStack(spacing: 4) {
            if e.onDevice { Image(systemName: "iphone").foregroundStyle(.secondary) }
            if e.inICloud { Image(systemName: e.downloaded ? "folder" : "icloud.and.arrow.down").foregroundStyle(.secondary) }
        }
        .font(.caption)
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
    private static func relative(_ d: Date) -> String {
        d.formatted(Date.RelativeFormatStyle(presentation: .named))
    }
    private static func full(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale))
    }
    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
