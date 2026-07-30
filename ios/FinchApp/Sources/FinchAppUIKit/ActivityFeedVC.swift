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
/// The Calendar grid and the saved-search chips stay SwiftUI, hosted in cells via
/// `UIHostingConfiguration` — they are leaf views with no navigation, which is
/// where SwiftUI is strongest. Crucially the `UICollectionView` remains the
/// screen's scroll view: hosting the whole calendar mode as a SwiftUI list would
/// put a SwiftUI scroll view in a pushed page, which is reproducer B and shadows.
final class ActivityFeedVC: UIViewController {

    private enum SectionID: Hashable {
        case modePicker   // List | Calendar, the list's first row as in SwiftUI
        case savedSearch  // the chip row
        case calendar     // the month grid
        case day(String)  // calendar mode: the selected day's rows
        case pending
        case month(String)
        case all          // group-by-month off: one flat section
        case empty
        case loadMore
    }

    private enum ViewMode { case list, calendar }

    /// Item ids are transaction ids; these two are sentinels for the non-row cells.
    private static let confirmAllID = "__confirm_all__"
    private static let loadMoreID = "__load_more__"
    private static let modePickerID = "__mode_picker__"
    private static let savedSearchID = "__saved_searches__"
    private static let calendarID = "__calendar__"

    private var searchQuery = ""
    /// The app's own sort enum, reused — it carries `sorted(_:)`, so ordering is
    /// literally the same code the SwiftUI screen ran.
    private var sort: TxSort = .dateDesc
    private var filter = TxFilter()
    private var visibleCount = 50
    private var hasMore = false
    private var isSelecting = false
    private var selected: Set<String> = []
    private var viewMode: ViewMode = .list
    private var calMonthAnchor = MonthCashCalendar.firstOfMonth(forISO: nil)
    private var calSelectedDay: String?
    private let savedSearches = SavedSearchStore()
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
            if id == Self.modePickerID {
                // The picker is the list's FIRST ROW, not a nav-bar title view —
                // same reason as the SwiftUI screen: it keeps the collection view
                // the primary scroll view so the large title behaves.
                cell.contentConfiguration = UIHostingConfiguration {
                    Picker("", selection: Binding(
                        get: { self.viewMode },
                        set: { self.viewMode = $0; self.calSelectedDay = nil; self.applySnapshot() })) {
                        Text(String(localized: "List")).tag(ViewMode.list)
                        Text(String(localized: "Calendar")).tag(ViewMode.calendar)
                    }
                    .pickerStyle(.segmented)
                }
                cell.accessories = []
                return
            }
            if id == Self.savedSearchID {
                cell.contentConfiguration = UIHostingConfiguration {
                    SavedSearchChips(
                        searches: self.savedSearches.all(ledgerId: self.store.activeLedgerId),
                        onApply: { [weak self] s in
                            self?.filter = s.filter
                            self?.applySnapshot()
                        },
                        onDelete: { [weak self] s in
                            self?.savedSearches.remove(s.id)
                            self?.applySnapshot()
                        },
                        onSave: { [weak self] in self?.promptSaveSearch() })
                }
                cell.accessories = []
                return
            }
            if id == Self.calendarID {
                cell.contentConfiguration = UIHostingConfiguration {
                    MonthCashCalendar(
                        monthAnchor: Binding(get: { self.calMonthAnchor },
                                             set: { self.calMonthAnchor = $0; self.applySnapshot() }),
                        selectedDay: Binding(get: { self.calSelectedDay },
                                             set: { self.calSelectedDay = $0; self.applySnapshot() }),
                        wallToday: self.store.wallToday,
                        amountsForRange: { from, through in
                            MonthGrouping.dailyIncomeExpense(
                                self.filteredTxns().filter { $0.date >= from && $0.date <= through })
                        },
                        format: { self.store.displayExactBase($0) })
                }
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
            case .day(let day):
                cfg.text = MonthCashCalendar.pretty(day)
            case .modePicker, .savedSearch, .calendar, .loadMore:
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
        snap.appendSections([.modePicker])
        snap.appendItems([Self.modePickerID], toSection: .modePicker)

        if viewMode == .calendar {
            snap.appendSections([.calendar])
            snap.appendItems([Self.calendarID], toSection: .calendar)
            // The rows under the grid: the selected day, or the whole anchored
            // month — always the same filtered set the grid sums, so the cells and
            // the rows cannot disagree.
            if let day = calSelectedDay {
                let dayTx = txns.filter { $0.date == day }
                snap.appendSections([.day(day)])
                snap.appendItems(dayTx.map(\.id), toSection: .day(day))
            } else {
                let key = String(format: "%04d-%02d",
                                 AppDate.civil.component(.year, from: calMonthAnchor),
                                 AppDate.civil.component(.month, from: calMonthAnchor))
                let monthTx = txns.filter { $0.date.hasPrefix(key) }
                if !monthTx.isEmpty {
                    snap.appendSections([.month(key)])
                    snap.appendItems(monthTx.map(\.id), toSection: .month(key))
                }
            }
            dataSource.apply(snap, animatingDifferences: false)
            configureToolbar()
            return
        }

        snap.appendSections([.savedSearch])
        snap.appendItems([Self.savedSearchID], toSection: .savedSearch)

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

    /// The SwiftUI screen used an `.alert` with a `TextField`; same shape here.
    private func promptSaveSearch() {
        let alert = UIAlertController(title: String(localized: "Save search"),
                                      message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = String(localized: "Name") }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Save"), style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text, !name.isEmpty else { return }
            self.savedSearches.save(name: name, filter: self.filter, ledgerId: self.store.activeLedgerId)
            self.applySnapshot()
        })
        present(alert, animated: true)
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
    /// Cells that host an interactive SwiftUI control must not be selectable, or the
    /// cell's own selection swallows the touch and the control never sees it — the
    /// mode picker looked inert for exactly this reason.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt ip: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: ip) else { return true }
        return id != Self.modePickerID && id != Self.savedSearchID && id != Self.calendarID
    }

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

/// The saved-search chip row: a leaf view, so it stays SwiftUI and rides in a cell.
/// Long-press a chip to delete, matching the SwiftUI screen's context menu.
private struct SavedSearchChips: View {
    let searches: [SavedSearch]
    let onApply: (SavedSearch) -> Void
    let onDelete: (SavedSearch) -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searches) { s in
                    Button { onApply(s) } label: { chip(s.name) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { onDelete(s) } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                }
                Button { onSave() } label: { chip(String(localized: "＋ Save")) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
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
