import Foundation

/// One snapshot in the merged backup history — a `.finch` pack identified by its
/// canonical filename, present on-device and/or in iCloud Drive. A device's own
/// backup carries the **same filename** in both stores, so the filename is the
/// dedup key. Pure value types + a pure `merge`/`date` so the history logic is
/// unit-testable without `FileManager` / `NSMetadataQuery`.
public struct BackupEntry: Identifiable, Equatable {
    public let name: String        // "finch-YYYYMMDD-HHmmss.finch"
    public let date: Date          // parsed from the filename stamp (device-clock-independent)
    public let size: Int64         // bytes (0 when unknown)
    public let onDevice: Bool      // present in the local Backups dir
    public let inICloud: Bool      // present in iCloud Drive
    public let downloaded: Bool    // bytes available locally without a download
    public var id: String { name }

    public init(name: String, date: Date, size: Int64, onDevice: Bool, inICloud: Bool, downloaded: Bool) {
        self.name = name; self.date = date; self.size = size
        self.onDevice = onDevice; self.inICloud = inICloud; self.downloaded = downloaded
    }
}

/// On-device backup descriptor (merge input).
public struct LocalBackup: Equatable {
    public let name: String; public let size: Int64
    public init(name: String, size: Int64) { self.name = name; self.size = size }
}

/// iCloud Drive backup descriptor (merge input); `downloaded` = bytes present locally.
public struct ICloudBackup: Equatable {
    public let name: String; public let size: Int64; public let downloaded: Bool
    public init(name: String, size: Int64, downloaded: Bool) { self.name = name; self.size = size; self.downloaded = downloaded }
}

/// Pure history builder: parse the canonical stamp and merge the two stores into
/// one deduped, newest-first list. Paired with `BackupPruner` (which decides which
/// filenames to drop) — both stores prune the same names in lockstep, so a device
/// only ever removes its own snapshots.
public enum BackupHistory {
    // Matches AutoBackupManager.stamp(): "yyyyMMdd-HHmmss", en_US_POSIX.
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Parse the timestamp from a backup filename — "finch-YYYYMMDD-HHmmss.finch"
    /// or "finch-YYYYMMDD-HHmmss-<deviceId>.finch" — or nil if malformed. The
    /// device-id suffix (added so two devices never collide on a filename in a
    /// shared folder) is ignored; the old suffix-less format still parses.
    public static func date(fromName name: String) -> Date? {
        guard name.hasPrefix("finch-"), name.hasSuffix(".finch") else { return nil }
        let middle = name.dropFirst("finch-".count).dropLast(".finch".count)
        let parts = middle.split(separator: "-")
        guard parts.count >= 2 else { return nil }   // date + time; a 3rd part is the device id
        return stampFormatter.date(from: "\(parts[0])-\(parts[1])")
    }

    /// The device id embedded in a backup filename ("finch-YYYYMMDD-HHmmss-<id>.finch"),
    /// or nil for the old suffix-less format. Used to prune only a device's OWN
    /// snapshots from a shared folder.
    public static func deviceId(fromName name: String) -> String? {
        guard name.hasPrefix("finch-"), name.hasSuffix(".finch") else { return nil }
        let parts = name.dropFirst("finch-".count).dropLast(".finch".count).split(separator: "-")
        return parts.count >= 3 ? String(parts[2]) : nil
    }

    /// Merge on-device + iCloud descriptors into one deduped (by filename),
    /// newest-first history. Names that don't parse to a date are dropped. Size
    /// prefers the local value; `downloaded` is true when on-device or the iCloud
    /// copy is already downloaded.
    public static func merge(local: [LocalBackup], iCloud: [ICloudBackup]) -> [BackupEntry] {
        let localByName = Dictionary(local.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let iCloudByName = Dictionary(iCloud.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [BackupEntry] = []
        for name in Set(localByName.keys).union(iCloudByName.keys) {
            guard let date = date(fromName: name) else { continue }
            let l = localByName[name], c = iCloudByName[name]
            out.append(BackupEntry(
                name: name, date: date,
                size: l?.size ?? c?.size ?? 0,
                onDevice: l != nil, inICloud: c != nil,
                downloaded: l != nil || (c?.downloaded ?? false)))
        }
        // Newest first; filename is a stable tiebreak (chronological by construction).
        return out.sorted { $0.date != $1.date ? $0.date > $1.date : $0.name > $1.name }
    }
}

/// Pure failure-episode logic for the designated-backup-folder mirror. The
/// debounced auto-backup fires constantly, so we alert **once** when the mirror
/// STARTS failing (an ok→fail transition), never on the subsequent failures of
/// the same episode; a persistent banner tracks `failing` meanwhile, and a
/// recovery (fail→ok) clears it so the next failure is a fresh episode that
/// alerts again. Local backups are unaffected — this is only about the mirror.
public enum MirrorAlert {
    public struct Decision: Equatable {
        public let failing: Bool        // drives the persistent "unavailable" banner
        public let shouldAlert: Bool    // raise the one-shot alert this round?
    }

    /// Given the prior failing state and whether THIS mirror attempt failed,
    /// return the new failing state + whether to raise a one-shot alert.
    public static func next(wasFailing: Bool, failed: Bool) -> Decision {
        Decision(failing: failed, shouldAlert: failed && !wasFailing)
    }
}

/// How often automatic backups may run (a minimum interval, not a guaranteed
/// wakeup — iOS can't back up while the app isn't running, so it's "at most once
/// per interval, next time you change something in-app").
public enum BackupFrequency: String, CaseIterable, Identifiable, Sendable {
    case hourly, daily, weekly, monthly
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    /// Minimum seconds between automatic backups.
    public var interval: TimeInterval {
        switch self {
        case .hourly:  return 3_600
        case .daily:   return 86_400
        case .weekly:  return 604_800
        case .monthly: return 2_592_000   // 30 days
        }
    }
}

/// Pure throttle decision for automatic backups. Manual "Back up now" and the
/// pre-restore safety backup bypass this (they always run).
public enum BackupSchedule {
    /// Whether an automatic backup is due: yes if none has ever run, or at least
    /// `frequency.interval` has elapsed since the last one.
    public static func shouldAutoBackup(lastBackupAt: Date?, frequency: BackupFrequency, now: Date) -> Bool {
        guard let last = lastBackupAt else { return true }
        return now.timeIntervalSince(last) >= frequency.interval
    }
}

/// Pure per-write targeting: which stores get this snapshot. The LOCAL latest is
/// on a fixed **daily** cadence (the pack is a pure archive — nothing reads it at
/// runtime — so per-change rewriting was wasted I/O); the folder archive follows
/// the user's frequency. The two throttles are independent, so an hourly folder
/// cadence still fires on days the local latest is already fresh. Forced writes
/// ("Back up now", the pre-restore safety copy) hit both.
public enum BackupDecision {
    public struct Targets: Equatable {
        public let local: Bool
        public let folder: Bool
        public init(local: Bool, folder: Bool) { self.local = local; self.folder = folder }
    }

    public static func compute(force: Bool, lastLocalAt: Date?, folderAvailable: Bool,
                               lastFolderAt: Date?, frequency: BackupFrequency, now: Date) -> Targets {
        Targets(
            local: force || BackupSchedule.shouldAutoBackup(lastBackupAt: lastLocalAt, frequency: .daily, now: now),
            folder: folderAvailable && (force || BackupSchedule.shouldAutoBackup(lastBackupAt: lastFolderAt, frequency: frequency, now: now)))
    }
}
