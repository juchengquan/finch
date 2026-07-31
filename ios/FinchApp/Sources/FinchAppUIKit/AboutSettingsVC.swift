#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screens 19–20: `SettingsAboutView` and `AuditDetailView` converted.
///
/// Versions, the database summary (including a row-count list that grows with the
/// schema), the audit state, and the force-import escape hatch.
///
/// The audit detail is converted alongside it — fifteen lines in SwiftUI — so the
/// About chain stays native rather than pushing a hosted screen for a list of
/// three-line problem records.
///
/// FORCE IMPORT IS THE DANGEROUS ONE. It is a deliberate iOS-only divergence (D7):
/// the web has no audit-skip path. It replaces the live database with a pack the
/// audit REJECTED, and cannot be undone. The order here matches SwiftUI exactly —
/// confirm, then `gate.confirmSensitive()`, then the write — because the biometric
/// prompt is the last line of defence and must not be skipped when the confirmation
/// alert is dismissed some other way.
final class AboutSettingsVC: UIViewController {

    private let store = FinchStore.shared
    private let gate = BiometricGate.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case versions, database, audit, forceImport }

    private static let appVersionID = "__app_version__"
    private static let packVersionID = "__pack_version__"
    private static let filenameID = "__filename__"
    private static let sizeID = "__size__"
    private static let schemaID = "__schema__"
    private static let lastImportID = "__last_import__"
    private static let auditID = "__audit__"
    private static let forceImportID = "__force_import__"
    /// Row counts are data-driven, so their identifiers are too.
    private static let rowCountPrefix = "__rows__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []
    private var rowCounts: [String: Int] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "About")
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        // dbInfo and auditProblems are both rewritten by a reprojection or an import.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            // Only Database and Audit carry headers, as in SwiftUI.
            config.headerMode = (kind == .database || kind == .audit) ? .supplementary : .none
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
            cell.accessories = []
            let info = self.store.dbInfo

            switch id {
            case Self.appVersionID:
                self.configureValueRow(cell, String(localized: "App version"), FinchCore.version)
            case Self.packVersionID:
                self.configureValueRow(cell, String(localized: "Pack format"), FinchCore.packFormatVersion)
            case Self.filenameID:
                self.configureValueRow(cell, String(localized: "Filename"), info.filename)
            case Self.sizeID:
                self.configureValueRow(cell, String(localized: "Size"), info.formattedSize)
            case Self.schemaID:
                self.configureValueRow(cell, String(localized: "Schema version"), info.schemaVersion)
            case Self.lastImportID:
                self.configureValueRow(cell, String(localized: "Last imported"), info.lastImportedAtDisplay)

            case Self.auditID:
                var cfg = cell.defaultContentConfiguration()
                let problems = self.store.auditProblems.count
                if problems == 0 {
                    cfg.text = String(localized: "Clean")
                    cfg.image = UIImage(systemName: "checkmark.seal")
                    cell.contentConfiguration = cfg
                } else {
                    cfg.text = String(localized: "\(problems) problems")
                    cfg.image = UIImage(systemName: "exclamationmark.triangle")
                    cell.contentConfiguration = cfg
                    cell.accessories = [.disclosureIndicator()]
                }

            case Self.forceImportID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Force import (skip audit — iOS only)")
                cfg.textProperties.color = .systemRed
                cell.contentConfiguration = cfg

            default:
                guard id.hasPrefix(Self.rowCountPrefix) else { return }
                let name = String(id.dropFirst(Self.rowCountPrefix.count))
                self.configureValueRow(cell, name, "\(self.rowCounts[name] ?? 0)")
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            switch self.sectionIDs[indexPath.section] {
            case .database: cfg.text = String(localized: "Database")
            case .audit: cfg.text = String(localized: "Audit")
            default: cfg.text = nil
            }
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
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
        trailing.textAlignment = .right
        cell.accessories = [.customView(configuration: .init(customView: trailing, placement: .trailing()))]
    }

    private func applySnapshot() {
        let ordered = store.dbInfo.rowCountsOrdered
        rowCounts = Dictionary(uniqueKeysWithValues: ordered)

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.versions])
        snap.appendItems([Self.appVersionID, Self.packVersionID], toSection: .versions)

        snap.appendSections([.database])
        snap.appendItems([Self.filenameID, Self.sizeID, Self.schemaID, Self.lastImportID]
                         + ordered.map { Self.rowCountPrefix + $0.0 }, toSection: .database)

        snap.appendSections([.audit])
        snap.appendItems([Self.auditID], toSection: .audit)

        snap.appendSections([.forceImport])
        snap.appendItems([Self.forceImportID], toSection: .forceImport)

        // Size, row counts and the audit state all change under fixed identifiers.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Force import

    /// Confirm FIRST, then the biometric gate, then the write — the SwiftUI order.
    /// The gate is what stops a passer-by replacing the database, so it must sit
    /// between the confirmation and the destructive call, never after it.
    private func confirmForceImport() {
        let alert = UIAlertController(
            title: String(localized: "Force import?"),
            message: String(localized: "This replaces your live database with the audit-rejected pack and cannot be undone."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Replace data"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard await self.gate.confirmSensitive() else { return }
                do { try self.store.forceImportCurrentPack() }
                catch { self.presentImportError(i18nMessage(error)) }
            }
        })
        present(alert, animated: true)
    }

    private func presentImportError(_ message: String) {
        let alert = UIAlertController(title: String(localized: "Import failed"),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
        present(alert, animated: true)
    }
}

extension AboutSettingsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        if id == Self.forceImportID { return true }
        // The audit row only navigates when there is something to show.
        if id == Self.auditID { return !store.auditProblems.isEmpty }
        return false
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if id == Self.forceImportID { confirmForceImport(); return }
        if id == Self.auditID, !store.auditProblems.isEmpty {
            navigationController?.pushViewController(
                AuditProblemsVC(problems: store.auditProblems), animated: true)
        }
    }
}

/// `AuditDetailView` converted — a read-only list of problem records.
final class AuditProblemsVC: UIViewController {

    private let problems: [Audit.AuditProblem]
    private enum SectionID: Hashable { case problems }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, Int>!

    init(problems: [Audit.AuditProblem]) {
        self.problems = problems
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Audit problems")
        navigationItem.largeTitleDisplayMode = .always

        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Indices as identifiers: two problems can be genuinely identical (same code,
        // no entry id, same detail), and duplicate item identifiers are fatal.
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { [weak self] cell, _, index in
            guard let self, self.problems.indices.contains(index) else { return }
            let problem = self.problems[index]
            cell.contentConfiguration = UIHostingConfiguration {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: problem.code.rawValue).font(.headline)
                    if let entryId = problem.entryId {
                        Text("entry: \(entryId)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(verbatim: problem.detail).font(.callout)
                }
            }
        }
        dataSource = UICollectionViewDiffableDataSource<SectionID, Int>(collectionView: collectionView) {
            cv, indexPath, index in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: index)
        }
        var snap = NSDiffableDataSourceSnapshot<SectionID, Int>()
        snap.appendSections([.problems])
        snap.appendItems(Array(problems.indices), toSection: .problems)
        dataSource.apply(snap, animatingDifferences: false)
    }
}

extension AuditProblemsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }
}
#endif
