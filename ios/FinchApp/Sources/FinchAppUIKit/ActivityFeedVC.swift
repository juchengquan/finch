#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 1: `ActivityFeedView` converted to UIKit.
///
/// This is the template the rest of Phase 2 follows, so it is worth reading:
/// `UICollectionView` list configuration + a diffable data source for the pending
/// bucket and month sections, `UISearchController` for `.searchable`,
/// `UISwipeActionsConfiguration` for `.swipeActions`, `UIMenu` for the sort
/// picker, and sheets that stay SwiftUI in a `UIHostingController` — sheets are
/// presented, never pushed, so they never shadow and never need converting.
///
/// The store needs no changes: `@Published` slices are observed with Combine, and
/// every read goes through the same selectors the SwiftUI screen used.
///
/// NOT YET PORTED — the screen stays behind `-uikitActivity YES` until these land,
/// so the shipped default is unchanged:
///   - multi-select ("Select") and the bulk confirm / recategorize / delete bar
///   - the filter sheet's full surface (the button presents the SwiftUI sheet, but
///     the active-filter chips are not rendered)
///   - the Calendar view mode
///   - "Confirm all N pending"
final class ActivityFeedVC: UIViewController {

    private enum SectionID: Hashable {
        case pending
        case month(String)
        case empty
    }

    private var searchQuery = ""
    /// The app's own sort enum, reused — it carries `sorted(_:)`, so ordering is
    /// literally the same code the SwiftUI screen ran.
    private var sort: TxSort = .dateDesc
    private var cancellables = Set<AnyCancellable>()

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var txByID: [String: Tx] = [:]

    private let store = FinchStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Activity")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()

        store.$txns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: [Tx]) in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
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
            guard let self, let tx = self.txByID[id] else { return }
            var cfg = cell.defaultContentConfiguration()
            // Same rule as the SwiftUI TxRow: category is the title, date beneath.
            cfg.text = self.store.categoryName(tx.category) ?? String(localized: "Uncategorized")
            cfg.secondaryText = tx.date
            cell.contentConfiguration = cfg

            let amount = UILabel()
            amount.text = self.store.displayMoneyBase(tx.amount)
            amount.font = .preferredFont(forTextStyle: .body)
            amount.textColor = tx.amount < 0 ? .label : .systemGreen
            cell.accessories = [.customView(configuration: .init(customView: amount,
                                                                 placement: .trailing()))]
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, ip in
            guard let self else { return }
            var cfg = view.defaultContentConfiguration()
            let section = self.dataSource.snapshot().sectionIdentifiers[ip.section]
            switch section {
            case .pending:
                let n = self.dataSource.snapshot().numberOfItems(inSection: .pending)
                cfg.text = String(localized: "To confirm (\(n))")
            case .month(let key):
                cfg.text = MonthGrouping.label(key)
                let txns = self.dataSource.snapshot().itemIdentifiers(inSection: section)
                    .compactMap { self.txByID[$0] }
                cfg.secondaryText = "\(String(localized: "Income")) \(self.store.displayMoneyBase(MonthGrouping.income(txns)))"
                    + " · \(String(localized: "Spent")) \(self.store.displayMoneyBase(MonthGrouping.expense(txns)))"
            case .empty:
                cfg.text = String(localized: "Transactions")
            }
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, ip, id in cv.dequeueConfiguredReusableCell(using: cell, for: ip, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, ip in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: ip)
        }
    }

    /// The SwiftUI screen recomputed this inside `body`; here it is explicit. Same
    /// selector, so filtering and ordering stay identical.
    private func applySnapshot() {
        let all = store.txns
        let filtered = searchQuery.isEmpty ? all
            : Selectors.selectTransactions(all, ListOptions(ledgerId: store.activeLedgerId,
                                                            query: searchQuery))
        let txns = sort.sorted(filtered)
        txByID = Dictionary(uniqueKeysWithValues: txns.map { ($0.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        let pending = txns.filter { $0.pending == true }
        let confirmed = txns.filter { $0.pending != true }
        if !pending.isEmpty {
            snap.appendSections([.pending])
            snap.appendItems(pending.map(\.id), toSection: .pending)
        }
        if confirmed.isEmpty {
            snap.appendSections([.empty])
        } else {
            for section in MonthGrouping.sections(confirmed) {
                snap.appendSections([.month(section.id)])
                snap.appendItems(section.txns.map(\.id), toSection: .month(section.id))
            }
        }
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Bars

    private func configureSearch() {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = String(localized: "Search transactions")
        navigationItem.searchController = sc
        navigationItem.hidesSearchBarWhenScrolling = false   // matches displayMode: .always
    }

    private func configureToolbar() {
        let sortMenu = UIMenu(title: String(localized: "Sort"), children: TxSort.allCases.map { option in
            UIAction(title: String(localized: String.LocalizationValue(option.label)),
                     state: option == sort ? .on : .off) { [weak self] _ in
                self?.sort = option
                self?.configureToolbar()
                self?.applySnapshot()
            }
        })
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), menu: sortMenu),
        ]
    }

    private func swipeActions(at ip: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: ip), let tx = txByID[id] else { return nil }
        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { [weak self] _, _, done in
            // Same chokepoint helper the SwiftUI screen calls; it also unlinks receipts.
            do { try self?.store.deleteTransaction(tx.id); done(true) } catch { done(false) }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension ActivityFeedVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        cv.deselectItem(at: ip, animated: true)
        guard let id = dataSource.itemIdentifier(for: ip), let tx = txByID[id] else { return }
        present(UIHostingController(rootView:
            EditTransactionSheet(txn: tx)
                .environmentObject(store)
                .environmentObject(DeepLinkRouter.shared)
        ), animated: true)
    }
}

extension ActivityFeedVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}
#endif
