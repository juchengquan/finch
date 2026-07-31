#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// `LedgerListView` converted to UIKit — the ledger list.
///
/// **Why this one, and why with its detail.** The ledger flow is the last hosted
/// SwiftUI scroll view left in the UIKit shell: `RootTabBarController` presents
/// `LedgerListView` inside a `.rightSlideDrill` cover even under `-uikitActivity YES`,
/// where every other screen is native. Converting the list ALONE would have made
/// things worse, not better — a native list pushing a hosted `LedgerDetailView` is
/// reproducer B exactly (a hosted SwiftUI scroll view at navigation depth), so the
/// detail had to land in the same change. See `LedgerDetailVC`.
///
/// Sheets stay in SwiftUI (`AddLedgerSheet`, `EditLedgerSheet`): they are presented,
/// never pushed, so they cannot shadow, and they own write forms it would be reckless
/// to retype.
final class LedgersVC: UIViewController {

    private let store = FinchStore.shared
    private let gate = BiometricGate.shared
    private var cancellables = Set<AnyCancellable>()

    /// Selection mode. `nil` → compact: a row PUSHES its detail. Non-nil → this list
    /// drives a split view's detail column and reports the id instead.
    ///
    /// The UIKit counterpart of the `selection: Binding<String?>?` the SwiftUI screens
    /// carry. A closure rather than a binding because the owner here is a view
    /// controller, and because the list never needs to read the value back — only the
    /// highlight does, and that comes through `selectedID`.
    private let onSelect: ((String) -> Void)?
    /// The row to show as selected, when a split view owns the selection.
    var selectedID: String? {
        didSet { guard selectedID != oldValue else { return }; applySnapshot() }
    }

    init(onSelect: ((String) -> Void)? = nil) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private enum SectionID: Hashable { case ledgers }
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!

    /// Ledger by id, so the diffable ids stay `Hashable` strings.
    private var ledgerByID: [String: Ledger] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Ledgers")
        configureCollectionView()
        configureDataSource()
        configureToolbar()
        applySnapshot()

        // `ledgers` is @Published; `activeLedgerId` drives the checkmark, and the net
        // worth column moves with the transactions.
        Publishers.Merge3(store.$ledgers.map { _ in () },
                          store.$activeLedgerId.map { _ in () },
                          store.$txns.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
            self?.swipeActions(at: ip)
        }
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
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self, let ledger = self.ledgerByID[id] else { return }
            var cfg = cell.defaultContentConfiguration()
            cfg.text = ledger.name
            cfg.secondaryText = ledger.base          // the base currency, as the SwiftUI row shows
            cfg.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            cfg.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = cfg

            // Trailing: net worth, preceded by a tick on the active ledger.
            let worth = UILabel()
            worth.text = self.store.displayMoney(self.store.netWorth(forLedger: ledger.id),
                                                 forLedger: ledger.id)
            worth.font = .preferredFont(forTextStyle: .subheadline)
            worth.textColor = .secondaryLabel
            var accessories: [UICellAccessory] = [
                .customView(configuration: .init(customView: worth, placement: .trailing()))
            ]
            // A chevron promises a push. In selection mode the row fills a column
            // beside it instead, so the chevron would be a lie.
            if self.onSelect == nil { accessories.append(.disclosureIndicator()) }
            if ledger.id == self.store.activeLedgerId {
                let tick = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
                tick.tintColor = .tintColor
                tick.contentMode = .scaleAspectFit
                accessories.insert(.customView(configuration: .init(customView: tick, placement: .trailing())),
                                   at: 0)
            }
            cell.accessories = accessories
        }
        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    private func configureToolbar() {
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
            self?.presentAddLedger()
        })
        add.accessibilityLabel = String(localized: "Add Ledger")
        navigationItem.rightBarButtonItem = add
    }

    private func applySnapshot() {
        ledgerByID = Dictionary(uniqueKeysWithValues: store.ledgers.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.ledgers])
        snap.appendItems(store.ledgers.map(\.id), toSection: .ledgers)
        // Ids are stable across a rename or an active-ledger switch, so carried-over
        // rows must be told to re-read or the tick and the net worth stay stale.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)

        // Re-assert the highlight: `apply` clears the selection, so without this the
        // row stops looking selected every time a net worth changes underneath it.
        if let selectedID, let ip = dataSource.indexPath(for: selectedID) {
            collectionView.selectItem(at: ip, animated: false, scrollPosition: [])
        }
    }

    // MARK: Actions

    /// Delete is disabled at one ledger: the app has no meaningful state with none,
    /// and the SwiftUI row disables it the same way.
    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let ledger = ledgerByID[id], store.ledgers.count > 1 else { return nil }
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(ledger); done(true)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func confirmDelete(_ ledger: Ledger) {
        // A centred alert, not a row-anchored dialog — the SwiftUI screen notes that a
        // row-anchored popout dies with the row when the swipe collapses.
        let alert = UIAlertController(
            title: String(localized: "Delete this ledger?"),
            message: String(localized: "This permanently deletes \(ledger.name) and all its data."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Delete \(ledger.name)"),
                                      style: .destructive) { [weak self] _ in self?.delete(ledger) })
        present(alert, animated: true)
    }

    private func delete(_ ledger: Ledger) {
        // Destroying a ledger destroys its data — gated like the other sensitive
        // actions, exactly as the SwiftUI screen gates it.
        Task { @MainActor in
            guard await gate.confirmSensitive() else { return }
            do {
                try store.apply(.deleteLedger, Args(["id": .string(ledger.id)]))
                if store.activeLedgerId == ledger.id {
                    // Deleted the active one — fall back to whatever remains, or the
                    // rest of the app is scoped to a ledger that no longer exists.
                    store.activeLedgerId = store.ledgers.first?.id ?? ""
                }
            } catch {
                presentError(i18nMessage(error))
            }
        }
    }

    private func presentAddLedger() {
        let host = UIHostingController(rootView:
            AddLedgerSheet()
                .environmentObject(store)
                .environmentObject(gate))
        present(host, animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

extension LedgersVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if let onSelect {
            // Stay selected: the row is the current state of the column beside it, not
            // a button that fired.
            selectedID = id
            onSelect(id)
            return
        }
        cv.deselectItem(at: indexPath, animated: true)
        navigationController?.pushViewController(LedgerDetailVC(ledgerId: id), animated: true)
    }

    /// Long-press delete, mirroring the SwiftUI row's context menu.
    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let ledger = ledgerByID[id], store.ledgers.count > 1 else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Delete"),
                         image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in self?.confirmDelete(ledger) }
            ])
        }
    }
}
#endif
