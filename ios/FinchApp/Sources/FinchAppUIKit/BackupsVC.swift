#if os(iOS)
import UIKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import FinchCore

/// Phase 2, screen 21: `SettingsBackupsView` converted to UIKit.
///
/// The merged on-device + folder backup history. This was the LAST hosted SwiftUI
/// scroll view sitting in a pushed page — reproducer B — so with it converted no
/// pushed page in the app hosts one.
///
/// THE RESTORE PATH IS THE DANGEROUS PART and its ORDER is load-bearing, so it is
/// reproduced step for step from the SwiftUI original:
///
///   confirm → biometric gate → READ THE TARGET'S BYTES → flush() → loadPack
///
/// The bytes must be read BEFORE the safety flush, because `flush()` refreshes the
/// single on-device latest (pruning the previous copy) and re-prunes the folder to
/// its retention — either of which can evict the very snapshot being restored.
/// Reading first makes the restore safe against its own safety net. Do not reorder
/// these for tidiness.
final class BackupsVC: UIViewController {

    private let store = FinchStore.shared
    private let gate = BiometricGate.shared
    private let backups = AutoBackupManager.shared
    private let icloud = ICloudSync.shared
    private var cancellables = Set<AnyCancellable>()

    /// The snapshot currently being restored, if any — drives the row spinner and
    /// disables every destructive action while in flight.
    private var restoring: BackupEntry?

    private enum SectionID: Hashable { case device, folder, history }

    private static let latestID = "__latest__"
    private static let backUpNowID = "__back_up_now__"
    private static let backupErrorID = "__backup_error__"
    private static let folderToggleID = "__folder_toggle__"
    private static let mirrorFailingID = "__mirror_failing__"
    private static let folderNameID = "__folder_name__"
    private static let retentionID = "__retention__"
    private static let retentionWheelID = "__retention_wheel__"
    private static let frequencyID = "__frequency__"
    private static let emptyHistoryID = "__empty_history__"
    private static let entryPrefix = "__entry__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []
    private var entryByID: [String: BackupEntry] = [:]
    private var latestEntryID: String?
    /// The count wheel is collapsed until you are actually changing it — open it is
    /// ~180pt, which would dwarf the section.
    private var retentionExpanded = false

    private var retention: Int {
        UserDefaults.standard.object(forKey: AutoBackupManager.retentionKey) as? Int
            ?? AutoBackupManager.defaultRetention
    }
    private var frequencyRaw: String {
        UserDefaults.standard.string(forKey: AutoBackupManager.frequencyKey) ?? BackupFrequency.daily.rawValue
    }
    private var entries: [BackupEntry] {
        BackupHistory.merge(local: backups.localBackups(), iCloud: icloud.remoteBackups)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Backups")
        navigationItem.largeTitleDisplayMode = .never
        // Older builds allowed counts up to 50 — snap a stored value into range, as
        // the SwiftUI screen did on appear.
        let clamped = min(max(retention, AutoBackupManager.retentionRange.lowerBound),
                          AutoBackupManager.retentionRange.upperBound)
        if clamped != retention { UserDefaults.standard.set(clamped, forKey: AutoBackupManager.retentionKey) }

        configureCollectionView()
        configureDataSource()
        applySnapshot()

        Publishers.Merge(backups.objectWillChange, icloud.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .supplementary
            config.footerMode = .supplementary
            config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.restoreSwipe(at: ip)
            }
            config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.deleteSwipe(at: ip)
            }
            _ = index
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self else { return }
            // Clear accessories EXCEPT an already-installed switch: removing it from
            // the hierarchy is what destroyed the glass and swallowed taps. See
            // ToggleAccessory.
            if !ToggleAccessory.isInstalled(on: cell) { cell.accessories = [] }
            var cfg = cell.defaultContentConfiguration()

