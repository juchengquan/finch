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

    private enum SectionID: Hashable {
        case modePicker
        case calendar
        case empty                      // no templates and no detected charges
        case month(String)              // "yyyy-MM", or "—" for ended templates
        case detected
        case noResults                  // search matched nothing
    }
    private static let modePickerID = "__mode_picker__"
    private static let calendarID = "__calendar__"
    private static let emptyID = "__empty__"
    private static let noResultsID = "__no_results__"
    private static let chargePrefix = "__charge__"

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
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
            self?.presentSheet(ScheduledSheet(prefillStart: nil))
        })
        add.accessibilityLabel = String(localized: "Add Scheduled")
        // Disabled with no accounts: a recurring transaction needs somewhere to post.
        add.isEnabled = !store.accounts.isEmpty
        navigationItem.rightBarButtonItem = add
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
                .margins(.vertical, 4)

            case Self.calendarID:
                // Hosted whole: the calendar is a leaf with its own gesture model, and
                // it already routes edit / post / delete / add / select through the
                // callbacks below. Rebuilding a month grid in UIKit would buy nothing.
                cell.contentConfiguration = UIHostingConfiguration {
                    ScheduledCalendarView(
                        templates: self.filteredTemplates(),
                        onEdit: { [weak self] t in self?.presentSheet(ScheduledSheet(template: t)) },
                        onPost: { [weak self] t, occ in self?.post(t, occurrence: occ) },
                        onDelete: { [weak self] t in self?.confirmDelete(t, from: nil) },
                        onAdd: { [weak self] date in self?.presentSheet(ScheduledSheet(prefillStart: date)) },
                        onSelect: self.onSelect.map { pick in { (t: ScheduledTemplate) in pick(t.id) } },
                        topRow: AnyView(EmptyView()))   // the picker is its own row here
                        .environmentObject(self.store)
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

            default:
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
                    ScheduledRow(template: t).environmentObject(self.store)
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
        let edit = UIContextualAction(style: .normal, title: String(localized: "Edit")) { [weak self] _, _, done in
            self?.presentSheet(ScheduledSheet(template: t)); done(true)
        }
        edit.image = UIImage(systemName: "pencil")
        edit.backgroundColor = .systemBlue
        // Not `.destructive`: that style plays a fake row-removal animation before the
        // confirmation, so the row vanishes and then comes back if you cancel.
        let del = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(t, from: self?.collectionView.cellForItem(at: indexPath)); done(true)
        }
        del.image = UIImage(systemName: "trash")
        del.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [edit, del])
    }

    private func leadingSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let t = template(at: indexPath) else { return nil }
        let post = UIContextualAction(style: .normal, title: String(localized: "Post")) { [weak self] _, _, done in
            self?.post(t, occurrence: nil); done(true)
        }
        post.image = UIImage(systemName: "checkmark.circle")
        post.backgroundColor = .systemGreen
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
        return templateByID[id] != nil || chargeByID[id] != nil
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if let charge = chargeByID[id] {
            cv.deselectItem(at: indexPath, animated: true)
            presentSheet(ScheduledSheet(fromCharge: charge))
            return
        }
        guard let t = templateByID[id] else { return }
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
