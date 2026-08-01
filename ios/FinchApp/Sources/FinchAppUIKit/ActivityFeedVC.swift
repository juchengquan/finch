#if os(iOS)
import UIKit
import SwiftUI
import Combine
import QuickLook
import FinchCore

/// Phase 2, screen 1: `ActivityFeedView` converted to UIKit.
///
/// **Two modes, as of Phase 3b step 4.** `onSelect == nil` is the original pushed
/// screen — reached from Accounts → All Transactions on iPhone — where tapping a row
/// opens the edit sheet. Non-nil makes it the iPad supplementary COLUMN: a tap reports
/// the id and the row stays selected, driving the shell's detail column.
///
/// Activity is the odd one in Phase 3b: it has **no compact tab root** to convert
/// (`RootTabBarController.slots` has no `.activity` — the feed lives inside Accounts),
/// so unlike Ledger/Budgets/Scheduled there is no "root and column together" pairing.
/// The compact path was already native from Phase 2; this step only adds the column.
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
/// DELIBERATELY STILL SWIFTUI (not a gap — this is the intended end state):
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

        /// The picker, the chip row and the grid are bare rows in the SwiftUI
        /// screen — no `Section` header. Reserving header space for them (which a
        /// uniform `.supplementary` config does) added ~17pt above the picker.
        var wantsHeader: Bool {
            switch self {
            case .modePicker, .savedSearch, .calendar, .loadMore: return false
            default: return true
            }
        }
    }

    private enum ViewMode { case list, calendar }

    /// Item ids are transaction ids; these two are sentinels for the non-row cells.
    private static let confirmAllID = "__confirm_all__"
    private static let loadMoreID = "__load_more__"
    /// Appears in the `.empty` section only while the launch txns projection is in
    /// flight, so it can never collide with a transaction id. See TxnsLoadingCell.
    private static let loadingID = "__loading__"
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
    /// Staged for QuickLook, which reads its item from the data source.
    private var previewURL: URL?
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    private var cancellables = Set<AnyCancellable>()
    /// Pings `TabChromeVC` when multi-select toggles, so the hosted floating `+`
    /// gets out of the bulk-action bar's way. The SwiftUI screen did this with a
    /// `SelectionActiveKey` preference, which a UIKit screen cannot publish.
    private let fabState = PassthroughSubject<Void, Never>()

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var txByID: [String: Tx] = [:]
    /// Section order and header text, both computed in `applySnapshot` and set BEFORE
    /// the apply — see `configureHeader` for why they cannot be derived on demand.
    private var sectionIDs: [SectionID] = []
    private struct HeaderContent { var title: String?; var subtitle: String? }
    private var headerContent: [SectionID: HeaderContent] = [:]

    private let store = FinchStore.shared

    /// Selection mode. `nil` → the pushed screen: a row opens the edit sheet. Non-nil →
    /// this feed is a split view's supplementary column, so a row reports its id and
    /// stays selected instead. Same seam as `LedgersVC` / `BudgetsListVC` /
    /// `ScheduledListVC`; `String?` so deleting the selected row can clear the column.
    private let onSelect: ((String?) -> Void)?
    /// The row to show as selected, when a split view owns the selection.
    var selectedID: String? {
        didSet { guard selectedID != oldValue else { return }; reassertSelection() }
    }

    init(onSelect: ((String?) -> Void)? = nil) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Activity")
        // Large, collapsing to inline on scroll — what `.navigationTitle("Activity")`
        // gives the SwiftUI screen, which sets no display mode and so inherits the
        // navigation controller's `prefersLargeTitles`. Phase 2 pinned every converted
        // screen to `.never`, which silently dropped that on the feed.
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()

        store.$txns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: [Tx]) in self?.applySnapshot() }
            .store(in: &cancellables)
        // Removes the loading row when the projection lands on an empty ledger, where
        // `$txns` publishes [] → [] and cannot distinguish the two states.
        TxnsLoadingCell.observe(store) { [weak self] in self?.applySnapshot() }
            .store(in: &cancellables)
        // Hide-amounts is not `$txns`, so without this a toggle left the month
        // headers' income/spent and the calendar's `masked:` on their old values —
        // both are read when the cells are configured.
        store.$privacyMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)

        // A one-shot filter handed over from elsewhere ("show me this account's
        // transactions"), mirroring `ActivityFeedView.consumePendingFilter`.
        //
        // NOTE: nothing in the app writes `router.pendingFilter` today — grep finds the
        // declaration and the two consumers and no producer at all. This is carried for
        // parity so the native column behaves like the SwiftUI one the day a writer is
        // added, rather than being a silently missing feature then.
        DeepLinkRouter.shared.$pendingFilter
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                guard let self else { return }
                self.searchQuery = ""
                self.filter = pending
                DeepLinkRouter.shared.pendingFilter = nil
                self.applySnapshot()
            }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        // Per-section header mode, as AccountDetailVC does — a single
        // `.list(using:)` config applies `.supplementary` to every section, which
        // reserves header space above the bare rows. `sectionIDs` is set before each
        // apply, so the provider can ask what kind of section it is laying out.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            config.headerMode = (kind?.wantsHeader ?? true) ? .supplementary : .none
            config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.rowActions(at: ip).map { $0.actions.leading($0.tx) }
            }
            config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.rowActions(at: ip).map { $0.actions.trailing($0.tx) }
            }
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
            // The picker's own section padding, not just the row's margin: an
            // insetGrouped section pads top and bottom on top of the inter-section
            // spacing, which is most of the gap under the toggle. Zeroing the top
            // and handing the bottom to the token is what makes the token actually
            // control the distance to the content it switches.
            if kind == .modePicker {
                section.contentInsets.top = 0
                section.contentInsets.bottom = Metrics.modePickerBottomGap
            }
            return section
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
            if id == Self.loadingID {
                TxnsLoadingCell.configure(cell)
                return
            }
            if id == Self.confirmAllID {
                let n = self.dataSource.snapshot().numberOfItems(inSection: .pending) - 1
                let title = String(localized: "Confirm all \(n) pending")
                // Hosted rather than a `defaultContentConfiguration` so it announces as
                // a BUTTON, which is what the SwiftUI screen's `Button` gives. A content
                // configuration owns the cell's accessibility, so setting the trait on
                // the cell afterwards does nothing — this row read as plain text while
                // the control read it as a button. Same fix as the Accounts screen's
                // All Transactions row.
                cell.contentConfiguration = UIHostingConfiguration {
                    Label(title, systemImage: "checkmark.circle")
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                }
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
                // No card behind it. An insetGrouped list gives every cell the
                // grouped background, which wrapped the picker in a white rounded
                // card the SwiftUI row doesn't have — and cost ~20pt of vertical
                // rhythm, pushing everything below it down.
                .margins(.top, 0)
                .margins(.bottom, Metrics.modePickerBottomGap)
                cell.backgroundConfiguration = .clear()
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
                        format: { self.store.displayExactBase($0) },
                        masked: self.store.privacyMode)
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
            // The SwiftUI row itself, hosted — it draws the amount, so no trailing
            // accessory. `showRunningBalance: false` because this feed mixes accounts
            // and a running balance only reads sensibly within one.
            //
            // Every row prints its own date and time. The feed used to print the date
            // once per day-run, which also swallowed the TIME — several transactions
            // on one day rendered as identical rows with no way to tell them apart or
            // order them. Every other screen already showed all of them.
            if self.onSelect == nil { cell.backgroundConfiguration = txRowBackground() }
            TxRowCell.configure(cell, tx: tx, store: self.store,
                                showRunningBalance: false,
                                onPreviewReceipt: self.isSelecting ? nil
                                    : { [weak self] in self?.previewReceipt($0) })
            var accessories: [UICellAccessory] = []
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
            self?.configureHeader(view, at: ip)
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, ip, id in cv.dequeueConfiguredReusableCell(using: cell, for: ip, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, ip in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: ip)
        }
    }

    private func monthHeader(_ key: String, _ txns: [Tx]) -> HeaderContent {
        HeaderContent(
            title: MonthGrouping.label(key),
            subtitle: "\(String(localized: "Income")) \(store.displayMoneyBase(MonthGrouping.income(txns)))"
                + " · \(String(localized: "Spent")) \(store.displayMoneyBase(MonthGrouping.expense(txns)))")
    }

    /// Reads text computed in `applySnapshot`, and deliberately does NOT recompute it
    /// from `dataSource.snapshot()`: that returns the PRE-apply sections while an
    /// apply is in flight, which made every header one generation stale (confirming a
    /// row moved it into its month but left the month's income/spent unchanged).
    /// Verified on the simulator; it survived a re-dequeue, which ruled out a
    /// display-refresh cause.
    private func configureHeader(_ view: UICollectionViewListCell, at ip: IndexPath) {
        guard sectionIDs.indices.contains(ip.section) else { return }
        var cfg = view.defaultContentConfiguration()
        if let content = headerContent[sectionIDs[ip.section]] {
            cfg.text = content.title
            cfg.secondaryText = content.subtitle
        }
        view.contentConfiguration = cfg
    }

    /// A diffable data source does NOT re-render a supplementary view when only the
    /// section's ITEMS change — the section identifier is unchanged, so the header
    /// stays exactly as it was. The month headers here show income/spent computed
    /// FROM those rows, and the pending header shows a count, so deleting a row or
    /// flipping its status left the figures stale. SwiftUI recomputed them for free.
    /// Only the visible headers are refreshed, to stay off `reloadSections` — which
    /// would re-render every row in the section.

    /// Clear a highlight that outlived its row's position.
    ///
    /// Tapping a swipe action highlights the cell. Diffable MOVES that cell to its
    /// new index path rather than re-dequeuing it, so `prepareForReuse` never fires
    /// and the highlight arrives with the row — the arriving row rendered grey for
    /// ~0.5s before de-highlighting, which reads as a blink (see #702).
    private func clearStuckHighlight() {
        for cell in collectionView.visibleCells where cell.isHighlighted {
            cell.isHighlighted = false
        }
    }

    private func refreshVisibleHeaders() {
        let kind = UICollectionView.elementKindSectionHeader
        for ip in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            guard let view = collectionView.supplementaryView(forElementKind: kind, at: ip)
                    as? UICollectionViewListCell else { continue }
            configureHeader(view, at: ip)
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
        var headers: [SectionID: HeaderContent] = [:]
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
                headers[.day(day)] = HeaderContent(title: MonthCashCalendar.pretty(day))
            } else {
                let key = String(format: "%04d-%02d",
                                 AppDate.civil.component(.year, from: calMonthAnchor),
                                 AppDate.civil.component(.month, from: calMonthAnchor))
                let monthTx = txns.filter { $0.date.hasPrefix(key) }
                if !monthTx.isEmpty {
                    snap.appendSections([.month(key)])
                    snap.appendItems(monthTx.map(\.id), toSection: .month(key))
                    headers[.month(key)] = monthHeader(key, monthTx)
                }
            }
            let carried = Set(dataSource.snapshot().itemIdentifiers)
            snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
            headerContent = headers
            sectionIDs = snap.sectionIdentifiers
            dataSource.apply(snap, animatingDifferences: false) { [weak self] in
                self?.refreshVisibleHeaders()
            self?.clearStuckHighlight()
            }
            configureToolbar()
            return
        }

        // Only when there is something to show. The SwiftUI screen gates this the same
        // way (`if !saved.isEmpty || filter.isActive`); appending it unconditionally put
        // an empty chip row above every feed, which is not a row this screen ever had.
        // `filter.isActive` keeps the "＋ Save" affordance reachable once the user has
        // narrowed the list — that is the only way to create the first saved search.
        if !savedSearches.all(ledgerId: store.activeLedgerId).isEmpty || filter.isActive {
            snap.appendSections([.savedSearch])
            snap.appendItems([Self.savedSearchID], toSection: .savedSearch)
        }

        if !pending.isEmpty {
            snap.appendSections([.pending])
            snap.appendItems(pending.map(\.id) + [Self.confirmAllID], toSection: .pending)
            // The count excludes the "Confirm all" row that shares the section.
            headers[.pending] = HeaderContent(title: String(localized: "To confirm (\(pending.count))"))
        }
        if page.isEmpty {
            snap.appendSections([.empty])
            headers[.empty] = HeaderContent(title: String(localized: "Transactions"))
            // At launch the feed is empty because the projection has not landed, not
            // because the ledger is — spin rather than present a bare "Transactions".
            if TxnsLoadingCell.shouldSpin(store, searchQuery: searchQuery) {
                snap.appendItems([Self.loadingID], toSection: .empty)
            }
        } else if groupByMonth {
            for section in MonthGrouping.sections(page) {
                snap.appendSections([.month(section.id)])
                snap.appendItems(section.txns.map(\.id), toSection: .month(section.id))
                headers[.month(section.id)] = monthHeader(section.id, section.txns)
            }
        } else {
            snap.appendSections([.all])
            snap.appendItems(page.map(\.id), toSection: .all)
            headers[.all] = HeaderContent(title: String(localized: "Transactions"))
        }
        if hasMore {
            snap.appendSections([.loadMore])
            snap.appendItems([Self.loadMoreID], toSection: .loadMore)
        }
        // Diffable keeps the EXISTING cell for an unchanged item identifier, so a row
        // whose data changed — an edited amount, a new category, a recomputed figure —
        // would keep drawing the old values until it happened to be re-dequeued.
        // Reconfiguring the carried-over items re-runs the cell provider, and only for
        // the visible ones, so this is not a reload.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        headerContent = headers
        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false) { [weak self] in
            self?.refreshVisibleHeaders()
            self?.clearStuckHighlight()
            // `apply` clears the selection, so in column mode the row would stop
            // looking selected every time a figure changed underneath it.
            self?.reassertSelection()
        }
        dropSelectionIfGone()
        configureToolbar()
    }

    // MARK: Bars

    private func configureSearch() {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        // Plain "Search" everywhere, matching the SwiftUI screens and the other
        // converted ones — the bar sits under a title that already says what is
        // being searched.
        sc.searchBar.placeholder = String(localized: "Search")
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
        fabState.send()
    }

    private func bulkConfirm() {
        report(store.confirmTransactions(Array(selected)), of: selected.count)
        setSelecting(false)
    }

    private func bulkDelete() {
        report(store.deleteTransactions(Array(selected)), of: selected.count)   // also unlinks receipts
        setSelecting(false)
    }

    /// One write for the whole selection, so a row the engine rejects is skipped
    /// rather than abandoning the rest — which means the shortfall has to be said
    /// out loud, or a silently-skipped row looks like it worked.
    private func report(_ applied: Int, of requested: Int) {
        guard applied < requested else { return }
        let alert = UIAlertController(title: String(localized: "Data problem"),
                                      message: String(localized: "\(requested - applied) of \(requested) couldn't be applied."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
        present(alert, animated: true)
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

    /// The row's gestures come from the shared `TxRowActions`, so this feed and the
    /// account detail cannot drift apart — the whole reason the SwiftUI side keeps
    /// `TxnSwipeActions` in one place. This screen previously offered a bare
    /// Delete: no Duplicate, no status toggle, no confirmation step.
    private func rowActions(at ip: IndexPath) -> (tx: Tx, actions: TxRowActions)? {
        guard let id = dataSource.itemIdentifier(for: ip), let tx = txByID[id] else { return nil }
        var actions = TxRowActions(
            duplicate: { [weak self] tx in self?.presentDuplicate(tx) },
            requestDelete: { [weak self] tx in self?.confirmDeleteTransaction(tx) },
            toggleStatus: { [weak self] tx in
                guard let self else { return }
                self.run { try txnToggleStatus(tx, store: self.store) }
            },
            edit: { [weak self] tx in self?.presentEditTransaction(tx) },
            previewReceipt: { [weak self] tx in self?.previewReceipt(tx) })
        // The item is omitted when the row has no attachment, as in SwiftUI.
        if store.attachments(for: tx.id).isEmpty { actions.previewReceipt = nil }
        return (tx, actions)
    }

    /// Centered alert, not a row-anchored sheet: the row is torn down when the swipe
    /// collapses or the cell recycles, which would take a popout with it.
    private func confirmDeleteTransaction(_ tx: Tx) {
        let alert = UIAlertController(title: String(localized: "Delete transaction?"),
                                      message: "\(tx.merchant) · \(store.displayMoneyBase(tx.amount))",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            // Same chokepoint helper the SwiftUI screen calls; it also unlinks receipts.
            self.run { try self.store.deleteTransaction(tx.id); Haptics.warning() }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func presentEditTransaction(_ tx: Tx) {
        present(UIHostingController(rootView:
            EditTransactionSheet(txn: tx)
                .environmentObject(store)
                .environmentObject(DeepLinkRouter.shared)
        ), animated: true)
    }

    /// Duplicate opens the Add sheet pre-filled; nothing is written until Save.
    private func presentDuplicate(_ tx: Tx) {
        present(UIHostingController(rootView:
            AddTransactionSheet(prefill: tx)
                .environmentObject(store)
                .environmentObject(DeepLinkRouter.shared)
        ), animated: true)
    }

    /// The SwiftUI screen's `.quickLookPreview($previewURL)`.
    private func previewReceipt(_ tx: Tx) {
        guard let first = store.attachments(for: tx.id).first else { return }
        previewURL = store.attachmentURL(for: first)
        let preview = QLPreviewController()
        preview.dataSource = self
        present(preview, animated: true)
    }
}

extension ActivityFeedVC: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewURL ?? URL(fileURLWithPath: "/")) as NSURL
    }
}

extension ActivityFeedVC: UICollectionViewDelegate {
    /// Cells that host an interactive SwiftUI control must not be selectable, or the
    /// cell's own selection swallows the touch and the control never sees it — the
    /// mode picker looked inert for exactly this reason.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt ip: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: ip) else { return true }
        return id != Self.modePickerID && id != Self.savedSearchID && id != Self.calendarID
            && id != Self.loadingID   // a spinner, not a row
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
        if let onSelect {
            // Stay selected: the row is the current state of the column beside it, not
            // a button that fired. (Re-selecting because the guard above deselected.)
            selectedID = id
            cv.selectItem(at: ip, animated: false, scrollPosition: [])
            onSelect(id)
            return
        }
        presentEditTransaction(tx)
    }

    /// Clear the column when the selected transaction stops existing — deleted from a
    /// row action, from the bulk bar, or on another device via sync. Done here, off the
    /// snapshot, rather than in each delete path: there are three of them and a
    /// stale-id detail column is the same bug however the row went away.
    private func dropSelectionIfGone() {
        guard let onSelect, let id = selectedID else { return }
        guard !store.txns.contains(where: { $0.id == id }) else { return }
        selectedID = nil
        onSelect(nil)
    }

    /// Restore the highlight after a snapshot apply or an external selection change.
    /// No-op outside column mode, where nothing owns a persistent selection.
    private func reassertSelection() {
        guard onSelect != nil else { return }
        // Same trap as the sibling lists: `selectedID` can be set by the split shell
        // before this view loads, and `dataSource` is nil until `viewDidLoad`.
        guard dataSource != nil else { return }
        guard let selectedID, let ip = dataSource.indexPath(for: selectedID) else { return }
        collectionView.selectItem(at: ip, animated: false, scrollPosition: [])
    }

    /// Right-click on Mac/iPad and long-press on touch — swipe is touch-only, so the
    /// SwiftUI row carried the same actions in a context menu.
    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt ip: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isSelecting, let row = rowActions(at: ip) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            row.actions.menu(row.tx)
        }
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
                        // Long-press is the ONLY way to delete a chip, and VoiceOver
                        // does not surface a context menu — so without this a VoiceOver
                        // user can create saved searches and never remove one. Mirrored
                        // in ActivityTab's chip row, which has the same shape.
                        .accessibilityAction(named: Text(String(localized: "Delete"))) { onDelete(s) }
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
/// The converted feed hides the floating `+` during multi-select, where the
/// bulk-action bar occupies the same corner. The SwiftUI screen publishes
/// `SelectionActiveKey`; this is the native equivalent.
extension ActivityFeedVC: AddTxFABProviding {
    var hidesAddTxFAB: Bool { isSelecting }
    var addTxFABStateDidChange: AnyPublisher<Void, Never> { fabState.eraseToAnyPublisher() }
}

#endif
