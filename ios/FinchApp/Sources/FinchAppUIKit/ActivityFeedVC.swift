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
/// Parity with the SwiftUI feed: pending bucket, month sections, search, sort,
/// filter (the SwiftUI sheet, hosted), group-by-month, 50-row pagination with
/// "Load more", multi-select with the bulk confirm / recategorize / delete bar,
/// "Confirm all N pending", add, edit, duplicate and swipe actions.
///
/// The query pipeline is not reimplemented: `filteredTxns()` builds the same
/// `ListOptions` and calls the same `Selectors.selectTransactions` with the same
/// category/tag name maps, then the same `TxSort.sorted`. Anything else would
/// drift from the SwiftUI screen the moment either changed.
///
/// STILL NOT PORTED (the flag stays until these land):
///   - the Calendar view mode
///   - saved searches (save / list / delete)
final class ActivityFeedVC: UIViewController {

    private enum SectionID: Hashable {
        case pending
        case month(String)
        case all          // group-by-month off: one flat section
        case empty
        case loadMore
    }

    /// Item ids are transaction ids; these two are sentinels for the non-row cells.
    private static let confirmAllID = "__confirm_all__"
    private static let loadMoreID = "__load_more__"

    private var searchQuery = ""
    /// The app's own sort enum, reused — it carries `sorted(_:)`, so ordering is
    /// literally the same code the SwiftUI screen ran.
    private var sort: TxSort = .dateDesc
    private var filter = TxFilter()
    private var visibleCount = 50
    private var hasMore = false
    private var isSelecting = false
    private var selected: Set<String> = []
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
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
            guard let self else { return }
            if id == Self.confirmAllID {
                var cfg = cell.defaultContentConfiguration()
                let n = self.dataSource.snapshot().numberOfItems(inSection: .pending) - 1
                cfg.text = String(localized: "Confirm all \(n) pending")
                cfg.image = UIImage(systemName: "checkmark.circle")
                cfg.textProperties.color = .tintColor
                cell.contentConfiguration = cfg
                cell.accessories = []
                return
            }
            if id == Self.loadMoreID {
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Load more")
                cfg.textProperties.color = .tintColor
                cell.contentConfiguration = cfg
                cell.accessories = []
                return
            }
            guard let tx = self.txByID[id] else { return }
            var cfg = cell.defaultContentConfiguration()
            // Same rule as the SwiftUI TxRow: category is the title, date beneath.
            cfg.text = self.store.categoryName(tx.category) ?? String(localized: "Uncategorized")
            cfg.secondaryText = tx.date
            cell.contentConfiguration = cfg

