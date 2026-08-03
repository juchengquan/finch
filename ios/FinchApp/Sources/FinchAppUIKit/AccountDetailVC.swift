#if os(iOS)
import UIKit
import SwiftUI
import Combine
import QuickLook
import FinchCore

/// Phase 2, screen 2: `AccountDetailView` converted to UIKit — now at parity.
///
/// Lifted from the migration pilot (`exp/uikit-pilot-account-detail`), where it was
/// written to measure conversion effort, then finished here. Same patterns as
/// `ActivityFeedVC`: `UICollectionView` list config + a diffable data source for
/// the holdings / pending / month sections, `UISearchController`,
/// `UISwipeActionsConfiguration`, `UIMenu`, and sheets left in SwiftUI behind
/// `UIHostingController`.
///
/// Two things are hosted rather than rebuilt, both LEAF views with no scroll view
/// of their own: the List/Calendar picker and `MonthCashCalendar`. Hosting a
/// screen's whole scroll view is what brings the iOS 26 resume shadow back (see
/// `ios/docs/ios26-shadow-variant-matrix.md`, reproducer B); hosting leaves does
/// not, because the `UICollectionView` remains the scroll view.
final class AccountDetailVC: UIViewController {

    // MARK: Model

    private let accountId: String
    private let store = FinchStore.shared
    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }
    private var searchQuery = ""
    private var cancellables = Set<AnyCancellable>()

    // The SwiftUI screen read these through `@AppStorage`; the wrapper works
    // outside a `View` (it is just UserDefaults underneath) — it simply no longer
    // invalidates anything, so the reads happen inside `applySnapshot`.
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    @AppStorage(ReconcileReminder.key) private var reconcileStaleDays = ReconcileReminder.defaultDays

    /// Calendar lens: the shared `MonthCashCalendar` with IN/OUT semantics — at
    /// single-account grain the honest reading is a bank statement's credits and
    /// debits, so transfers count on the side they move. Hence the footer.
    private enum ViewMode { case list, calendar }
    private var viewMode: ViewMode = .list
    private var calMonthAnchor = MonthCashCalendar.firstOfMonth(forISO: nil)
    private var calSelectedDay: String?

    private enum SectionID: Hashable {
        case balance        // account balance + reconcile seal, formerly the titleView
        case modePicker
        case holdings
        case calendar
        case pending
        case month(String)      // list mode: label · net · end-of-month balance
        case calMonth(String)   // calendar fallback: label · net only (see below)
        case day(String)
        case all
        case empty

        /// The picker and the grid are bare rows in SwiftUI — no `Section` header.
        var wantsHeader: Bool {
            switch self {
            case .balance, .modePicker, .calendar: return false
            default: return true
            }
        }
        /// Only the grid carries the in/out explanation.
        var wantsFooter: Bool {
            if case .calendar = self { return true }
            return false
        }
    }

    private static let modePickerID = "__mode_picker__"
    private static let calendarID = "__calendar__"
    private static let balanceID = "__balance__"
    private static let emptyID = "__empty__"
    private static let emptyDayID = "__empty_day__"
    private static let holdingPrefix = "__holding__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    /// Diffable wants Hashable ids, so the source of truth stays `Tx` keyed by id.
    private var txByID: [String: Tx] = [:]
    private var holdingByID: [String: Holding] = [:]
    /// The layout's section provider needs the section kinds, and querying the
    /// data source's snapshot from inside that closure races `apply`. Keep the
    /// order here and set it BEFORE applying.
    private var sectionIDs: [SectionID] = []

    /// Header text is computed in `applySnapshot` and read back here, NOT recomputed
    /// from `dataSource.snapshot()` inside the header registration. Reading the
    /// snapshot there returns the PRE-apply sections while an apply is in flight, so
    /// every figure came out one generation stale: confirming a transaction moved the
    /// row into its month but left the month's net, income/spent and end-of-month
    /// balance showing the values from before the move. Verified on the simulator —
    /// it survived a re-dequeue, which is what ruled out a display-refresh cause.
    private enum HeaderContent {
        case plain(String?)
        case month(label: String, trailing: String, subtitle: String?)
        /// Net, in, out on one row under the month name.
        case figures(label: String, figures: [MonthHeaderFigures.Figure], spoken: String)
    }
    private var headerContent: [SectionID: HeaderContent] = [:]

    private var previewURL: URL?
    private var moreItem: UIBarButtonItem?

    init(accountId: String) {
        self.accountId = accountId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Inline, with the balance in a two-line `titleView` (see updateTitleView) —
        // the same thing the SwiftUI screen has always shown, now on every OS
        // version rather than only iOS 26.
        //
        // The old note here said a large title and a custom titleView cannot share
        // the bar, which is why the balance had been moved into a content card. True
        // — but it only bites while the title is LARGE. Inline, the titleView is the
        // ordinary way to do this and needs no new API, so the iOS 26 subtitle work
        // is gone along with its availability fork.
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        updateTitleView()
        applySnapshot()

        // The SwiftUI store needs no rewrite: 18 @Published properties, observed
        // here with Combine instead of by the view-update system.
        store.$txns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySnapshot()
                self?.updateTitleView()   // the balance moves with the rows
            }
            .store(in: &cancellables)
        // Clears the launch spinner on a ledger with no transactions, where `$txns`
        // publishes [] → [] and cannot distinguish the two states. See TxnsLoadingCell.
        TxnsLoadingCell.observe(store) { [weak self] in self?.applySnapshot() }
            .store(in: &cancellables)
        store.$holdings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
        store.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // The SwiftUI screen re-resolved the account by id and dismissed
                // when it vanished, which is how Archive and Delete leave the
                // page. Same rule here.
                guard self.account != nil else {
                    self.navigationController?.popViewController(animated: true)
                    return
                }
                self.updateTitleView()
                self.applySnapshot()
            }
            .store(in: &cancellables)

        // Hide-amounts is not one of the slices above, so without this the screen
        // kept rendering figures after a toggle — the balance in the bar, the row
        // amounts and the calendar's `masked:` all read the flag when they are
        // built. `updateTitleView` as well as the snapshot: the balance lives in
        // the navigation item, which no snapshot touches.
        store.$privacyMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTitleView()
                self?.applySnapshot()
            }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        // Per-section header/footer, so the picker and the grid stay bare and only
        // the grid gets the explanatory footer — the SwiftUI `Section` shape.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            config.headerMode = (kind?.wantsHeader ?? true) ? .supplementary : .none
            if kind?.wantsFooter == true { config.footerMode = .supplementary }
            config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.swipe(at: ip)?.leading
            }
            config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.swipe(at: ip)?.trailing
            }
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
            // The picker is the first section and sits right under the search bar.
            // An insetGrouped list opens with a ~35pt top inset meant to separate a
            // first section from a large title — and this screen has no large title
            // (the bar carries name-over-balance instead), so that space just read as
            // a hole. Matches the gap on All Transactions.
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

            if id == Self.modePickerID {
                // The picker is the list's FIRST ROW, not a title view — same reason
                // as the SwiftUI screen: it keeps the collection view the primary
                // scroll view so the nav bar behaves.
                cell.contentConfiguration = UIHostingConfiguration {
                    Picker("", selection: Binding(
                        get: { self.viewMode },
                        set: { self.viewMode = $0; self.calSelectedDay = nil; self.applySnapshot() })) {
                        Text(String(localized: "List")).tag(ViewMode.list)
                        Text(String(localized: "Calendar")).tag(ViewMode.calendar)
                    }
                    .pickerStyle(.segmented)
                }
                // No card behind it — same as ActivityFeedVC's identical picker.
                .margins(.top, 0)
                .margins(.bottom, Metrics.modePickerBottomGap)
                cell.backgroundConfiguration = .clear()
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
                                self.visibleTxns().filter { $0.date >= from && $0.date <= through })
                        },
                        format: { self.store.displayExactBase($0) },
                        masked: self.store.privacyMode)
                }
                cell.accessories = []
                return
            }

            if id == Self.balanceID {
                guard let account = self.account else { return }
                self.configureBalanceCell(cell, account)
                return
            }

            if id == Self.emptyID || id == Self.emptyDayID {
                // The balance header above is already correct — it reads the stored
                // current_balance column, not this list — so only the rows wait.
                if TxnsLoadingCell.shouldSpin(self.store, searchQuery: self.searchQuery) {
                    TxnsLoadingCell.configure(cell)
                    return
                }
                var cfg = cell.defaultContentConfiguration()
                cfg.text = id == Self.emptyDayID
                    ? String(localized: "No transactions.")
                    : (self.searchQuery.isEmpty ? String(localized: "No transactions")
                                                : String(localized: "No matching transactions"))
                cfg.textProperties.font = .preferredFont(forTextStyle: .caption1)
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg
                cell.accessories = []
                return
            }

            if let holding = self.holdingByID[id] {
                var cfg = cell.defaultContentConfiguration()
                cfg.text = holding.symbol
                cell.contentConfiguration = cfg
                let value = UILabel()
                value.text = Selectors.holdingValue(holding)
                    .map { self.store.displayMoney($0, from: holding.currency) } ?? "—"
                value.font = .preferredFont(forTextStyle: .body)
                value.textColor = .secondaryLabel
                cell.accessories = [.customView(configuration: .init(customView: value, placement: .trailing()))]
                return
            }

            guard let tx = self.txByID[id] else { return }
            // The SwiftUI row itself, hosted — it draws the amount and the running
            // balance, so no trailing accessory here. See TxRowCell for why this is
            // hosted rather than rebuilt.
            cell.backgroundConfiguration = txRowBackground()
            TxRowCell.configure(cell, tx: tx, store: self.store,
                                onPreviewReceipt: { [weak self] in self?.previewReceipt($0) })
            cell.accessories = []
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            self?.configureHeader(view, at: indexPath)
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { view, _, _ in
            var cfg = view.defaultContentConfiguration()
            cfg.text = String(localized: "Money in · out of this account, transfers included.")
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

    /// Extracted from the registration so `refreshVisibleHeaders()` can re-run it —
    /// see the comment there for why that is necessary.
    private func configureHeader(_ view: UICollectionViewListCell, at indexPath: IndexPath) {
        guard sectionIDs.indices.contains(indexPath.section) else { return }
        switch headerContent[sectionIDs[indexPath.section]] {
        case .month(let label, let trailing, let subtitle):
            view.contentConfiguration = UIHostingConfiguration {
                MonthSectionHeader(label: label, trailing: trailing, subtitle: subtitle)
            }
        case .figures(let label, let figures, let spoken):
            view.contentConfiguration = UIHostingConfiguration {
                MonthFiguresHeader(label: label, figures: figures, accessibilityText: spoken)
            }
        case .plain(let text):
            var cfg = view.defaultContentConfiguration()
            cfg.text = text
            view.contentConfiguration = cfg
        case nil:
            view.contentConfiguration = view.defaultContentConfiguration()
        }
    }

    /// The month's net, income and spending — the same three figures the Activity feed
    /// shows, so the two screens read alike.
    ///
    /// This header used to carry the account's END-OF-MONTH BALANCE as well, taken from
    /// the newest row's running balance. That is gone by choice: the balance answered a
    /// different question from the other figures (what the account was worth, not what
    /// the month did), and it is the account's own header and rows that carry it now.
    /// Its removal is also why list and calendar mode no longer need separate shapes —
    /// the balance was the only thing the calendar fallback had to suppress, since it
    /// includes pending rows while the running balance is confirmed-only math.
    private func monthHeader(_ key: String, _ txns: [Tx]) -> HeaderContent {
        .figures(label: MonthGrouping.label(key),
                 figures: store.monthHeaderFigures(txns),
                 spoken: store.monthHeaderSpoken(txns))
    }

    /// A diffable data source does NOT re-render a supplementary view when only the
    /// section's ITEMS change — the section identifier is unchanged, so the header is
    /// left exactly as it was. Every header here is computed FROM those rows (net,
    /// end-of-month balance, income/spent, the pending count), so a row moving in or
    /// out of a month left the figures stale: confirming a transaction visibly did
    /// not update July's net or its end-of-month balance. SwiftUI recomputed the
    /// header for free; in UIKit it is explicit.
    ///
    /// Only the VISIBLE headers are refreshed, which keeps this off `reloadSections`
    /// — that would re-render every row in the section, and this screen is expected
    /// to hold thousands.

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
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            guard let view = collectionView.supplementaryView(forElementKind: kind, at: indexPath)
                    as? UICollectionViewListCell else { continue }
            configureHeader(view, at: indexPath)
        }
    }

    /// This account's rows, searched — the same base, selector and options as the
    /// SwiftUI screen, so filtering and ordering stay identical.
    private func visibleTxns() -> [Tx] {
        guard let account else { return [] }
        let all = store.transactions(for: account.id)
        guard !searchQuery.isEmpty else { return all }
        return Selectors.selectTransactions(
            all, ListOptions(ledgerId: store.activeLedgerId, query: searchQuery))
    }

    /// The SwiftUI original recomputes this inside `body`; here it is explicit —
    /// which is the single biggest day-to-day difference the migration introduces.
    private func applySnapshot() {
        guard let account else { return }
        let txns = visibleTxns()
        txByID = Dictionary(uniqueKeysWithValues: txns.map { ($0.id, $0) })

        let holdings = Selectors.holdingsForAccount(store.holdings, account.id)
        holdingByID = Dictionary(uniqueKeysWithValues: holdings.map { (Self.holdingPrefix + $0.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        var headers: [SectionID: HeaderContent] = [:]
        // No balance row: the bar's titleView carries it (see updateTitleView), so
        // this would only repeat it.
        snap.appendSections([.modePicker])
        snap.appendItems([Self.modePickerID], toSection: .modePicker)

        if !holdings.isEmpty {
            snap.appendSections([.holdings])
            snap.appendItems(holdings.map { Self.holdingPrefix + $0.id }, toSection: .holdings)
            headers[.holdings] = .plain(String(localized: "Holdings"))
        }

        if viewMode == .calendar {
            snap.appendSections([.calendar])
            snap.appendItems([Self.calendarID], toSection: .calendar)
            // The rows under the grid: the selected day, or the whole anchored
            // month — always the same searched set the grid sums, so the cells and
            // the rows cannot disagree.
            if let day = calSelectedDay {
                let dayTx = txns.filter { $0.date == day }
                snap.appendSections([.day(day)])
                snap.appendItems(dayTx.isEmpty ? [Self.emptyDayID] : dayTx.map(\.id), toSection: .day(day))
                headers[.day(day)] = .plain(MonthCashCalendar.pretty(day))
            } else {
                let key = String(format: "%04d-%02d",
                                 AppDate.civil.component(.year, from: calMonthAnchor),
                                 AppDate.civil.component(.month, from: calMonthAnchor))
                let monthTx = txns.filter { $0.date.hasPrefix(key) }
                if !monthTx.isEmpty {
                    snap.appendSections([.calMonth(key)])
                    snap.appendItems(monthTx.map(\.id), toSection: .calMonth(key))
                    headers[.calMonth(key)] = monthHeader(key, monthTx)
                }
            }
        } else {
            let pending = txns.filter { $0.pending == true }
            let confirmed = txns.filter { $0.pending != true }
            if !pending.isEmpty {
                snap.appendSections([.pending])
                snap.appendItems(pending.map(\.id), toSection: .pending)
                headers[.pending] = .plain(String(localized: "To confirm (\(pending.count))"))
            }
            if confirmed.isEmpty {
                snap.appendSections([.empty])
                snap.appendItems([Self.emptyID], toSection: .empty)
                headers[.empty] = .plain(String(localized: "Transactions"))
            } else if groupByMonth {
                for section in MonthGrouping.sections(confirmed) {
                    snap.appendSections([.month(section.id)])
                    snap.appendItems(section.txns.map(\.id), toSection: .month(section.id))
                    headers[.month(section.id)] = monthHeader(section.id, section.txns)
                }
            } else {
                snap.appendSections([.all])
                snap.appendItems(confirmed.map(\.id), toSection: .all)
                headers[.all] = .plain(String(localized: "Transactions"))
            }
        }

        // Diffable keeps the EXISTING cell for an unchanged item identifier, so a row
        // whose data changed — an edited amount, a new category, a recomputed figure —
        // would keep drawing the old values until it happened to be re-dequeued.
        // Reconfiguring the carried-over items re-runs the cell provider, and only for
        // the visible ones, so this is not a reload.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        headerContent = headers                // before apply — the headers read it
        sectionIDs = snap.sectionIdentifiers   // before apply — the layout reads it
        dataSource.apply(snap, animatingDifferences: false) { [weak self] in
            self?.refreshVisibleHeaders()
            self?.clearStuckHighlight()
        }
    }

    // MARK: Search / bars — the SwiftUI one-liners, expanded

    private func configureSearch() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Search")
        navigationItem.searchController = search
        // Matches the SwiftUI screen's `.navigationBarDrawer(displayMode: .always)`.
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    /// Name over balance, always visible while scrolled — the SwiftUI
    /// `ToolbarItem(placement: .principal)`. Privacy-aware via `displayMoney`; the
    /// reconcile seal sits beside the balance with the same glyph and colors as the
    /// Accounts list rows, and the absolute date stays in the Reconcile sheet where
    /// you would act on it.
    /// The account name, as the (large) navigation title.
    ///
    /// No `titleView` any more. It used to carry name-over-balance, ported from the
    /// SwiftUI screen's `.principal` toolbar item, but a large title and a custom
    /// `titleView` cannot share the bar: the bar renders the `titleView`, so the name
    /// would show twice while expanded and the large title would have nowhere to
    /// collapse into. The balance moved to a content row instead — see
    /// `configureBalanceCell`. The trade is deliberate: the balance now scrolls away
    /// rather than staying pinned, which is what the SwiftUI comment
    /// ("always visible while scrolled") was protecting.
    private func updateTitleView() {
        guard let account else { return }
        let name = account.name ?? String(localized: "Account")
        title = name   // still needed: it is what a pushed screen's back button shows
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [nameLabel, balanceBarView(account)])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        navigationItem.titleView = stack
    }

    /// Balance + reconcile seal as the bar's subtitle.
    private func balanceBarView(_ account: AccountRow) -> UIView {
        let label = UILabel()
        label.text = store.displayMoney(account.balance, from: account.currency)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        guard let seal = titleSeal(account) else { return label }
        let mark = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        mark.tintColor = seal
        mark.contentMode = .scaleAspectFit
        mark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        mark.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [label, mark])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }

    /// The balance row: amount, with the reconcile seal beside it.
    ///
    /// Same meaning as the old title subtitle and the Accounts list rows — green fresh,
    /// orange overdue, nothing if never reconciled — and still privacy-aware, because
    /// it goes through `displayMoney`.
    private func configureBalanceCell(_ cell: UICollectionViewListCell, _ account: AccountRow) {
        var cfg = cell.defaultContentConfiguration()
        cfg.text = store.displayMoney(account.balance, from: account.currency)
        cfg.textProperties.font = .preferredFont(forTextStyle: .title2)
        cfg.secondaryText = String(localized: "Balance")
        cfg.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        cfg.secondaryTextProperties.color = .secondaryLabel
        cfg.textToSecondaryTextVerticalPadding = 2
        cell.contentConfiguration = cfg
        if let seal = titleSeal(account) {
            let mark = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
            mark.tintColor = seal
            mark.contentMode = .scaleAspectFit
            cell.accessories = [.customView(configuration: .init(customView: mark, placement: .trailing()))]
        } else {
            cell.accessories = []
        }
    }

    /// Seal color beside the title balance — same meaning as the Accounts list
    /// rows (green fresh / orange overdue / none never reconciled).
    private func titleSeal(_ a: AccountRow) -> UIColor? {
        switch Selectors.reconcileStatus(a.lastReconciledAt, store.wallToday,
                                         staleDays: ReconcileReminder.staleDays(reconcileStaleDays)) {
        case .never: return nil
        case .fresh: return .systemGreen
        case .stale: return .systemOrange
        }
    }

    private func configureToolbar() {
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
            self?.presentAddTransaction()
        })
        add.accessibilityLabel = String(localized: "Add Transaction")

        let menu = UIMenu(children: [
            UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.presentEditAccount()
            },
            UIAction(title: String(localized: "Reconcile"), image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                self?.presentReconcile()
            },
            UIAction(title: String(localized: "Adjust balance…"),
                     image: UIImage(systemName: TxnKindIcon.icon(for: "adjustment"))) { [weak self] _ in
                self?.presentAdjustBalance()
            },
            UIAction(title: String(localized: "Archive"), image: UIImage(systemName: "archivebox")) { [weak self] _ in
                self?.archiveAccount()
            },
            UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                     attributes: .destructive) { [weak self] _ in
                self?.confirmDeleteAccount()
            },
        ])
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: menu)
        moreItem = more
        navigationItem.rightBarButtonItems = [more, add]
    }

    private var rowActions: TxRowActions {
        TxRowActions(
            duplicate: { [weak self] tx in self?.presentDuplicate(tx) },
            requestDelete: { [weak self] tx in self?.confirmDeleteTransaction(tx) },
            toggleStatus: { [weak self] tx in
                guard let self else { return }
                self.run { try txnToggleStatus(tx, store: self.store) }
            },
            edit: { [weak self] tx in self?.presentEditTransaction(tx) },
            previewReceipt: { [weak self] tx in self?.previewReceipt(tx) })
    }

    private func swipe(at indexPath: IndexPath)
        -> (leading: UISwipeActionsConfiguration, trailing: UISwipeActionsConfiguration)? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let tx = txByID[id] else { return nil }
        let actions = rowActions
        return (actions.leading(tx), actions.trailing(tx))
    }

    // MARK: Writes
    //
    // Every one goes through the same chokepoint the SwiftUI screen used, so the
    // engine rules (receipt unlinking, balance recompute, rejection on accounts
    // that still have transactions) are unchanged by the migration.

    /// Surfaces a rejected write as a localized alert rather than silently
    /// no-op'ing — the SwiftUI screen's `errorAlert`.
    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    private func confirmDeleteTransaction(_ tx: Tx) {
        // A centered ALERT, not a row-anchored sheet: the row is torn down when the
        // swipe collapses or the cell recycles, which would take the popout with it.
        // Same multi-leg warning as the feed's delete alert (ActivityFeedVC): a split
        // purchase (or a transfer) renders as one row per account leg, and deleting
        // any one row deletes the whole entry.
        var message = "\(tx.merchant) · \(store.displayMoneyBase(tx.amount))"
        if tx.transferGroupId != nil {
            message += " " + ActivityFeedView.transferDeleteHint
        } else if (tx.accountLegCount ?? 1) > 1 {
            message += " " + ActivityFeedView.multiLegDeleteHint
        }
        let alert = UIAlertController(title: String(localized: "Delete transaction?"),
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.deleteTransaction(tx.id); Haptics.warning() }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func archiveAccount() {
        guard let account else { return }
        run { try store.apply(.archiveAccount, Args(["id": .string(account.id)])) }   // pops via account == nil
    }

    private func confirmDeleteAccount() {
        guard let account else { return }
        let sheet = UIAlertController(
            title: String(localized: "Delete this account?"),
            message: String(localized: "Accounts with transactions can't be deleted — archive instead."),
            preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            // The engine rejects this if the account still has transactions.
            self.run { try self.store.apply(.deleteAccount, Args(["id": .string(account.id)])); Haptics.warning() }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        // iPad needs an anchor; the ⋯ item is where the SwiftUI dialog was anchored.
        sheet.popoverPresentationController?.barButtonItem = moreItem
        present(sheet, animated: true)
    }

    // MARK: Sheets — still SwiftUI, hosted. They are presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    private func presentAddTransaction() {
        guard let account else { return }
        present(hosted(AddTransactionSheet(defaultAccountId: account.id)), animated: true)
    }

    private func presentEditAccount() {
        guard let account else { return }
        present(hosted(AccountSheet(account: account, defaultCurrency: store.baseCurrency)), animated: true)
    }

    private func presentReconcile() {
        guard let account else { return }
        present(hosted(ReconcileSheet(preselect: account.id)), animated: true)
    }

    private func presentAdjustBalance() {
        guard let account else { return }
        present(hosted(AdjustBalanceSheet(account: account)), animated: true)
    }

    private func presentEditTransaction(_ tx: Tx) {
        present(hosted(EditTransactionSheet(txn: tx)), animated: true)
    }

    /// Duplicate opens the Add sheet pre-filled; nothing is written until Save.
    private func presentDuplicate(_ tx: Tx) {
        present(hosted(AddTransactionSheet(prefill: tx)), animated: true)
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

extension AccountDetailVC: UICollectionViewDelegate {
    /// Cells that host an interactive SwiftUI control must not be selectable, or the
    /// cell's own selection swallows the touch and the control never sees it — the
    /// mode picker looked inert for exactly this reason.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return true }
        return txByID[id] != nil
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let tx = txByID[id] else { return }
        presentEditTransaction(tx)
    }

    /// Right-click on Mac/iPad and long-press on touch — swipe is touch-only, so the
    /// SwiftUI row carried the same actions in a context menu.
    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let tx = txByID[id] else { return nil }
        var actions = rowActions
        // The item is omitted when the row has no attachment, as in SwiftUI.
        if store.attachments(for: tx.id).isEmpty { actions.previewReceipt = nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in actions.menu(tx) }
    }
}

extension AccountDetailVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}

extension AccountDetailVC: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewURL ?? URL(fileURLWithPath: "/")) as NSURL
    }
}

/// Seeds the shell's floating `+` with this account, matching the screen's own
/// toolbar `+`. The SwiftUI screen publishes the same value as an `AddTxContextKey`
/// preference; a pushed UIKit screen has no view tree to publish from, so it states
/// it here and `TabChromeVC` republishes it into the hosted FAB.
///
/// In this file, not a shared one: `accountId` is `private`, which is file-scoped.
extension AccountDetailVC: AddTxFABProviding {
    var addTxContext: AddTxContext { AddTxContext(accountId: accountId) }
}

#endif
