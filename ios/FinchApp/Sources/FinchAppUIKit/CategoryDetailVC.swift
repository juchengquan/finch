#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 9: `CategoryDetailView` converted to UIKit.
///
/// A category's transactions plus aggregate stats, pushed from `CategoriesVC`.
/// Converting it matters beyond parity: it was the last hosted SwiftUI screen in
/// the Categories chain, and a hosted SwiftUI scroll view inside a PUSHED page is
/// reproducer B — the shape that brings the iOS 26 resume shadow back. Categories
/// itself was already clean; this closes the drill behind it.
///
/// Membership deliberately matches the count pill on the parent page:
/// `categoryTransactions` ≙ `categoryTxCounts`, i.e. split legs included, pending
/// excluded. Pending rows are queried separately and pinned on top rather than
/// silently omitted — the same "To confirm" treatment the account detail gives.
///
/// The row is the shared SwiftUI `TxRow`, hosted. It is a leaf, so the collection
/// view stays the scroll view, and hosting it keeps the tag chips, the receipt
/// indicator and the relative-date formatting that a hand-built UIKit cell would
/// silently drop.
final class CategoryDetailVC: UIViewController {

    private let category: CategoryRow
    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case summary, pending, transactions }

    private static let countID = "__count__"
    private static let totalID = "__total__"
    private static let averageID = "__average__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []
    private var txByID: [String: Tx] = [:]
    private var headerContent: [SectionID: String] = [:]
    /// Recomputed in `applySnapshot` so the summary cells never re-derive.
    private var summary: (count: Int, total: Double) = (0, 0)

    init(category: CategoryRow) {
        self.category = category
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = category.name
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            // The summary block is a bare `Section { }` in SwiftUI — no header.
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            config.headerMode = (kind == .summary) ? .none : .supplementary
            config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.rowActions(at: ip).map { $0.actions.leading($0.tx) }
            }
            config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.rowActions(at: ip).map { $0.actions.trailing($0.tx) }
            }
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

            switch id {
            case Self.countID:
                self.configureValueRow(cell, String(localized: "Transactions"), "\(self.summary.count)")
            case Self.totalID:
                self.configureValueRow(cell, String(localized: "Total"),
                                       self.store.displayMoneyBase(self.summary.total))
            case Self.averageID:
                let average = self.summary.count > 0
                    ? self.summary.total / Double(self.summary.count) : 0
                self.configureValueRow(cell, String(localized: "Average"),
                                       self.store.displayMoneyBase(average))
            default:
                guard let tx = self.txByID[id] else { return }
                // The shared SwiftUI row, hosted verbatim — a leaf, so the collection
                // view remains the scroll view. `showRunningBalance: false` because a
                // running balance only reads sensibly when every row shares one
                // account, which a category's rows do not.
                cell.contentConfiguration = UIHostingConfiguration {
                    TxRow(txn: tx, showRunningBalance: false)
                        .environmentObject(self.store)
                }
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            cfg.text = self.headerContent[self.sectionIDs[indexPath.section]]
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
        cell.accessories = [.customView(configuration: .init(customView: trailing, placement: .trailing()))]
    }

    private func applySnapshot() {
        let ledger = store.activeLedgerId
        let txns = Selectors.categoryTransactions(store.txns, category.id, ledger)
        // Pending is excluded from `txns` (and from the parent's count pill), so it is
        // fetched separately rather than being dropped on the floor.
        let pending = Selectors.categoryTransactions(store.txns, category.id, ledger,
                                                     includePending: true)
            .filter { $0.pending == true }

        summary = (txns.count, txns.reduce(0) { $0 + $1.amount })
        txByID = Dictionary(uniqueKeysWithValues: (txns + pending).map { ($0.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        var headers: [SectionID: String] = [:]

        snap.appendSections([.summary])
        var summaryItems = [Self.countID, Self.totalID]
        if !txns.isEmpty { summaryItems.append(Self.averageID) }   // no average over zero
        snap.appendItems(summaryItems, toSection: .summary)

        if !pending.isEmpty {
            snap.appendSections([.pending])
            snap.appendItems(pending.map(\.id), toSection: .pending)
            headers[.pending] = String(localized: "To confirm (\(pending.count))")
        }
        if !txns.isEmpty {
            snap.appendSections([.transactions])
            snap.appendItems(txns.map(\.id), toSection: .transactions)
            headers[.transactions] = String(localized: "Transactions")
        }

        // The summary cells sit under fixed identifiers and every figure on them is
        // derived, so without this a delete or a status flip would leave them stale.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        headerContent = headers
        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Row actions

    /// The SwiftUI row passes no `previewReceipt`, so the menu omits it here too.
    private func rowActions(at indexPath: IndexPath) -> (tx: Tx, actions: TxRowActions)? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let tx = txByID[id] else { return nil }
        let actions = TxRowActions(
            duplicate: { [weak self] tx in self?.presentDuplicate(tx) },
            requestDelete: { [weak self] tx in self?.confirmDelete(tx) },
            toggleStatus: { [weak self] tx in
                guard let self else { return }
                self.run { try txnToggleStatus(tx, store: self.store) }
            },
            edit: { [weak self] tx in self?.presentEdit(tx) },
            previewReceipt: nil)
        return (tx, actions)
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    /// Centered alert, not a row-anchored sheet — row recycling tears a popout down.
    private func confirmDelete(_ tx: Tx) {
        let alert = UIAlertController(title: String(localized: "Delete transaction?"),
                                      message: "\(tx.merchant) · \(store.displayMoneyBase(tx.amount))",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.deleteTransaction(tx.id); Haptics.warning() }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    private func presentEdit(_ tx: Tx) {
        present(hosted(EditTransactionSheet(txn: tx)), animated: true)
    }

    /// Duplicate opens the Add sheet pre-filled; nothing is written until Save.
    private func presentDuplicate(_ tx: Tx) {
        present(hosted(AddTransactionSheet(prefill: tx)), animated: true)
    }
}

extension CategoryDetailVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return txByID[id] != nil   // the summary rows are read-only
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let tx = txByID[id] else { return }
        presentEdit(tx)
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let row = rowActions(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            row.actions.menu(row.tx)
        }
    }
}
#endif
