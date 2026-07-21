import SwiftUI
import FinchCore

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

    @State private var pendingRestore: BackupEntry?
    @State private var restoring: BackupEntry?     // in-flight (download + loadPack)
    @State private var errorMessage: String?
    @State private var auditMessage: String?

    private var entries: [BackupEntry] {
        BackupHistory.merge(local: backups.localBackups(), iCloud: icloud.remoteBackups)
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No backups yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Backups are taken automatically after you make changes.")
                }
            } else {
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                        row(e, isLatest: idx == 0)
                    }
                } footer: {
                    Text("Tap a backup to restore it — this replaces all current data, and your current data is backed up first. Backups live on this device and in iCloud Drive (Files › iCloud Drive › finch).")
                }
            }
        }
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
            if e.inICloud { Image(systemName: e.downloaded ? "icloud" : "icloud.and.arrow.down").foregroundStyle(.secondary) }
        }
        .font(.caption)
        .accessibilityLabel(e.onDevice && e.inICloud ? "On device and iCloud" : e.onDevice ? "On device" : "iCloud")
    }

    /// Restore: confirm (done) → Face-ID → auto-backup current → fetch bytes →
    /// loadPack. On a successful restore the pre-restore state is the new Latest.
    private func restore(_ e: BackupEntry) async {
        pendingRestore = nil
        guard await gate.confirmSensitive() else { return }
        restoring = e
        defer { restoring = nil }
        await backups.flush()   // reversible: snapshot the current state first
        let data: Data?
        if e.onDevice {
            data = try? Data(contentsOf: backups.url(forName: e.name))
        } else {
            data = await icloud.download(name: e.name)
        }
        guard let data else { errorMessage = "Couldn't read that backup — it may still be downloading from iCloud."; return }
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
