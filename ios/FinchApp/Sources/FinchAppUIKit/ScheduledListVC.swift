#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// `ScheduledTab` converted to UIKit — Phase 3b step 2.
///
/// **Serves both widths, and that is the point.** Ledger showed the shape by accident:
/// one view controller as the compact tab root AND as the iPad supplementary column.
/// The alternative — converting only the iPad column — would leave iPhone rendering
/// `ScheduledTab` and give the app two implementations of one list, which is the
/// Mac-divergence risk reproduced between iPhone and iPad. See the Phase 3b correction
/// in `uikit-migration-plan.md`.
///
/// **Leaves are hosted, the scroll view is native.** `ScheduledRow`,
/// `ViewModePickerRow` and `ScheduledCalendarView` are all leaves, so they are hosted
/// verbatim: the row keeps its exact layout, the calendar keeps its whole interaction
/// model, and neither can drift from the Mac's copy. The `UICollectionView` is the
/// scroll view, which is what keeps the iOS 26 resume shadow away — hosting a screen's
/// *scroll view* is reproducer B; hosting its leaves is not. Same split as
/// `AccountDetailVC`, which this is modelled on.
final class ScheduledListVC: UIViewController {

    private let store = FinchStore.shared
    private let router = DeepLinkRouter.shared
    private var cancellables = Set<AnyCancellable>()

    /// Selection mode, as `LedgersVC` defines it: nil → compact, a row opens the
    /// editor; non-nil → this drives a detail column and reports the id instead.
    private let onSelect: ((String) -> Void)?
    var selectedID: String? {
        didSet { guard selectedID != oldValue else { return }; applySnapshot() }
    }

    init(onSelect: ((String) -> Void)? = nil) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private enum Mode { case list, calendar }
    private var mode: Mode = .calendar          // the SwiftUI screen opens on the calendar
    private var searchQuery = ""
    private var monthAnchor = MonthCashCalendar.firstOfMonth(forISO: nil)
    private var selectedDay: String?
    /// Occurrences for the visible month, keyed by day. Rebuilt in `applySnapshot`.
    /// Drives the day SECTIONS below the grid, so it stays the anchored month alone.
    private var occurrencesByDay: [String: [(date: String, template: ScheduledTemplate)]] = [:]
    /// The same expansion widened to prev…next — what the GRID is summed from.
    /// `MonthPager` renders the anchored month AND its neighbours, and each page asks
    /// `amountsForRange` for its own month, so an anchored-month-only map left the
    /// incoming page drawing bare day numbers until the swipe settled.
    /// `ScheduledCalendarView` keeps the same window, for the same reason.
    private var occurrencesWide: [String: [(date: String, template: ScheduledTemplate)]] = [:]

    private enum SectionID: Hashable {
        case modePicker
        case calendar
        case empty                      // no templates and no detected charges
        case month(String)              // "yyyy-MM", or "—" for ended templates
        case detected
        case noResults                  // search matched nothing
        case day(String)                // calendar mode: one section per day with occurrences
        case nothingScheduled
    }
    private static let modePickerID = "__mode_picker__"
    private static let calendarID = "__calendar__"
    private static let emptyID = "__empty__"
    private static let noResultsID = "__no_results__"
    private static let chargePrefix = "__charge__"
    private static let occPrefix = "__occ__"
    private static let nothingID = "__nothing__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var templateByID: [String: ScheduledTemplate] = [:]
    private var chargeByID: [String: RecurringCharge] = [:]
    /// Section header text, computed in `applySnapshot`. NOT read back from
    /// `dataSource.snapshot()` inside the registration — that returns the PRE-apply
    /// sections while an apply is in flight, which is how AccountDetailVC's month
    /// figures came out a generation stale.
    private var headers: [SectionID: String] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Scheduled")
        navigationItem.largeTitleDisplayMode = onSelect == nil ? .always : .never
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()

        // Templates drive the list; accounts drive the no-accounts branch and the row
        // subtitles; transactions move the detected-charge estimates.
        Publishers.Merge3(store.$scheduled.map { _ in () },
                          store.$accounts.map { _ in () },
                          store.$txns.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applySnapshot() }
            .store(in: &cancellables)