            switch id {
            case Self.latestID:
                self.configureValueRow(cell, String(localized: "Latest on this device"),
                                       self.backups.lastBackupAt.map(Self.full)
                                        ?? String(localized: "None yet"))

            case Self.backUpNowID:
                cfg.text = String(localized: "Back up now")
                cfg.textProperties.color = self.store.ledgers.isEmpty ? .tertiaryLabel : .tintColor
                cell.contentConfiguration = cfg

            case Self.backupErrorID:
                cfg.text = self.backups.lastError
                cfg.textProperties.color = .systemRed
                cfg.textProperties.font = .preferredFont(forTextStyle: .caption1)
                cell.contentConfiguration = cfg

            case Self.folderToggleID:
                cfg.text = String(localized: "Back up to a folder")
                cell.contentConfiguration = cfg
                ToggleAccessory.install(on: cell,
                                        isOn: self.icloud.designatedFolderName != nil) { [weak self] on in
                    guard let self else { return }
                    if on { self.pickFolder() } else { self.icloud.clearFolder() }
                }

            case Self.mirrorFailingID:
                cfg.text = String(localized: "Backup folder unavailable — re-select it. Your latest backup is still saved on this device.")
                cfg.textProperties.color = .systemOrange
                cfg.textProperties.font = .preferredFont(forTextStyle: .caption1)
                cfg.image = UIImage(systemName: "exclamationmark.icloud")
                cell.contentConfiguration = cfg

            case Self.folderNameID:
                self.configureValueRow(cell, String(localized: "Folder"),
                                       self.icloud.designatedFolderName ?? "")
                cell.accessories.append(.disclosureIndicator())

            case Self.retentionID:
                cfg.text = String(localized: "Number of backups")
                cell.contentConfiguration = cfg
                let value = UILabel()
                // Through the catalog: the SwiftUI screen's `Text("\(retention)")`
                // already contributes the key "%lld", so this reuses it.
                value.text = String(localized: "\(self.retention)")
                value.font = .preferredFont(forTextStyle: .body)
                // Tinted while the wheel is open, as in SwiftUI.
                value.textColor = self.retentionExpanded ? .tintColor : .secondaryLabel
                cell.accessories = [.customView(configuration: .init(customView: value,
                                                                     placement: .trailing()))]

            case Self.retentionWheelID:
                cell.contentConfiguration = UIHostingConfiguration {
                    Picker("", selection: Binding(
                        get: { self.retention },
                        set: {
                            UserDefaults.standard.set($0, forKey: AutoBackupManager.retentionKey)
                            self.backups.pruneNow()      // the SwiftUI onChange
                            self.applySnapshot()
                        })) {
                        ForEach(AutoBackupManager.retentionRange, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }

            case Self.frequencyID:
                let current = BackupFrequency(rawValue: self.frequencyRaw) ?? .daily
                cfg.text = String(localized: "Frequency")
                cell.contentConfiguration = cfg
                cell.accessories = [self.menuAccessory(
                    value: current.title,
                    options: BackupFrequency.allCases.map { ($0.title, $0.rawValue) },
                    onPick: { raw in
                        UserDefaults.standard.set(raw, forKey: AutoBackupManager.frequencyKey)
                        self.applySnapshot()
                    })]

            case Self.emptyHistoryID:
                cfg.text = String(localized: "No backups yet.")
                cfg.textProperties.color = .secondaryLabel
                cfg.textProperties.font = .preferredFont(forTextStyle: .callout)
                cell.contentConfiguration = cfg

            default:
                guard let entry = self.entryByID[id] else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    BackupRowVisual(date: Self.full(entry.date),
                                    size: Self.size(entry.size),
                                    isLatest: id == self.latestEntryID,
                                    onDevice: entry.onDevice,
                                    inICloud: entry.inICloud,
                                    downloaded: entry.downloaded,
                                    restoring: self.restoring?.id == entry.id)
                }
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            switch self.sectionIDs[indexPath.section] {
            case .device: cfg.text = String(localized: "On this device")
            case .folder: cfg.text = String(localized: "Folder backup")
            case .history: cfg.text = String(localized: "History")
            }
            view.contentConfiguration = cfg
        }

        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            switch self.sectionIDs[indexPath.section] {
            case .device:
                cfg.text = String(localized: "finch keeps its latest backup on this device, refreshed at most once a day — a quick, offline restore point. “Back up now” always writes a fresh one. Turn on a backup folder to keep a browsable history off-device.")
            case .folder:
                cfg.text = self.icloud.designatedFolderName != nil
                    ? String(localized: "Keeps this device's newest \(self.retention) backups in the folder. Frequency is a minimum interval — at most once per that period, the next time you make a change. “Back up now” always writes.")
                    : String(localized: "Pick an iCloud Drive folder to keep a browsable history off-device and share it across your devices.")
            case .history:
                cfg.text = self.entryByID.isEmpty ? nil
                    : String(localized: "Swipe right on a backup to restore it, left to delete it. Restoring replaces all current data — your current data is backed up first.")
            }
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, kind, indexPath in
            kind == UICollectionView.elementKindSectionFooter
                ? cv.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
                : cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    private func configureValueRow(_ cell: UICollectionViewListCell, _ label: String, _ value: String) {
        var cfg = cell.defaultContentConfiguration()
        cfg.text = label
        cell.contentConfiguration = cfg
        let trailing = UILabel()
        trailing.text = value
        trailing.font = .preferredFont(forTextStyle: .body)
        trailing.textColor = .secondaryLabel
        cell.accessories = [.customView(configuration: .init(customView: trailing, placement: .trailing()))]
    }

    private func menuAccessory(value: String, options: [(String, String)],
                               onPick: @escaping (String) -> Void) -> UICellAccessory {
        let button = UIButton(type: .system)
        button.setTitle(value, for: .normal)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: options.map { title, raw in
            UIAction(title: title, state: title == value ? .on : .off) { _ in onPick(raw) }
        })
        return .customView(configuration: .init(customView: button, placement: .trailing()))
    }

