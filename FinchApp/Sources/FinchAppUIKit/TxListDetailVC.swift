#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screens 9–11: `CategoryDetailView`, `TagDetailView` and
/// `CounterpartyDetailView` converted — as ONE view controller.
///
/// Those three SwiftUI screens are the same screen three times: identical summary
/// block, identical pending/confirmed sections, identical row and gestures. They
/// differ only in the selector they call and the title they show. Rather than port
/// three near-identical files, this takes a `Source` and the callers pick one. The
/// SwiftUI side can stay as it is; the UIKit side does not inherit its triplication.
///
/// Converting these matters beyond parity: each was the last hosted SwiftUI screen
/// in its drill chain, and a hosted SwiftUI scroll view inside a PUSHED page is
/// reproducer B — the shape that brings the iOS 26 resume shadow back. With these
/// converted, Categories, Tags and Merchants are native end to end.
///
/// The row is the shared SwiftUI `TxRow`, hosted verbatim. It is a leaf, so the
/// collection view stays the scroll view, and hosting keeps the tag chips, the
/// pending clock, the kind bar and the relative dates that a hand-built cell drops.
final class TxListDetailVC: UIViewController {

    /// Title plus the two row sets. `confirmed` must match the parent page's count
    /// pill; `pending` is queried separately so pending rows are surfaced on top
    /// rather than silently omitted — the same treatment the account detail gives.
    struct Source {
        let title: String
        // @MainActor because FinchStore is: these read `txns` / `activeLedgerId`, and
        // they are only ever called from `applySnapshot` on the main actor.
        let confirmed: @MainActor (FinchStore) -> [Tx]
        let pending: @MainActor (FinchStore) -> [Tx]

        /// Membership matches `categoryTxCounts`: split legs in, pending out.
        static func category(_ row: CategoryRow) -> Source {
            Source(title: row.name,
                   confirmed: { Selectors.categoryTransactions($0.txns, row.id, $0.activeLedgerId) },
                   pending: {
                       Selectors.categoryTransactions($0.txns, row.id, $0.activeLedgerId,
                                                      includePending: true)
                           .filter { $0.pending == true }
                   })
        }

        /// Membership matches `tagTxCounts`: tagged in this ledger, pending out.
        static func tag(_ row: TagRow) -> Source {
            Source(title: row.name,
                   confirmed: { Selectors.tagTransactions($0.txns, row.id, $0.activeLedgerId) },
                   pending: {
                       Selectors.tagTransactions($0.txns, row.id, $0.activeLedgerId,
                                                 includePending: true)
                           .filter { $0.pending == true }
                   })
        }

        /// Membership matches `counterpartyTxCounts`.
        static func merchant(_ row: Counterparty) -> Source {
            Source(title: row.name,
                   confirmed: {
                       Selectors.merchantTransactions($0.txns, $0.merchants, row.id, $0.activeLedgerId)
                   },
                   pending: {
                       Selectors.merchantTransactions($0.txns, $0.merchants, row.id,
                                                      $0.activeLedgerId, includePending: true)
                           .filter { $0.pending == true }
                   })
        }
    }

    private let source: Source
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
    /// Recomputed in `applySnapshot`, so the summary cells never re-derive.
    private var summary: (count: Int, total: Double) = (0, 0)

    init(_ source: Source) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = source.title
        // Large: CategoryDetailView / TagDetailView / CounterpartyDetailView — the
        // three screens this replaces — all render large titles.
        navigationItem.largeTitleDisplayMode = .always
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
                let average = self.summary.count > 0 ? self.summary.total / Double(self.summary.count) : 0
                self.configureValueRow(cell, String(localized: "Average"),
                                       self.store.displayMoneyBase(average))
            default:
                guard let tx = self.txByID[id] else { return }
                // `showRunningBalance: false` — a running balance only reads sensibly
                // when every row shares one account, which none of these lists do.
                // Routed through TxRowCell for its row-height margins; this screen
                // already hosted TxRow, it just sat taller than the SwiftUI original.
                TxRowCell.configure(cell, tx: tx, store: self.store,
                                    showRunningBalance: false)
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
        let txns = source.confirmed(store)
        let pending = source.pending(store)

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

        // The summary cells sit under fixed identifiers and every figure is derived,
        // so without this a delete or a status flip would leave them stale.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        headerContent = headers
        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Row actions

    /// The SwiftUI rows pass no `previewReceipt` on any of these three screens, so
    /// the menu omits it here too.
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

extension TxListDetailVC: UICollectionViewDelegate {
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
