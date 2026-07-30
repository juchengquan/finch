#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 18: `SettingsBackupSyncView` converted to UIKit.
///
/// Two sections: the backup summary (last backup, a count that drills into the
/// history) and the import/export buttons.
///
/// `ImportButton`, `ExportButton` and `ExportCsvButton` stay SwiftUI, hosted one per
/// cell. They are not decorative — each owns a file importer or a share sheet and
/// its own progress and error handling. Rebuilding that in UIKit would duplicate the
/// riskiest code on the screen (import REPLACES the database) for no benefit, so the
/// cells are non-selectable and the hosted buttons keep their own touches.
///
/// KNOWN GAP: the Backups row still pushes `SettingsBackupsView`, which is 235 lines
/// of SwiftUI and out of scope here. That makes it the one remaining hosted SwiftUI
/// scroll view inside a pushed page — reproducer B — so that screen can still
/// shadow. Recorded in the verification checklist.
final class BackupSyncSettingsVC: UIViewController {

    private let store = FinchStore.shared
    private let backups = AutoBackupManager.shared
    private let icloud = ICloudSync.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case backups, importExport }

    private static let lastBackupID = "__last_backup__"
    private static let backupsID = "__backups__"
    private static let importID = "__import__"
    private static let exportID = "__export__"
    private static let exportCsvID = "__export_csv__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Backup & Sync")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        // Both drive the summary row: a new backup changes the stamp and the count.
        Publishers.Merge(backups.objectWillChange, icloud.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .supplementary
            config.footerMode = .supplementary
            _ = self
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

    private var backupCount: Int {
        BackupHistory.merge(local: backups.localBackups(), iCloud: icloud.remoteBackups).count
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self else { return }
            cell.accessories = []

            switch id {
            case Self.lastBackupID:
                let stamp = self.backups.lastBackupAt.map {
                    $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(AppDate.h24Locale))
                } ?? "—"
                self.configureValueRow(cell, String(localized: "Last backup"), stamp)

            case Self.backupsID:
                self.configureValueRow(cell, String(localized: "Backups"), "\(self.backupCount)")
                cell.accessories.append(.disclosureIndicator())

            // These MUST get the environment objects injected. A UIHostingConfiguration
            // does NOT inherit them from anywhere — unlike `hosted()` below, which is
            // for presented controllers — and all three buttons read
            // @EnvironmentObject (store, and the export ones also the biometric gate).
            // Omitting them is not a silent no-op: SwiftUI traps with "No
            // ObservableObject of type FinchStore found", which crashed the app the
            // moment this screen opened.
            case Self.importID:
                cell.contentConfiguration = UIHostingConfiguration {
                    ImportButton()
                        .environmentObject(self.store)
                        .environmentObject(BiometricGate.shared)
                }
            case Self.exportID:
                cell.contentConfiguration = UIHostingConfiguration {
                    ExportButton()
                        .environmentObject(self.store)
                        .environmentObject(BiometricGate.shared)
                }
            case Self.exportCsvID:
                cell.contentConfiguration = UIHostingConfiguration {
                    ExportCsvButton()
                        .environmentObject(self.store)
                        .environmentObject(BiometricGate.shared)
                }

            default:
                break
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            cfg.text = self.sectionIDs[indexPath.section] == .backups
                ? String(localized: "Backups")
                : String(localized: "Import & Export")
            view.contentConfiguration = cfg
        }

        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            cfg.text = self.sectionIDs[indexPath.section] == .backups
                ? String(localized: "finch always keeps your latest backup on this device. Open Backups to add a folder history (count, frequency), browse backups, and restore an earlier version.")
                : String(localized: "Export your whole ledger set as a self-contained .finch file; import to replace your data (audited first). The CSV export covers the active ledger's full transaction history.")
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

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.backups])
        snap.appendItems([Self.lastBackupID, Self.backupsID], toSection: .backups)
        snap.appendSections([.importExport])
        snap.appendItems([Self.importID, Self.exportID, Self.exportCsvID], toSection: .importExport)

        // The stamp and the count both live under fixed identifiers.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }
}

extension BackupSyncSettingsVC: UICollectionViewDelegate {
    /// Only the Backups row navigates; the three button rows host their own controls.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) == Self.backupsID
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard dataSource.itemIdentifier(for: indexPath) == Self.backupsID else { return }
        // Still SwiftUI, hosted — see the note at the top of this file.
        navigationController?.pushViewController(hosted(SettingsBackupsView()), animated: true)
    }
}
#endif