    private func applySnapshot() {
        let list = entries
        entryByID = Dictionary(uniqueKeysWithValues: list.map { (Self.entryPrefix + $0.id, $0) })
        latestEntryID = list.first.map { Self.entryPrefix + $0.id }

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()

        snap.appendSections([.device])
        var deviceItems = [Self.latestID, Self.backUpNowID]
        if backups.lastError != nil { deviceItems.append(Self.backupErrorID) }
        snap.appendItems(deviceItems, toSection: .device)

        snap.appendSections([.folder])
        var folderItems = [Self.folderToggleID]
        if icloud.mirrorFailing { folderItems.append(Self.mirrorFailingID) }
        if icloud.designatedFolderName != nil {
            folderItems.append(Self.folderNameID)
            folderItems.append(Self.retentionID)
            if retentionExpanded { folderItems.append(Self.retentionWheelID) }
            folderItems.append(Self.frequencyID)
        }
        snap.appendItems(folderItems, toSection: .folder)

        snap.appendSections([.history])
        snap.appendItems(list.isEmpty ? [Self.emptyHistoryID]
                                      : list.map { Self.entryPrefix + $0.id }, toSection: .history)

        // The stamp, the count, the folder name, the badges and the in-flight spinner
        // all live under fixed identifiers.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Folder picking

    /// SwiftUI's `.fileImporter(allowedContentTypes: [.folder])`.
    private func pickFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    // MARK: Row actions

    private func entry(at indexPath: IndexPath) -> BackupEntry? {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return entryByID[id]
    }

    /// Swipe RIGHT to restore, matching the SwiftUI leading edge.
    private func restoreSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard restoring == nil, let entry = entry(at: indexPath) else { return nil }
        let restore = UIContextualAction(style: .normal, title: String(localized: "Restore")) { [weak self] _, _, done in
            self?.confirmRestore(entry); done(false)
        }
        restore.image = UIImage(systemName: "arrow.counterclockwise")
        restore.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [restore])
    }

    private func deleteSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard restoring == nil, let entry = entry(at: indexPath) else { return nil }
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(entry); done(false)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: Destructive flows

    private func confirmRestore(_ entry: BackupEntry) {
        let sheet = UIAlertController(
            title: String(localized: "Restore the backup from \(Self.full(entry.date))?"),
            message: String(localized: "This replaces all current data. Your current data is backed up first, so you can restore it back."),
            preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Restore"), style: .destructive) { [weak self] _ in
            Task { await self?.restore(entry) }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = collectionView
        present(sheet, animated: true)
    }

    /// Order is load-bearing — see the note at the top of this file.
    @MainActor private func restore(_ entry: BackupEntry) async {
        guard await gate.confirmSensitive() else { return }
        restoring = entry
        applySnapshot()
        defer { restoring = nil; applySnapshot() }

        // Read the target's bytes BEFORE snapshotting the current state: flush()
        // refreshes the on-device latest and re-prunes the folder, either of which
        // could evict this very snapshot.
        let data: Data?
        if entry.onDevice {
            data = try? Data(contentsOf: backups.url(forName: entry.name))
        } else {
            data = await icloud.download(name: entry.name)
        }
        guard let data else {
            presentError(String(localized: "Couldn't read that backup — it may still be downloading from iCloud."),
                         title: String(localized: "Restore failed"))
            return
        }
        await backups.flush()   // reversible: the current state becomes the new Latest
        do {
            try await store.loadPack(from: data)
            Haptics.success()
        } catch PackError.auditFailed(let problems) {
            presentError(String(localized: "\(problems.count) integrity problem(s). Use Settings › About › Force import to override (iOS only)."),
                         title: String(localized: "Backup failed its integrity check"))
        } catch {
            Haptics.warning()
            presentError(i18nMessage(error), title: String(localized: "Restore failed"))
        }
    }

    private func confirmDelete(_ entry: BackupEntry) {
        let alert = UIAlertController(
            title: String(localized: "Delete this backup?"),
            message: String(localized: "The backup from \(Self.full(entry.date)) will be removed everywhere it’s saved. This can’t be undone."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            // Remove it from EVERY store it lives in. A manual delete is explicit
            // intent; only automatic pruning is device-scoped.
            if entry.onDevice { self.backups.deleteLocal(name: entry.name) }
            if entry.inICloud { self.icloud.delete(name: entry.name) }
            self.applySnapshot()
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func presentError(_ message: String, title: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: Formatting — the SwiftUI screen's private statics

    private static func full(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale))
    }
    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension BackupsVC: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        icloud.setFolder(url)
        applySnapshot()
    }

    /// Cancelling leaves the toggle showing ON until the snapshot puts it back.
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        applySnapshot()
    }
}