            let amount = UILabel()
            amount.text = self.store.displayMoneyBase(tx.amount)
            amount.font = .preferredFont(forTextStyle: .body)
            amount.textColor = tx.amount < 0 ? .label : .systemGreen
            var accessories: [UICellAccessory] = [
                .customView(configuration: .init(customView: amount, placement: .trailing()))
            ]
            if self.isSelecting {
                // Multi-select: a leading tick, driven by our own `selected` set so
                // the same rows can also be tapped to open in normal mode.
                let ticked = self.selected.contains(id)
                let mark = UIImageView(image: UIImage(systemName: ticked ? "checkmark.circle.fill" : "circle"))
                mark.tintColor = ticked ? .tintColor : .tertiaryLabel
                accessories.insert(.customView(configuration: .init(customView: mark, placement: .leading())), at: 0)
            }
            cell.accessories = accessories
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
            case .all:
                cfg.text = String(localized: "Transactions")
            case .empty:
                cfg.text = String(localized: "Transactions")
            case .loadMore:
                cfg.text = nil
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
    /// Same construction as the SwiftUI screen's `filteredTxns()`: same base,
    /// same ListOptions, same selector, same name maps, same sort.
    private func filteredTxns() -> [Tx] {
        let base = filter.counterpartyId.map {
            Selectors.merchantTransactions(store.txns, store.merchants, $0, store.activeLedgerId,
                                           includePending: true)
        } ?? store.txns
        let opts = ListOptions(
            ledgerId: store.activeLedgerId,
            direction: filter.direction,
            query: searchQuery.isEmpty ? nil : searchQuery,
            accountId: filter.accountId,
            categoryId: filter.categoryId,
            status: filter.status,
            from: filter.fromYMD,
            to: filter.toYMD,
            minAmount: filter.minAmount,
            maxAmount: filter.maxAmount,
            tagIds: filter.tagIds.isEmpty ? nil : Array(filter.tagIds),
            tagsMatchAll: filter.tagsMatchAll)
        return sort.sorted(Selectors.selectTransactions(
            base, opts,
            categoryNames: Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0.name) }),
            tagNames: Dictionary(uniqueKeysWithValues: store.tags.map { ($0.id, $0.name) })))
    }

    private func applySnapshot() {
        let txns = filteredTxns()
        txByID = Dictionary(uniqueKeysWithValues: txns.map { ($0.id, $0) })

        // Pending is pinned newest-first whatever the sort menu says — same rule.
        let pending = TxSort.dateDesc.sorted(txns.filter { $0.pending == true })
        let confirmed = txns.filter { $0.pending != true }
        hasMore = confirmed.count > visibleCount
        let page = Array(confirmed.prefix(visibleCount))

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        if !pending.isEmpty {
            snap.appendSections([.pending])
            snap.appendItems(pending.map(\.id) + [Self.confirmAllID], toSection: .pending)
        }
        if page.isEmpty {
            snap.appendSections([.empty])
        } else if groupByMonth {
            for section in MonthGrouping.sections(page) {
                snap.appendSections([.month(section.id)])
                snap.appendItems(section.txns.map(\.id), toSection: .month(section.id))
            }
        } else {
            snap.appendSections([.all])
            snap.appendItems(page.map(\.id), toSection: .all)
        }
        if hasMore {
            snap.appendSections([.loadMore])
            snap.appendItems([Self.loadMoreID], toSection: .loadMore)
        }
        dataSource.apply(snap, animatingDifferences: false)
        configureToolbar()
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
        guard !isSelecting else {
            // Selection mode: the bar collapses to Done, and the bulk actions take
            // the bottom bar — the same shape as the SwiftUI screen.
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: String(localized: "Done"), primaryAction: UIAction { [weak self] _ in
                    self?.setSelecting(false)
                })
            ]
            navigationController?.setToolbarHidden(false, animated: true)
            let n = selected.count
            toolbarItems = [
                UIBarButtonItem(title: String(localized: "Confirm \(n)"), primaryAction: UIAction { [weak self] _ in self?.bulkConfirm() }),
                .flexibleSpace(),
                UIBarButtonItem(title: String(localized: "Recategorize \(n)"), primaryAction: UIAction { [weak self] _ in self?.bulkRecategorize() }),
                .flexibleSpace(),
                UIBarButtonItem(title: String(localized: "Delete \(n)"), primaryAction: UIAction { [weak self] _ in self?.bulkDelete() }),
            ]
            toolbarItems?.forEach { $0.isEnabled = n > 0 }
            return
        }
        navigationController?.setToolbarHidden(true, animated: true)

        let sortMenu = UIMenu(title: String(localized: "Sort"), children: TxSort.allCases.map { option in
            UIAction(title: String(localized: String.LocalizationValue(option.label)),
                     state: option == sort ? .on : .off) { [weak self] _ in
                self?.sort = option
                self?.applySnapshot()
            }
        })
        let groupToggle = UIAction(title: String(localized: "Group by month"),
                                   state: groupByMonth ? .on : .off) { [weak self] _ in
            guard let self else { return }
            self.groupByMonth.toggle()
            self.applySnapshot()
        }
        let overflow = UIMenu(children: [sortMenu, groupToggle])

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: overflow),
            UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
                            primaryAction: UIAction { [weak self] _ in self?.presentFilter() }),
            UIBarButtonItem(title: String(localized: "Select"), primaryAction: UIAction { [weak self] _ in
                self?.setSelecting(true)
            }),
        ]
        navigationItem.leftItemsSupplementBackButton = true
    }

    // MARK: Selection + bulk actions — the same store calls the SwiftUI screen made

    private func setSelecting(_ on: Bool) {
        isSelecting = on
        selected.removeAll()
        configureToolbar()
        applySnapshot()
    }

    private func bulkConfirm() {
        run { for id in selected { try store.apply(.confirmTransaction, Args(["id": .string(id)])) } }
        setSelecting(false)
    }

    private func bulkDelete() {
        run { for id in selected { try store.deleteTransaction(id) } }   // also unlinks receipts
        setSelecting(false)
    }

    private func bulkRecategorize() {
        let ids = selected
        present(UIHostingController(rootView:
            BulkRecategorizeSheet(ids: Array(ids)) { [weak self] in self?.setSelecting(false) }
                .environmentObject(store)
                .environmentObject(DeepLinkRouter.shared)
        ), animated: true)
    }

    private func confirmAllPending() {
        run {
            for tx in store.txns where tx.pending == true {
                try store.apply(.confirmTransaction, Args(["id": .string(tx.id)]))
            }
        }
    }

    private func presentFilter() {
        // The filter UI stays SwiftUI — it is a sheet, so it never shadows.
        present(UIHostingController(rootView:
            FilterSheetHost(initial: filter) { [weak self] updated in
                self?.filter = updated
                self?.applySnapshot()
            }
            .environmentObject(store)
        ), animated: true)
    }

    /// Surfaces a rejected write as a localized alert rather than silently
    /// no-op'ing — the SwiftUI screen's `run(_:)`.
    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
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
        guard let id = dataSource.itemIdentifier(for: ip) else { return }
        if id == Self.confirmAllID { confirmAllPending(); return }
        if id == Self.loadMoreID { visibleCount += 50; applySnapshot(); return }
        if isSelecting {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            configureToolbar()
            applySnapshot()
            return
        }
        guard let tx = txByID[id] else { return }
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

/// The filter UI is the app's own SwiftUI sheet; this only bridges its `@Binding`
/// back to the view controller when the sheet closes.
private struct FilterSheetHost: View {
    @State private var filter: TxFilter
    let onChange: (TxFilter) -> Void

    init(initial: TxFilter, onChange: @escaping (TxFilter) -> Void) {
        _filter = State(initialValue: initial)
        self.onChange = onChange
    }

    var body: some View {
        TransactionFilterSheet(filter: $filter)
            .onChange(of: filter) { _, new in onChange(new) }
    }
}
#endif