        // Privacy mode is not one of those three slices, so without this the eye
        // icon and the calendar's masked figures both stayed on whatever they were
        // when the tab was built.
        //
        // The precise publisher, not `objectWillChange`: this screen already
        // observes the slices it depends on, so the broad signal would rebuild the
        // snapshot for all 19 published properties. `BudgetsListVC` and
        // `AccountsListVC` do need the broad one — their `budgets` / `accounts`
        // are not published slices at all — but that reason does not apply here.
        store.$privacyMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        // Per-section headers: the picker and the calendar are bare rows in SwiftUI,
        // with no `Section` header, so they must not get one here either.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let section = self?.dataSource.sectionIdentifier(for: index)
            config.headerMode = (section.flatMap { self?.headers[$0] } != nil) ? .supplementary : .none
            config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.trailingSwipe(at: ip)
            }
            config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
                self?.leadingSwipe(at: ip)
            }
            let listSection = NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
            // See ActivityFeedVC: the picker's own section padding is most of the gap
            // under the toggle, so the token owns it rather than the row margin alone.
            if section == .modePicker {
                listSection.contentInsets.top = 0
                listSection.contentInsets.bottom = Metrics.modePickerBottomGap
            }
            return listSection
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

    private func configureSearch() {
        // Search sits OUTSIDE the Calendar/List toggle, pinned, as the SwiftUI screen
        // places it — it filters what the calendar draws too, not just the list.
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = String(localized: "Search")
        navigationItem.searchController = sc
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func configureToolbar() {
        // The Ledger corner control is compact-only — the iPad sidebar lists Ledger
        // itself, so the column must not carry a redundant button. `onSelect != nil` is
        // exactly "this list is a split-view column". Same rule and same construction as
        // `BudgetsListVC`; this tab shipped without it, so the ledger was unreachable
        // from Scheduled entirely.
        if onSelect == nil {
            // Tap only. A hold on this button briefly toggled privacy — removed,
            // because nothing on a button people have only ever tapped said so,
            // and a control nobody finds is not a control. Privacy lives in
            // Settings on iPhone and on the eye at regular width.
            let ledger = UIBarButtonItem(image: UIImage(systemName: "books.vertical"),
                                         primaryAction: UIAction { [weak self] _ in
                self?.router.showLedger = true
            })
            ledger.accessibilityLabel = String(localized: "Ledger")
            navigationItem.leftBarButtonItems = [ledger]
        } else {
            navigationItem.leftBarButtonItems = nil
        }

        // Hide-amounts, same construction as `BudgetsListVC`. The SwiftUI root has
        // always carried it; the converted root shipped without it, so with the
        // UIKit screens on by default the toggle was simply gone from this tab.
        let privacy = UIBarButtonItem(
            image: UIImage(systemName: store.privacyMode ? "eye.slash" : "eye"),
            primaryAction: UIAction { [weak self] _ in self?.store.privacyMode.toggle() })
        privacy.accessibilityLabel = String(localized: "Privacy mode")
        privacy.accessibilityValue = store.privacyMode ? String(localized: "on") : String(localized: "off")

        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
            self?.presentSheet(ScheduledSheet(prefillStart: nil))
        })
        add.accessibilityLabel = String(localized: "Add Scheduled")
        // Disabled with no accounts: a recurring transaction needs somewhere to post.
        add.isEnabled = !store.accounts.isEmpty
        // Right-to-left: `add` sits outermost, so this reads "eye +" on screen —
        // the order the SwiftUI root uses.
        // The eye is regular-width only. On iPhone the toolbar is cramped and
        // privacy's home is the Settings row; at regular width there is room and
        // no Settings tab a thumb can reach as quickly. `onSelect != nil` IS
        // "this list is a split-view column", the same flag that gates the ledger
        // button the other way, so the two cannot disagree about shape.
        //
        // (A hold on the ledger button also toggled it for a day. That went: a
        // gesture with nothing to announce it is not a control anyone finds.)
        navigationItem.rightBarButtonItems = onSelect != nil ? [add, privacy] : [add]
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self else { return }
            cell.accessories = []

            switch id {
            case Self.modePickerID:
                cell.contentConfiguration = UIHostingConfiguration {
                    ViewModePickerRow(
                        selection: Binding(get: { self.mode == .list ? "List" : "Calendar" },
                                           set: { self.mode = ($0 == "List") ? .list : .calendar
                                                  self.applySnapshot() }),
                        options: [(value: "Calendar", title: String(localized: "Calendar")),
                                  (value: "List", title: String(localized: "List"))])
                }
                // Match `ViewModePickerRow`'s own insets (top 0 / bottom 4) and its
                // `.listRowBackground(Color.clear)`. Without the clear background an
                // insetGrouped cell wraps the segmented control in a white card the
                // SwiftUI row does not have — the same thing the Activity, Categories
                // and account-detail pickers were fixed for; this screen went native
                // afterwards and missed it.
                .margins(.top, 0)
                .margins(.bottom, Metrics.modePickerBottomGap)
                cell.backgroundConfiguration = .clear()

            case Self.calendarID:
                // The month GRID only. `ScheduledCalendarView` returns a `List`, so
                // hosting it collapsed inside a self-sizing cell AND put a hosted
                // SwiftUI scroll view at navigation depth — reproducer B, the thing
                // this migration removes. `MonthCashCalendar` is the genuine leaf
                // inside it, and is the same view `AccountDetailVC` hosts.
                let amounts = self.dayAmounts()
                cell.contentConfiguration = UIHostingConfiguration {
                    MonthCashCalendar(
                        monthAnchor: Binding(get: { self.monthAnchor },
                                             set: { self.monthAnchor = $0; self.applySnapshot() }),
                        selectedDay: Binding(get: { self.selectedDay },
                                             set: { self.selectedDay = $0; self.applySnapshot() }),
                        wallToday: self.store.wallToday,
                        amountsForRange: { from, through in
                            amounts.filter { $0.key >= from && $0.key <= through }
                        },
                        format: { self.store.displayExactBase($0) },
                        // Privacy mode hides the figures and draws presence dots
                        // instead; AccountDetailVC passes the same flag.
                        masked: self.store.privacyMode)
                        .environmentObject(self.store)
                        // NO height bound. An earlier `.frame(height: 420)` was here to
                        // "leave a strip to drag from", on the theory that a pan starting
                        // inside a `.page TabView` always belongs to that pager. That
                        // theory was wrong: the page did not scroll because `TabChromeVC`
                        // swallowed every touch on the tab (see FABFrameKey), and the
                        // pager was never involved. With that fixed, the grid self-sizes
                        // to exactly the height the SwiftUI screen gives it — measured
                        // 359.3pt from the weekday header to the last week row against
                        // the control's 359.4 — and both gestures work: a vertical pan
                        // scrolls the page, a horizontal one pages the month.
                }

            case Self.emptyID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Tap + or a calendar day to add a recurring transaction.")
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg

            case Self.noResultsID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "No matches")
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg

            case Self.nothingID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Nothing scheduled.")
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg

            default:
                if id.hasPrefix(Self.occPrefix), let t = self.template(forOccurrence: id) {
                    // The occurrence row: the template, hosted as the same ScheduledRow
                    // the list mode uses, so the two modes cannot drift apart.
                    cell.contentConfiguration = UIHostingConfiguration {
                        ScheduledRow(template: t).environmentObject(self.store)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                    }
                    .margins(.vertical, 6)
                    return
                }
                if let charge = self.chargeByID[id] {
                    // A detected, not-yet-scheduled charge: tapping it opens the sheet
                    // prefilled from the charge, which is how one becomes a template.
                    var cfg = cell.defaultContentConfiguration()
                    cfg.text = charge.merchantName
                    cfg.secondaryText = String(localized: "\(charge.cadence.capitalized) · next ~\(charge.nextEstimatedDate)")
                    cfg.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
                    cfg.secondaryTextProperties.color = .secondaryLabel
                    cell.contentConfiguration = cfg
                    let amount = UILabel()
                    amount.text = self.store.displayMoneyBase(charge.averageAmount)
                    amount.font = .preferredFont(forTextStyle: .body)
                    cell.accessories = [.customView(configuration: .init(customView: amount, placement: .trailing()))]
                    return
                }
                guard let t = self.templateByID[id] else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    // One VoiceOver element per row, as the SwiftUI `Button` gave —
                    // hosting `ScheduledRow` bare exposes its name, cadence and amount
                    // as three separate elements. Same fix as `BudgetsListVC`.
                    ScheduledRow(template: t).environmentObject(self.store)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                }
                .margins(.vertical, 6)
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, let section = self.dataSource.sectionIdentifier(for: indexPath.section),
                  let text = self.headers[section] else { return }
            var cfg = view.defaultContentConfiguration()
            cfg.text = text
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    // MARK: Model

    private var searchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Templates filtered by name and ordered by next run, as the SwiftUI screen does.
    private func filteredTemplates() -> [ScheduledTemplate] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? store.scheduled : store.scheduled.filter { $0.name.lowercased().contains(q) }
        let today = store.wallToday
        return base.map { (next: scheduledNextRun($0, today: today), t: $0) }
            .sorted { $0.next != $1.next ? $0.next < $1.next : $0.t.name < $1.t.name }
            .map(\.t)
    }

    /// Grouped by the month of the next occurrence, in the already-sorted order.
    /// Ended templates fall under a trailing "—" key — the same date-landmark idea the
    /// transactions feed uses.
    private func templatesByMonth() -> [(key: String, items: [ScheduledTemplate])] {
        let today = store.wallToday
        var order: [String] = []
        var by: [String: [ScheduledTemplate]] = [:]
        for t in filteredTemplates() {
            let next = scheduledNextRun(t, today: today)
            let key = next.count >= 7 ? String(next.prefix(7)) : "—"
            if by[key] == nil { order.append(key) }
            by[key, default: []].append(t)
        }
        return order.map { ($0, by[$0] ?? []) }
    }

    private func filteredCharges() -> [RecurringCharge] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        // Same selector the SwiftUI screen uses; `isScheduled` ones already have a
        // template, so they belong in the list above, not in "Detected".
        let base = Selectors.detectRecurring(store.txns, store.activeLedgerId,
                                             store.wallToday, store.scheduled)
            .filter { !$0.isScheduled }
        return q.isEmpty ? base : base.filter { $0.merchantName.lowercased().contains(q) }
    }

    private func applySnapshot() {
        // The split shell sets `selectedID` BEFORE this view loads — `install(columns:)`
        // runs while the column is still being assembled — so `dataSource` is nil here on
        // a deep link that opens straight into a selection. Applying then trapped on the
        // implicitly-unwrapped nil and killed the app at launch, on iPad only, on the
        // widget / Spotlight / App Intent path. Nothing hit it interactively, where the
        // view always exists before a row can be tapped. `viewDidLoad` applies once the
        // data source is built, and `selectedID` is already stored by then, so skipping
        // here loses nothing.
        guard dataSource != nil else { return }
        rebuildOccurrences()
        let templates = templatesByMonth()
        let charges = filteredCharges()
        templateByID = Dictionary(uniqueKeysWithValues: filteredTemplates().map { ($0.id, $0) })
        chargeByID = Dictionary(uniqueKeysWithValues: charges.map { (Self.chargePrefix + $0.id, $0) })
        configureToolbar()   // the + follows whether any accounts exist

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        headers = [:]
        snap.appendSections([.modePicker])
        snap.appendItems([Self.modePickerID], toSection: .modePicker)

        if mode == .calendar {
            snap.appendSections([.calendar])
            snap.appendItems([Self.calendarID], toSection: .calendar)
            // The day sections the SwiftUI calendar rendered inside its own List are
            // now sections of THIS collection view.
            let days = occurrencesByDay.keys.sorted()
            if let day = selectedDay {
                let section = SectionID.day(day)
                snap.appendSections([section])
                let occ = occurrencesByDay[day] ?? []
                snap.appendItems(occ.isEmpty ? [Self.nothingID]
                                             : occ.map { Self.occPrefix + day + "|" + $0.template.id },
                                 toSection: section)
                headers[section] = MonthCashCalendar.pretty(day)
            } else if days.isEmpty {
                snap.appendSections([.nothingScheduled])
                snap.appendItems([Self.nothingID], toSection: .nothingScheduled)
            } else {
                for day in days {
                    let section = SectionID.day(day)
                    snap.appendSections([section])
                    snap.appendItems((occurrencesByDay[day] ?? []).map { Self.occPrefix + day + "|" + $0.template.id },
                                     toSection: section)
                    headers[section] = MonthCashCalendar.pretty(day)
                }
            }
        } else {
            if templates.isEmpty && charges.isEmpty && !searchActive {
                snap.appendSections([.empty])
                snap.appendItems([Self.emptyID], toSection: .empty)
            }
            for group in templates {
                let section = SectionID.month(group.key)
                snap.appendSections([section])
                snap.appendItems(group.items.map(\.id), toSection: section)
                // "—" is the ended bucket; the SwiftUI screen labels it rather than
                // showing a raw em dash.
                headers[section] = group.key == "—" ? String(localized: "Ended") : monthLabel(group.key)
            }
            if !charges.isEmpty {
                snap.appendSections([.detected])
                snap.appendItems(charges.map { Self.chargePrefix + $0.id }, toSection: .detected)
                headers[.detected] = String(localized: "Detected")
            }
            if searchActive && templates.isEmpty && charges.isEmpty {
                snap.appendSections([.noResults])
                snap.appendItems([Self.noResultsID], toSection: .noResults)
            }
        }

        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)

        // `apply` clears the selection, so the highlight has to be re-asserted or the
        // row stops looking selected whenever the list refreshes underneath it.
        if let selectedID, let ip = dataSource.indexPath(for: selectedID) {
            collectionView.selectItem(at: ip, animated: false, scrollPosition: [])
        }
    }

    /// `__occ__<day>|<templateId>` → the template. Occurrence ids carry the day so a
    /// template recurring twice in one month gets two distinct diffable ids; a repeated
    /// identifier is a hard crash, not a glitch.
    private func template(forOccurrence id: String) -> ScheduledTemplate? {
        guard let sep = id.lastIndex(of: "|") else { return nil }
        return templateByID[String(id[id.index(after: sep)...])]
    }

    /// Occurrences for the visible month, and the per-day amounts the grid colours by.
    ///
    /// Expanded ONCE over prev…next, then narrowed. The grid draws the anchored month
    /// and its neighbours, and asks each page for its own month's totals — expanding
    /// only the anchored month meant the incoming page rendered bare day numbers under
    /// the finger and the figures appeared after the swipe settled. The day sections
    /// below the grid still cover the anchored month alone.
    private func rebuildOccurrences() {
        let (start, end) = MonthGrouping.monthBounds(monthAnchor)
        let wide = MonthGrouping.carouselWindow(monthAnchor)
        occurrencesWide = Dictionary(
            grouping: Selectors.occurrencesInRange(filteredTemplates(),
                                                   from: wide.start, through: wide.end),
            by: { $0.date })
        occurrencesByDay = occurrencesWide.filter { $0.key >= start && $0.key <= end }
        // A stale selection (month changed under it) must not strand the day section.
        if let d = selectedDay, d < start || d > end { selectedDay = nil }
    }

    /// Per-day income/expense totals, the shape `MonthCashCalendar` colours by.
    ///
    /// Split on `template.type`, NOT on the sign of `amount` — scheduled amounts are
    /// stored unsigned, so a sign test marks every expense as income and the whole
    /// month renders green. Converted to base currency first, because a month can mix
    /// accounts in different currencies and summing raw amounts across them is
    /// meaningless. Both rules lifted from `ScheduledCalendarView.dayAmounts`.
    private func dayAmounts() -> [String: (income: Double, expense: Double)] {
        let currencyById = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, $0.currency) })
        var out: [String: (income: Double, expense: Double)] = [:]
        // The WIDE map: the grid's neighbouring pages need their own totals too.
        for (day, occs) in occurrencesWide {
            var inc = 0.0, exp = 0.0
            for o in occs {
                guard let amt = o.template.amount else { continue }
                let base = abs(store.toBase(amt, from: currencyById[o.template.accountId] ?? nil))
                switch o.template.type {
                case "income":  inc += base
                case "expense": exp += base
                default: break
                }
            }
            out[day] = (income: inc, expense: exp)
        }
        return out
    }

    private func monthLabel(_ key: String) -> String {
        guard let date = AppDate.isoDay.date(from: key + "-01") else { return key }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: Actions

    private func template(at indexPath: IndexPath) -> ScheduledTemplate? {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return templateByID[id]
    }

    /// Edit declared first so it sits at the trailing edge, Delete to its left — the
    /// order the SwiftUI row declares, and the order muscle memory expects.
    private func trailingSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let t = template(at: indexPath) else { return nil }
        let edit = SwipeAction.make(String(localized: "Edit"),
                                    systemImage: "pencil",
                                    tint: .systemBlue) { [weak self] done in
            self?.presentSheet(ScheduledSheet(template: t)); done(true)
        }
        // Not `.destructive`: that style plays a fake row-removal animation before the
        // confirmation, so the row vanishes and then comes back if you cancel.
        let del = SwipeAction.make(String(localized: "Delete"),
                                   systemImage: "trash",
                                   tint: .systemRed) { [weak self] done in
            self?.confirmDelete(t, from: self?.collectionView.cellForItem(at: indexPath)); done(true)
        }
        return UISwipeActionsConfiguration(actions: [edit, del])
    }

    private func leadingSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let t = template(at: indexPath) else { return nil }
        let post = SwipeAction.make(String(localized: "Post"),
                                    systemImage: "checkmark.circle",
                                    tint: .systemGreen) { [weak self] done in
            self?.post(t, occurrence: nil); done(true)
        }
        return UISwipeActionsConfiguration(actions: [post])
    }

    /// Presents the prefilled sheet rather than posting instantly — deliberately.
    /// `postNow` must resolve WHICH occurrence "post" means before it can act, and that
    /// choice needs confirming. Do not "fix" this into an instant post.
    private func post(_ t: ScheduledTemplate, occurrence: String?) {
        var prefill: PostPrefill?
        var error: String?
        let prefillBinding = Binding(get: { prefill }, set: { prefill = $0 })
        let errorBinding = Binding(get: { error }, set: { error = $0 })
        if let occurrence {
            ScheduledPoster.postNow(t, occurrence: occurrence, store: store,
                                    prefill: prefillBinding, errorMessage: errorBinding)
        } else {
            ScheduledPoster.postNow(t, store: store,
                                    prefill: prefillBinding, errorMessage: errorBinding)
        }
        if let error { presentError(error); return }
        // `ScheduledPoster` either posts silently or hands back a prefill for the
        // one-occurrence sheet — the same `ScheduledPostSheetContent` the SwiftUI
        // screen reaches through `.scheduledPostSheet`.
        if let prefill { presentSheet(ScheduledPostSheetContent(prefill: prefill)) }
    }

    private func confirmDelete(_ t: ScheduledTemplate, from cell: UICollectionViewCell?) {
        let sheet = UIAlertController(title: String(localized: "Delete this scheduled item?"),
                                      message: t.name, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try self.store.apply(.deleteScheduled, Args(["id": .string(t.id)])) }
            catch { self.presentError(i18nMessage(error)) }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = cell ?? view
        sheet.popoverPresentationController?.sourceRect = (cell ?? view).bounds
        present(sheet, animated: true)
    }

    private func presentSheet(_ view: some View) {
        present(UIHostingController(rootView:
            view.environmentObject(store)
                .environmentObject(DeepLinkRouter.shared)
                .environmentObject(BiometricGate.shared)), animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

extension ScheduledListVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let q = searchController.searchBar.text ?? ""
        guard q != searchQuery else { return }
        searchQuery = q
        applySnapshot()
    }
}

extension ScheduledListVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        if id == Self.modePickerID || id == Self.calendarID { return false }   // own their touches
        return templateByID[id] != nil || chargeByID[id] != nil || id.hasPrefix(Self.occPrefix)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if let charge = chargeByID[id] {
            cv.deselectItem(at: indexPath, animated: true)
            presentSheet(ScheduledSheet(fromCharge: charge))
            return
        }
        let t0 = templateByID[id] ?? template(forOccurrence: id)
        guard let t = t0 else { return }
        if let onSelect {
            selectedID = id           // stays selected: it is the column's state, not a button
            onSelect(t.id)
            return
        }
        cv.deselectItem(at: indexPath, animated: true)
        presentSheet(ScheduledSheet(template: t))
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let t = template(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { _ in
                    self?.presentSheet(ScheduledSheet(template: t))
                },
                UIAction(title: String(localized: "Post now"), image: UIImage(systemName: "checkmark.circle")) { _ in
                    self?.post(t, occurrence: nil)
                },
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in
                    self?.confirmDelete(t, from: cv.cellForItem(at: indexPath))
                },
            ])
        }
    }
}
#endif
