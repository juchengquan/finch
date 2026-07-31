#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 13: `SettingsPowerToolsView` converted to UIKit.
///
/// Settings › Experimental Labs — Rules, plus the CloudKit sync scaffold.
///
/// Unlike the screens converted so far, almost every row here is CONDITIONAL on
/// live coordinator state: the progress row appears while bootstrapping or syncing,
/// and the four status rows plus the error line only exist while sync is enabled.
/// So this VC observes `CloudKitSyncCoordinator` as well as the store, and rebuilds
/// its snapshot from scratch each time — the rows are cheap and the alternative is
/// hand-maintained insert/remove logic that would drift from the SwiftUI conditions.
///
/// The sync section is inert scaffold on a simulator (the network layer activates
/// only once the CloudKit container is provisioned, and there is no iCloud account),
/// so most of these states cannot be produced here. They are listed in the
/// verification checklist rather than claimed as working.
final class PowerToolsVC: UIViewController {

    private let store = FinchStore.shared
    private let cloudSync = CloudKitSyncCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case rules, sync }

    private static let rulesID = "__rules__"
    private static let toggleID = "__sync_toggle__"
    private static let progressID = "__sync_progress__"
    private static let statusID = "__status__"
    private static let pendingID = "__pending__"
    private static let lastSyncID = "__last_sync__"
    private static let errorID = "__error__"
    private static let resyncID = "__resync__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Experimental Labs")
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        // The coordinator drives which rows exist at all, so it is the primary
        // signal here — the store only matters for the resync call.
        cloudSync.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        // Only the sync section has a header and a footer.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            config.headerMode = (kind == .sync) ? .supplementary : .none
            config.footerMode = (kind == .sync) ? .supplementary : .none
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
            case Self.rulesID:
                cfg.text = String(localized: "Rules")
                cell.contentConfiguration = cfg
                cell.accessories = [.disclosureIndicator()]

            case Self.toggleID:
                cfg.text = String(localized: "Sync across devices (iCloud)")
                cell.contentConfiguration = cfg
                ToggleAccessory.install(on: cell, isOn: self.cloudSync.enabled) { [weak self] on in
                    guard let self else { return }
                    Task { await self.cloudSync.setEnabled(on, store: self.store) }
                }

            case Self.progressID:
                // Bootstrapping wins over syncing, as in the SwiftUI `if / else if`.
                cfg.text = self.cloudSync.isBootstrapping
                    ? String(localized: "Setting up iCloud sync…")
                    : String(localized: "Syncing…")
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessories = [.customView(configuration: .init(customView: spinner,
                                                                     placement: .leading()))]

            case Self.statusID:
                let status = self.cloudSync.status
                self.configureValueRow(cell, String(localized: "Status"),
                                       status.accountAvailable
                                           ? String(localized: "Subscribed to \(status.subscribedLedgers) ledgers")
                                           : String(localized: "iCloud account required"))

            case Self.pendingID:
                self.configureValueRow(cell, String(localized: "Pending changes"),
                                       "\(self.cloudSync.status.pendingChanges)")

            case Self.lastSyncID:
                let stamp = self.cloudSync.status.lastSyncAt.map {
                    $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(AppDate.h24Locale))
                } ?? "—"
                self.configureValueRow(cell, String(localized: "Last sync"), stamp)

            case Self.errorID:
                cfg.text = self.cloudSync.status.lastError
                cfg.textProperties.color = .systemRed
                cfg.textProperties.font = .preferredFont(forTextStyle: .caption1)
                cell.contentConfiguration = cfg

            case Self.resyncID:
                cfg.text = String(localized: "Resync ledger")
                // Disabled without an iCloud account, as in SwiftUI.
                cfg.textProperties.color = self.cloudSync.status.accountAvailable
                    ? .tintColor : .tertiaryLabel
                cell.contentConfiguration = cfg

            default:
                break
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { view, _, _ in
            var cfg = view.defaultContentConfiguration()
            cfg.text = String(localized: "Sync")
            view.contentConfiguration = cfg
        }

        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { view, _, _ in
            var cfg = view.defaultContentConfiguration()
            cfg.text = String(localized: "Row-level live sync over iCloud (CloudKit). Scaffold — the network layer activates once the CloudKit container is provisioned; without an iCloud account it stays inactive. Your data is always exportable as a .finch file.")
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
        snap.appendSections([.rules])
        snap.appendItems([Self.rulesID], toSection: .rules)

        snap.appendSections([.sync])
        var items = [Self.toggleID]
        if cloudSync.isBootstrapping || cloudSync.isSyncing { items.append(Self.progressID) }
        if cloudSync.enabled {
            items += [Self.statusID, Self.pendingID, Self.lastSyncID]
            if cloudSync.status.lastError != nil { items.append(Self.errorID) }
            items.append(Self.resyncID)
        }
        snap.appendItems(items, toSection: .sync)

        // Every one of these rows displays live coordinator state under a fixed
        // identifier, so a pending-count change or a new timestamp would otherwise
        // never redraw.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
    }
}

extension PowerToolsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        if id == Self.rulesID { return true }
        if id == Self.resyncID { return cloudSync.status.accountAvailable }
        // A tap anywhere on the sync row flips it, as SwiftUI's Toggle does.
        if id == Self.toggleID { return true }
        return false   // the spinner and the status rows are not tappable
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }

        if id == Self.toggleID {
            if let cell = cv.cellForItem(at: indexPath) as? UICollectionViewListCell {
                ToggleAccessory.flip(on: cell)
            }
            return
        }
        if id == Self.resyncID {
            Task { await cloudSync.resync(store: store) }
            return
        }
        guard id == Self.rulesID else { return }
        // Converted too, so nothing reachable from here is a hosted SwiftUI scroll
        // view in a pushed page.
        navigationController?.pushViewController(RulesManagerVC(), animated: true)
    }
}
#endif
