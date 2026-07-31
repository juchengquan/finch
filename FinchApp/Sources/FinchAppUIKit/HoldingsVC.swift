#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 4: `HoldingsView` converted to UIKit.
///
/// Investment positions: shares, market value and unrealized gain/loss per row;
/// add a position, update its price, delete it. The writes go through the same
/// `createHolding` / `setHoldingPrice` / `deleteHolding` actions as before.
///
/// The row itself stays SwiftUI — `HoldingRow` is reused verbatim in a
/// `UIHostingConfiguration`. It is a leaf view, so the `UICollectionView` remains
/// the screen's scroll view (hosting a whole SwiftUI scroll view in a pushed page
/// is reproducer B and shadows), and reusing it means the two-column layout, the
/// gain/loss colouring and the money formatting are not reimplemented — nor are
/// its string-catalog keys duplicated.
///
/// The empty state uses `UIContentUnavailableConfiguration`, the native
/// counterpart of `ContentUnavailableView`.
final class HoldingsVC: UIViewController {

    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    /// Positions can only be added to an investment account, so with none the `+` is
    /// disabled and the empty state says so instead.
    private var investmentAccounts: [AccountRow] {
        store.accounts.filter { $0.type == "investment" }
    }

    private enum SectionID: Hashable { case all }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var holdingByID: [String: Holding] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Holdings")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        configureToolbar()
        applySnapshot()

        store.$holdings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
        store.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Changes the `+` enabled state and the empty state's wording.
                self?.configureToolbar()
                self?.applySnapshot()
            }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none          // the SwiftUI List has no Section header
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActions(at: indexPath)
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
            guard let self, let holding = self.holdingByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                HoldingRow(holding: holding).environmentObject(self.store)
            }
            cell.accessories = []
        }
        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    private func applySnapshot() {
        holdingByID = Dictionary(uniqueKeysWithValues: store.holdings.map { ($0.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.all])
        snap.appendItems(store.holdings.map(\.id), toSection: .all)
        // A price update leaves the id alone, so without this the row would keep
        // showing the old value and gain/loss.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)

        updateEmptyState()
    }

    /// `ContentUnavailableView`'s native counterpart. Setting it to nil restores the
    /// list, so this is safe to call on every update.
    private func updateEmptyState() {
        guard store.holdings.isEmpty else {
            contentUnavailableConfiguration = nil
            return
        }
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "chart.bar")
        config.text = String(localized: "No holdings")
        config.secondaryText = investmentAccounts.isEmpty
            ? String(localized: "Add an investment account first (import a pack with one).")
            : String(localized: "Tap + to add a position.")
        contentUnavailableConfiguration = config
    }

    // MARK: Bars, gestures, writes

    private func configureToolbar() {
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
            self?.presentAdd()
        })
        add.accessibilityLabel = String(localized: "Add Holding")
        add.isEnabled = !investmentAccounts.isEmpty
        navigationItem.rightBarButtonItems = [add]
    }

    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let holding = holdingByID[id] else { return nil }
        // Deliberately `.normal`, not `.destructive`: the destructive style plays a
        // row-removal animation before the confirmation is answered.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(holding)
            done(false)   // the row stays until the alert is answered
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
    }

    /// Centered alert, not a row-anchored sheet — the row is torn down when the swipe
    /// collapses or the cell recycles, which would take a popout with it.
    private func confirmDelete(_ holding: Holding) {
        let alert = UIAlertController(
            title: String(localized: "Delete holding?"),
            message: String(localized: "\(holding.symbol) is removed from this account."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.apply(.deleteHolding, Args(["id": .string(holding.id)])) }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    // MARK: Sheets — still SwiftUI, hosted. They are presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    private func presentAdd() {
        present(hosted(AddHoldingSheet(accounts: investmentAccounts)), animated: true)
    }

    private func presentPrice(_ holding: Holding) {
        present(hosted(SetHoldingPriceSheet(holding: holding)), animated: true)
    }
}

extension HoldingsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let holding = holdingByID[id] else { return }
        presentPrice(holding)
    }

    /// Right-click on Mac/iPad and long-press on touch, matching the SwiftUI row's
    /// context menu. Swipe is touch-only, which is why both exist.
    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let holding = holdingByID[id] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in self?.confirmDelete(holding) },
            ])
        }
    }
}
#endif