extension BackupsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        // Backup rows are INERT — restore and delete are swipe/long-press only, so a
        // stray tap can never start a destructive flow.
        if id == Self.backUpNowID { return !store.ledgers.isEmpty }
        return id == Self.folderNameID || id == Self.retentionID
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        switch id {
        case Self.backUpNowID:
            Task { await backups.flush() }
        case Self.folderNameID:
            pickFolder()
        case Self.retentionID:
            retentionExpanded.toggle()
            applySnapshot()
        default:
            break
        }
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard restoring == nil, let entry = entry(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var items: [UIMenuElement] = [
                UIAction(title: String(localized: "Restore"),
                         image: UIImage(systemName: "arrow.counterclockwise")) { _ in
                    self?.confirmRestore(entry)
                },
            ]
            // iCloud-only snapshots already live in Files › iCloud Drive › finch, so
            // in-app Share only needs to cover on-device packs.
            if entry.onDevice {
                items.append(UIAction(title: String(localized: "Share"),
                                      image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self?.share(entry)
                })
            }
            items.append(UIAction(title: String(localized: "Delete"),
                                  image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                self?.confirmDelete(entry)
            })
            return UIMenu(children: items)
        }
    }

    /// SwiftUI's `ShareLink`.
    private func share(_ entry: BackupEntry) {
        let share = UIActivityViewController(activityItems: [backups.url(forName: entry.name)],
                                             applicationActivities: nil)
        share.popoverPresentationController?.sourceView = collectionView
        present(share, animated: true)
    }
}

/// The history row: date over size, a "Latest" pill, the location badges, and an
/// in-flight spinner. Hosted because the pill and badge cluster are pure layout.
private struct BackupRowVisual: View {
    let date: String
    let size: String
    let isLatest: Bool
    let onDevice: Bool
    let inICloud: Bool
    let downloaded: Bool
    let restoring: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: date).foregroundStyle(.primary)
                Text(verbatim: size).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isLatest {
                Text("Latest").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            // 📱 on device · folder / download arrow for the folder copy.
            HStack(spacing: 4) {
                if onDevice { Image(systemName: "iphone").foregroundStyle(.secondary) }
                if inICloud {
                    Image(systemName: downloaded ? "folder" : "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .accessibilityLabel(onDevice && inICloud ? "On device and in backup folder"
                                : onDevice ? "On device" : "In backup folder")
            if restoring { ProgressView() }
        }
    }
}
#endif
