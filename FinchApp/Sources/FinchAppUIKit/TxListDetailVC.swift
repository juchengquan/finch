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
            // `categoryShares`, not `categoryTransactions`: each row carries only
            // what THIS category took. A 100 shop split 70/30 reported 100 under
            // both categories, so the two screens together claimed 200 of spend.
            // Narrowing happens BEFORE `applySnapshot` collapses by purchase,
            // which is the only order that works for a grid group — its rows are
            // separate entries that both carry both categories.
            Source(title: row.name,
                   confirmed: { Selectors.categoryShares($0.txns, row.id, $0.activeLedgerId) },
                   pending: {
                       Selectors.categoryShares($0.txns, row.id, $0.activeLedgerId,
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

    /// The real transaction behind a row.
    ///
    /// On the category screen a row carries only that category's share, so every
    /// ACTION must be handed the whole purchase back: an editor opened on a share
    /// would save a fraction of it, and a delete warning quoting one would
    /// understate what it removes. `id` survives the narrowing so this resolves.
    /// On the tag and merchant screens rows are already whole and this is a no-op.
    private func actual(_ t: Tx) -> Tx { store.txns.first { $0.id == t.id } ?? t }
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
                //
                // Pinned background, as the feed and the account detail do. Tapping a
                // swipe action highlights the cell, and diffable MOVES that cell to its
                // new index path rather than re-dequeuing it, so `prepareForReuse` never
                // fires and the highlight rides along — the arriving row draws grey and
                // fades over ~0.5s. A row that never paints a highlight has nothing to
                // leave behind. Safe here because selection is transient: rows deselect
                // on tap and this screen has no column mode. (#702)
                cell.backgroundConfiguration = txRowBackground()
                // The glyph tap, which this screen was missed out of. `19f1d32a` wired
                // it into the SwiftUI Category/Tag/Counterparty views and said it
                // covered "the tag / category / counterparty detail screens" — but
                // those ship as this ONE view controller, and it was not wired. Tapping
                // a glyph here did nothing.
                //
                // It matters now rather than later: with the swipe's status action
                // removed, the glyph is the gesture, and leaving it inert would take
                // the toggle off these screens entirely bar the context menu.
                TxRowCell.configure(cell, tx: tx, store: self.store,
                                    showRunningBalance: false,
                                    onToggleStatus: { [weak self] tapped in
                                        guard let self else { return }
                                        self.run { try txnToggleStatus(tapped, store: self.store) }
                                    })
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            self?.configureHeader(view, at: indexPath)
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
        // One row per PURCHASE, not per payment — the UIKit twin of the same rule
        // the three SwiftUI detail views follow. This screen answers "what did I
        // spend on this": a purchase paid on two cards is one shop, and which card
        // paid is not the question here. Collapsing at the source keeps the count,
        // total, average, the pending header and the list itself all agreeing.
        // An account's own screen is the opposite and deliberately does NOT.
        let txns = Selectors.byPurchase(source.confirmed(store))
        let pending = Selectors.byPurchase(source.pending(store))

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

        headerContent = headers                // before apply — the headers read it
        sectionIDs = snap.sectionIdentifiers   // before apply — the layout reads it
        dataSource.apply(snap, animatingDifferences: false) { [weak self] in
            self?.refreshVisibleHeaders()
        }
    }

    /// Extracted from the registration so `refreshVisibleHeaders()` can re-run it.
    ///
    /// Reads text computed in `applySnapshot` rather than deriving it from
    /// `dataSource.snapshot()`, which returns the PRE-apply sections while an apply is
    /// in flight and would leave every header one generation stale.
    private func configureHeader(_ view: UICollectionViewListCell, at indexPath: IndexPath) {
        guard sectionIDs.indices.contains(indexPath.section) else { return }
        var cfg = view.defaultContentConfiguration()
        cfg.text = headerContent[sectionIDs[indexPath.section]]
        view.contentConfiguration = cfg
    }

    /// A diffable data source does NOT re-render a supplementary view when only the
    /// section's ITEMS change — the section identifier is unchanged, so the header is
    /// left exactly as it was. `To confirm (N)` is computed FROM those rows, so this
    /// screen did not show the count late, it showed it WRONG: confirming a row moved
    /// it out of the bucket and the header kept the old number until it happened to be
    /// re-created by scrolling. The feed and the account detail already do this; this
    /// screen was simply missed. (#702)
    ///
    /// Deliberately in the apply's COMPLETION, where the collection view's section
    /// indices already match `sectionIDs`. Running it earlier would make the figures
    /// land in the same frame as the rows, but it also means writing a header from
    /// outside UIKit's update pass — which is the mechanism suspected in the device
    /// flicker that caused #710 to be reverted. Correct one frame late beats wrong.
    private func refreshVisibleHeaders() {
        let kind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            guard let view = collectionView.supplementaryView(forElementKind: kind, at: indexPath)
                    as? UICollectionViewListCell else { continue }
            configureHeader(view, at: indexPath)
        }
    }

    // MARK: Row actions

    /// The SwiftUI rows pass no `previewReceipt` on any of these three screens, so
    /// the menu omits it here too.
    private func rowActions(at indexPath: IndexPath) -> (tx: Tx, actions: TxRowActions)? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = txByID[id] else { return nil }
        let tx = actual(row)
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
        presentEdit(actual(tx))
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
