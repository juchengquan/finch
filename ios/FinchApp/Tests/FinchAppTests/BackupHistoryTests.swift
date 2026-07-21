import XCTest
@testable import FinchApp

/// The pure backup-history builder — filename→date parsing and the local+iCloud
/// merge/dedup. The FileManager / NSMetadataQuery gathering is the untested shell.
final class BackupHistoryTests: XCTestCase {
    private let newer = "finch-20260721-131200.finch"   // Jul 21 13:12:00
    private let mid   = "finch-20260720-090000.finch"   // Jul 20 09:00:00
    private let older = "finch-20260719-082200.finch"   // Jul 19 08:22:00

    func test_dateFromName_parsesValidAndRejectsGarbage() {
        XCTAssertNotNil(BackupHistory.date(fromName: newer))
        XCTAssertNil(BackupHistory.date(fromName: "garbage.finch"))
        XCTAssertNil(BackupHistory.date(fromName: "finch-notadate.finch"))
        XCTAssertNil(BackupHistory.date(fromName: "finch-20260721-131200.txt"))
        // Chronological by construction: a later stamp parses to a later date.
        XCTAssertGreaterThan(BackupHistory.date(fromName: newer)!, BackupHistory.date(fromName: older)!)
    }

    func test_localOnly_isOnDeviceAndDownloaded() {
        let m = BackupHistory.merge(local: [LocalBackup(name: newer, size: 100)], iCloud: [])
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].name, newer)
        XCTAssertEqual(m[0].size, 100)
        XCTAssertTrue(m[0].onDevice)
        XCTAssertFalse(m[0].inICloud)
        XCTAssertTrue(m[0].downloaded)   // on-device ⇒ bytes present
    }

    func test_iCloudOnly_notDownloaded() {
        let m = BackupHistory.merge(local: [], iCloud: [ICloudBackup(name: mid, size: 200, downloaded: false)])
        XCTAssertEqual(m.count, 1)
        XCTAssertFalse(m[0].onDevice)
        XCTAssertTrue(m[0].inICloud)
        XCTAssertFalse(m[0].downloaded)  // needs a download before restore
        XCTAssertEqual(m[0].size, 200)   // size known from metadata without downloading
    }

    func test_sameNameInBothStores_dedupesToOneEntryOnBoth() {
        let m = BackupHistory.merge(
            local: [LocalBackup(name: newer, size: 128)],
            iCloud: [ICloudBackup(name: newer, size: 128, downloaded: false)])
        XCTAssertEqual(m.count, 1)                 // deduped by filename
        XCTAssertTrue(m[0].onDevice)
        XCTAssertTrue(m[0].inICloud)
        XCTAssertTrue(m[0].downloaded)             // on-device wins
        XCTAssertEqual(m[0].size, 128)             // local size preferred
    }

    func test_merge_sortsNewestFirst_acrossStores() {
        let m = BackupHistory.merge(
            local: [LocalBackup(name: older, size: 1), LocalBackup(name: newer, size: 3)],
            iCloud: [ICloudBackup(name: mid, size: 2, downloaded: false)])
        XCTAssertEqual(m.map(\.name), [newer, mid, older])   // newest → oldest
    }

    func test_unparseableNamesAreDropped() {
        let m = BackupHistory.merge(
            local: [LocalBackup(name: "bogus.finch", size: 1), LocalBackup(name: newer, size: 2)],
            iCloud: [ICloudBackup(name: "also-bad", size: 1, downloaded: true)])
        XCTAssertEqual(m.map(\.name), [newer])
    }

    // MirrorAlert — alert once per failure episode; persistent banner via `failing`.
    func test_mirrorAlert_alertsOnceOnEntryThenBannerOnly() {
        // ok → fail: alert + start the banner.
        let a = MirrorAlert.next(wasFailing: false, failed: true)
        XCTAssertTrue(a.failing); XCTAssertTrue(a.shouldAlert)
        // fail → fail: banner stays, no new alert (no nagging).
        let b = MirrorAlert.next(wasFailing: true, failed: true)
        XCTAssertTrue(b.failing); XCTAssertFalse(b.shouldAlert)
    }

    func test_mirrorAlert_recoveryClearsAndReArmsForNextEpisode() {
        // fail → ok: banner clears, no alert.
        let r = MirrorAlert.next(wasFailing: true, failed: false)
        XCTAssertFalse(r.failing); XCTAssertFalse(r.shouldAlert)
        // ok → ok: nothing.
        let s = MirrorAlert.next(wasFailing: false, failed: false)
        XCTAssertFalse(s.failing); XCTAssertFalse(s.shouldAlert)
        // a fresh failure after recovery alerts again (new episode).
        let t = MirrorAlert.next(wasFailing: false, failed: true)
        XCTAssertTrue(t.failing); XCTAssertTrue(t.shouldAlert)
    }

    // Device-id suffix: filenames are `finch-<stamp>-<deviceId>.finch` so two
    // devices never collide in a shared folder. Parsing ignores the suffix, and
    // the old suffix-less format still parses.
    func test_dateFromName_ignoresDeviceIdSuffix_andBackCompat() {
        let old = "finch-20260721-131200.finch"
        let withId = "finch-20260721-131200-ab3f9c.finch"
        XCTAssertNotNil(BackupHistory.date(fromName: withId))
        XCTAssertEqual(BackupHistory.date(fromName: withId), BackupHistory.date(fromName: old))
    }

    func test_merge_sameSecondDifferentDevices_noFalseCollision() {
        // Same second, two devices → different filenames → two entries (not deduped).
        let a = "finch-20260721-131200-aaaa11.finch"
        let b = "finch-20260721-131200-bbbb22.finch"
        let m = BackupHistory.merge(local: [LocalBackup(name: a, size: 1)],
                                    iCloud: [ICloudBackup(name: b, size: 2, downloaded: false)])
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(Set(m.map(\.name)), [a, b])
    }

    // BackupSchedule — the auto-backup throttle (min interval per frequency).
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // a fixed instant

    func test_schedule_neverBackedUp_isAlwaysDue() {
        for f in BackupFrequency.allCases {
            XCTAssertTrue(BackupSchedule.shouldAutoBackup(lastBackupAt: nil, frequency: f, now: now))
        }
    }

    func test_schedule_dueOnlyAfterTheInterval() {
        // daily: not due at 2h, due at 25h.
        XCTAssertFalse(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-7_200), frequency: .daily, now: now))
        XCTAssertTrue(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-90_000), frequency: .daily, now: now))
        // hourly: not due at 30m, due at 61m.
        XCTAssertFalse(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-1_800), frequency: .hourly, now: now))
        XCTAssertTrue(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-3_660), frequency: .hourly, now: now))
        // weekly: not due at 3d, due at 8d.
        XCTAssertFalse(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-259_200), frequency: .weekly, now: now))
        XCTAssertTrue(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-691_200), frequency: .weekly, now: now))
        // monthly: not due at 20d, due at 31d.
        XCTAssertFalse(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-1_728_000), frequency: .monthly, now: now))
        XCTAssertTrue(BackupSchedule.shouldAutoBackup(lastBackupAt: now.addingTimeInterval(-2_678_400), frequency: .monthly, now: now))
    }

    func test_frequency_intervalsAreOrdered() {
        XCTAssertLessThan(BackupFrequency.hourly.interval, BackupFrequency.daily.interval)
        XCTAssertLessThan(BackupFrequency.daily.interval, BackupFrequency.weekly.interval)
        XCTAssertLessThan(BackupFrequency.weekly.interval, BackupFrequency.monthly.interval)
    }

    func test_deviceIdFromName() {
        XCTAssertEqual(BackupHistory.deviceId(fromName: "finch-20260721-131200-ab3f9c.finch"), "ab3f9c")
        XCTAssertNil(BackupHistory.deviceId(fromName: "finch-20260721-131200.finch"))   // old suffix-less
        XCTAssertNil(BackupHistory.deviceId(fromName: "garbage.finch"))
    }
}
