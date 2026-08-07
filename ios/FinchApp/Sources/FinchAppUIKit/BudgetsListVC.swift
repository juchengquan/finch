#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// `BudgetsTab` converted to UIKit — Phase 3b step 2.
///
/// **One list, both widths.** This is the compact tab root (via `RootTabBarController`,
/// wrapped in `TabChromeVC`) *and* the iPad supplementary column (via `SplitShellVC`).
/// Converting only the column would have left iPhone rendering `BudgetsTab` and iPad
/// rendering this — two implementations of one list, which is the drift the Phase 3b
/// correction exists to prevent. `LedgersVC` got that shape by accident because the
/// ledger flow *is* the list; here it is deliberate.
///
/// Selection mode is the same seam `LedgersVC` uses: `onSelect == nil` means compact,
/// where a row pushes `BudgetDetailVC`; non-nil means this list drives a split view's
/// detail column and reports the id instead.
///
/// **What is hosted and what is not.** The row visual (`BudgetRowView`), the health
/// header (`BudgetSummaryCard`) and the empty state are hosted SwiftUI *leaves* — no
/// scroll view inside any of them, so the collection view stays the only scroll view
/// and reproducer B cannot form. The write forms stay SwiftUI sheets (`BudgetSheet`,
/// `AddGroupSheet`, `AddTransactionSheet`): presented, never pushed, so they cannot
/// shadow, and retyping them in UIKit would fork logic the Mac still runs.
///
/// The group headers are ROWS, not section headers — `BudgetsTab` made the same call
/// (#223): a tappable row makes the collapse chevron fire reliably and keeps the
/// default list look.
///
/// **One deliberate behaviour change.** In SwiftUI a long press on a budget row could
/// both open the context menu and start a within-group `onMove` drag; SwiftUI arbitrates
/// between them. UIKit gives the long press to the context menu, so within-group
/// reordering now goes through the explicit Reorder editor (⋯ → Reorder), which already
/// did strictly more — it moves budgets ACROSS groups and drags whole groups. Nothing is
/// unreachable; the shortcut is.
final class BudgetsListVC: UIViewController {

    private let store = FinchStore.shared
    private let router = DeepLinkRouter.shared
    private var cancellables = Set<AnyCancellable>()

    /// Selection mode. `nil` → compact: a row PUSHES its detail. Non-nil → this list
    /// drives a split view's detail column and reports the id instead.
    ///
    /// Takes `String?` rather than `LedgersVC`'s `String` because deleting the selected
    /// budget has to CLEAR the column — the SwiftUI screen did the same
    /// (`if selection?.wrappedValue == budget.id { selection?.wrappedValue = nil }`).
    private let onSelect: ((String?) -> Void)?
    /// The row to show as selected, when a split view owns the selection.
    var selectedID: String? {
        didSet { guard selectedID != oldValue else { return }; applySnapshot() }
    }

    init(onSelect: ((String?) -> Void)? = nil) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: State

    private var collapsedGroups: Set<String> = []
    private var search = ""
    private var isReordering = false
    private var reorderRows: [BudgetReorderRow] = []
    /// Reorder mode starts with every real group collapsed, as the SwiftUI editor did —
    /// dragging a whole block is the common case and a flat list of every budget is not
    /// navigable.
    private var expandedReorderGroups: Set<String> = []
    /// Set while a drag is in flight; also carried on the drag item's `localObject` so
    /// the drop handler never has to load an item provider asynchronously.
    private var draggingId: String?

    private enum SectionID: Hashable {
        case summary
        case state
        case ungrouped
        case group(String)
        case reorder
    }

    private static let summaryID = "__summary__"
    private static let loadingID = "__loading__"
    private static let emptyID = "__empty__"
    private static let noResultsID = "__noresults__"
    private static let groupPrefix = "__grp__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!

    /// Budget by id, so the diffable ids stay `Hashable` strings.
    private var budgetByID: [String: BudgetRow] = [:]
    /// Reorder row by its `BudgetReorderRow.id`, for the reorder-mode registrations.
    private var reorderRowByID: [String: BudgetReorderRow] = [:]

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Budgets")
        collapsedGroups = BudgetGroupCollapse.collapsed(ledger: store.activeLedgerId)
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()
        consumeFocus()

        // `budgets` / `budgetGroups` are not @Published slices — they are plain
        // properties the reprojection rewrites, and the SwiftUI screen picked changes up
        // by observing the store as an ObservableObject. This is that same signal, and
        // it also covers the progress bars (which depend on txns), the privacy toggle
        // and `txnsReady`.
        store.objectWillChange
            .receive(on: DispatchQueue.main)   // delivered after the mutation lands
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)

        // Collapse state is per-ledger, so a ledger switch loads a different set.
        store.$activeLedgerId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lid in
                guard let self else { return }
                self.collapsedGroups = BudgetGroupCollapse.collapsed(ledger: lid)
                self.applySnapshot()
            }
            .store(in: &cancellables)

        // A `budget:` deep link stashed an id and switched to this tab.
        router.$focusedId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.consumeFocus() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
            self?.trailingSwipeActions(at: ip)
        }
        config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
            self?.leadingSwipeActions(at: ip)
        }
        // The app-wide grouped-section gap. SwiftUI took it from `.finchSectionSpacing()`
        // on the shell; a collection view inherits nothing, and UIKit's own insetGrouped
        // gap is ~36pt against SwiftUI's 12 — measured against the control build, where
        // every group sat visibly further apart on the native screen.
        //
        // `UICollectionViewCompositionalLayoutConfiguration.interSectionSpacing` does
        // NOT move a list layout (tried it; the screenshots were byte-identical) — the
        // gap comes from each section's own content insets, so that is what is set.
        let layout = UICollectionViewCompositionalLayout { index, env in
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
            section.contentInsets.bottom = 0
            if index > 0 { section.contentInsets.top = Metrics.sectionSpacing }
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = false   // only in reorder mode
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
            case Self.summaryID:
                let summary = self.store.budgetSummary
                cell.contentConfiguration = UIHostingConfiguration {
                    BudgetSummaryCard(summary: summary).environmentObject(self.store)
                }
                return

            case Self.loadingID:
                // Launch-only: budget "spent" comes from the deferred txns projection, so
                // every bar would read $0 for ~600ms and then fill. Spin instead — same
                // call the SwiftUI screen makes.
                cell.contentConfiguration = UIHostingConfiguration {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                }
                return

            case Self.emptyID:
                let hasLedger = !self.store.ledgers.isEmpty
                cell.contentConfiguration = UIHostingConfiguration {
                    EmptyState(tab: .budgets,
                               description: hasLedger ? String(localized: "Tap + to create a budget.") : nil)
                        .padding(.vertical, 32)
                }
                return

            case Self.noResultsID:
                let query = self.search
                cell.contentConfiguration = UIHostingConfiguration {
                    ContentUnavailableView.search(text: query).padding(.vertical, 32)
                }
                return

            default:
                break
            }

            if id.hasPrefix(Self.groupPrefix) {
                self.configureGroupHeader(cell, name: String(id.dropFirst(Self.groupPrefix.count)))
                return
            }
            if self.isReordering, let row = self.reorderRowByID[id] {
                self.configureReorderRow(cell, row: row)
                return
            }
            guard let budget = self.budgetByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                BudgetRowView(budget: budget)
                    .environmentObject(self.store)
                    // The SwiftUI row was a `Button`, so VoiceOver read it as ONE element
                    // ("Health, $72.90 / $100.00, 73%, · 1 days left"). Hosting the same
                    // view in a cell without this exposes its four texts separately,
                    // which is four swipes per budget instead of one. Combining here
                    // rather than setting `cell.accessibilityLabel` keeps the wording
                    // derived from the row itself, with nothing to drift.
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    /// The collapsible group row — a ROW, not a section header, matching `BudgetsTab`.
    private func configureGroupHeader(_ cell: UICollectionViewListCell, name: String) {
        let collapsed = collapsedGroups.contains(name)
        let hex = store.budgetGroups.first(where: { $0.name == name })?.color
        let subtotal = store.budgetSubtotalDisplay(for: name)
        cell.contentConfiguration = UIHostingConfiguration {
            HStack {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                if let hex, let c = Color(hex: hex) {
                    Circle().fill(c).frame(width: 8, height: 8)
                }
                Text(verbatim: name).fontWeight(.semibold)
                Spacer()
                Text(verbatim: subtotal).foregroundStyle(.secondary)
            }
            // One element with the collapse state, as the SwiftUI header `Button` was.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(collapsed ? String(localized: "Collapsed") : String(localized: "Expanded"))
            .accessibilityHint(collapsed ? String(localized: "Double tap to expand")
                                         : String(localized: "Double tap to collapse"))
        }
    }

    /// A row in the flat reorder editor: a group header (collapsible, drags as a block)
    /// or a budget.
    private func configureReorderRow(_ cell: UICollectionViewListCell, row: BudgetReorderRow) {
        // Everything draggable gets a grip. Without one, reorder mode looked
        // identical to the normal list apart from the toolbar, with nothing on
        // screen saying the rows could be dragged at all.
        cell.accessories = row.isDraggable ? [reorderGripAccessory()] : []
        switch row {
        case .group(let gid, let name):
            guard let gid else {
                // The Ungrouped bucket is pinned last and cannot be dragged.
                cell.contentConfiguration = UIHostingConfiguration {
                    Text(verbatim: name).fontWeight(.semibold).foregroundStyle(.secondary)
                }
                return
            }
            let expanded = expandedReorderGroups.contains(gid)
            let hex = store.budgetGroups.first(where: { $0.id == gid })?.color
            let count = BudgetReorder.itemCount(of: gid, in: reorderRows)
            cell.contentConfiguration = UIHostingConfiguration {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
                    if let hex, let c = Color(hex: hex) {
                        Circle().fill(c).frame(width: 8, height: 8)
                    }
                    Text(verbatim: name).fontWeight(.semibold)
                    Text(verbatim: "· \(count) budgets").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        case .item(let budget):
            cell.contentConfiguration = UIHostingConfiguration {
                BudgetRowView(budget: budget).environmentObject(self.store)
            }
        }
    }

    private func configureSearch() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = controller
        // `BudgetsTab` pins the bar on iOS (.navigationBarDrawer(.always)).
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    // MARK: Toolbar

    private func configureToolbar() {
        guard !isReordering else {
            let cancel = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                         primaryAction: UIAction { [weak self] _ in
                // Clear FIRST so `persistReorder`'s guard no-ops — the SwiftUI ✕ path
                // did exactly this.
                self?.reorderRows = []
                self?.exitReorder()
            })
            cancel.accessibilityLabel = String(localized: "Cancel")
            let done = UIBarButtonItem(image: UIImage(systemName: "checkmark"),
                                       primaryAction: UIAction { [weak self] _ in
                self?.persistReorder()
                self?.exitReorder()
            })
            done.accessibilityLabel = String(localized: "Done")
            navigationItem.leftBarButtonItems = [cancel]
            navigationItem.rightBarButtonItems = [done]
            navigationItem.searchController = nil
            return
        }

        // The Ledger corner control is compact-only — the iPad sidebar lists Ledger
        // itself, so the column must not carry a redundant button. `onSelect != nil` is
        // exactly "this list is a split-view column".
        if onSelect == nil {
            // Tap opens the ledger picker; HOLD shows the privacy toggle.
            // `UIBarButtonItem` runs `primaryAction` on tap and presents `menu`
            // on long-press, so this is the feature filling in a property that
            // was nil — not a gesture recogniser. The tab bar has no equivalent
            // (`UITabBarItem` has no menu API at all), which is why the toggle
            // lives here and not down there.
            let ledger = UIBarButtonItem(image: UIImage(systemName: "books.vertical"),
                                         primaryAction: UIAction { [weak self] _ in
                self?.router.showLedger = true
            },
                                         menu: PrivacyMenu.menu(store: store))
            ledger.accessibilityLabel = String(localized: "Ledger")
            navigationItem.leftBarButtonItems = [ledger]
        } else {
            navigationItem.leftBarButtonItems = nil
        }

        let privacy = UIBarButtonItem(
            image: UIImage(systemName: store.privacyMode ? "eye.slash" : "eye"),
            primaryAction: UIAction { [weak self] _ in self?.store.privacyMode.toggle() })
        privacy.accessibilityLabel = String(localized: "Privacy mode")
        privacy.accessibilityValue = store.privacyMode ? String(localized: "on") : String(localized: "off")

        let add = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                  primaryAction: UIAction { [weak self] _ in self?.presentBudgetSheet(nil) })
        add.accessibilityLabel = String(localized: "Add Budget")
        add.isEnabled = !store.ledgers.isEmpty

        // Group management and Reorder live in the ⋯ overflow, matching Accounts and
        // the `.secondaryAction` placements the SwiftUI toolbar used.
        var menuItems: [UIAction] = [
            UIAction(title: String(localized: "Add Group"),
                     image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                self?.presentAddGroup()
            }
        ]
        let reorder = UIAction(title: String(localized: "Reorder"),
                               image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
            self?.enterReorder()
        }
        reorder.attributes = store.budgets.isEmpty ? .disabled : []
        menuItems.append(reorder)

        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: menuItems))
        more.accessibilityLabel = String(localized: "More")
        // The eye is iPad-only now. On iPhone the toolbar is cramped and hiding
        // amounts moved to a long-press of the ledger button — which iPad does
        // not have, because its sidebar lists Ledger itself. `onSelect != nil`
        // IS "this list is a split-view column", the same flag that gates the
        // ledger button the other way, so the two cannot disagree about shape.
        navigationItem.rightBarButtonItems = onSelect != nil ? [more, add, privacy] : [more, add]
    }

    // MARK: Snapshot

    /// True while the user has typed a non-empty budget search.
    private var searchActive: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Budgets in `group`, narrowed by the search query (case-insensitive name
    /// contains). No query → the full group.
    private func filteredBudgets(in group: String) -> [BudgetRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let budgets = store.budgets(in: group)
        guard !q.isEmpty else { return budgets }
        return budgets.filter { $0.name.lowercased().contains(q) }
    }

    /// Ungrouped budgets, narrowed by the search query — rendered bare at the top.
    private var filteredUngroupedBudgets: [BudgetRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let buds = store.ungroupedBudgets
        guard !q.isEmpty else { return buds }
        return buds.filter { $0.name.lowercased().contains(q) }
    }

    /// Groups to render: all normally; while searching, only those with a match.
    private var groupsToShow: [String] {
        searchActive ? store.budgetGroupsOrdered.filter { !filteredBudgets(in: $0).isEmpty }
                     : store.budgetGroupsOrdered
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
        budgetByID = Dictionary(uniqueKeysWithValues: store.budgets.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()

        if isReordering {
            reorderRowByID = Dictionary(uniqueKeysWithValues: reorderRows.map { ($0.id, $0) })
            let collapsed = Set(store.budgetGroups.map(\.id)).subtracting(expandedReorderGroups)
            snap.appendSections([.reorder])
            snap.appendItems(BudgetReorder.visibleRows(reorderRows, collapsed: collapsed).map(\.id),
                             toSection: .reorder)
        } else if !store.txnsReady {
            snap.appendSections([.state])
            snap.appendItems([Self.loadingID], toSection: .state)
        } else if store.budgets.isEmpty {
            snap.appendSections([.state])
            snap.appendItems([Self.emptyID], toSection: .state)
        } else {
            snap.appendSections([.summary])
            snap.appendItems([Self.summaryID], toSection: .summary)

            let ungrouped = filteredUngroupedBudgets
            let groups = groupsToShow
            if searchActive && groups.isEmpty && ungrouped.isEmpty {
                snap.appendSections([.state])
                snap.appendItems([Self.noResultsID], toSection: .state)
            }
            if !ungrouped.isEmpty {
                snap.appendSections([.ungrouped])
                snap.appendItems(ungrouped.map(\.id), toSection: .ungrouped)
            }
            for name in groups {
                snap.appendSections([.group(name)])
                snap.appendItems([Self.groupPrefix + name], toSection: .group(name))
                // Collapse is bypassed while searching so matches always surface.
                if !collapsedGroups.contains(name) || searchActive {
                    snap.appendItems(filteredBudgets(in: name).map(\.id), toSection: .group(name))
                }
            }
        }

        // Renames, spend changes, privacy toggles and collapse toggles all leave the
        // item identifiers alone, so without this the cells keep their old content.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)

        // Re-assert the highlight: `apply` clears the selection, so without this the row
        // stops looking selected every time a figure changes underneath it.
        if let selectedID, let ip = dataSource.indexPath(for: selectedID) {
            collectionView.selectItem(at: ip, animated: false, scrollPosition: [])
        }
        configureToolbar()
    }

    // MARK: Reorder

    private func enterReorder() {
        isReordering = true
        reorderRows = BudgetReorder.buildRows(groups: store.budgetGroups, budgets: store.budgets)
        expandedReorderGroups = []
        collectionView.dragInteractionEnabled = true
        applySnapshot()
    }

    private func exitReorder() {
        isReordering = false
        reorderRows = []
        expandedReorderGroups = []
        collectionView.dragInteractionEnabled = false
        configureSearch()
        applySnapshot()
    }

    /// Persist on ✓ (diff-aware, mirroring the SwiftUI editor): group order via
    /// `updateBudgetGroup`, changed membership via `updateBudget`, then the ledger-wide
    /// flat order in one `setBudgetOrder`. Writes go through the per-call `store.apply`
    /// chokepoint, so it is not atomic — a mid-loop failure is cosmetic and self-heals
    /// on the next reorder.
    private func persistReorder() {
        guard !reorderRows.isEmpty else { return }
        let plan = BudgetReorder.plan(reorderRows)
        let curGroupOrder = Dictionary(uniqueKeysWithValues: store.budgetGroups.enumerated().map { ($1.id, $0) })
        let curGroupOf = Dictionary(uniqueKeysWithValues: store.budgets.map { ($0.id, $0.groupId) })
        do {
            for g in plan.groups where curGroupOrder[g.id] != g.order {
                try store.apply(.updateBudgetGroup,
                                Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(g.order)])]))
            }
            for it in plan.items where curGroupOf[it.id] != it.groupId {
                try store.apply(.updateBudget,
                                Args(["id": .string(it.id),
                                      "patch": .object(["groupId": it.groupId.map(JSONValue.string) ?? .null])]))
            }
            try store.apply(.setBudgetOrder,
                            Args(["ledgerId": .string(store.activeLedgerId),
                                  "budgetIds": .array(plan.items.map { .string($0.id) })]))
        } catch { presentError(i18nMessage(error)) }
    }

    // MARK: Row actions

    private func trailingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let budget = budgetByID[id] else { return nil }
        let edit = UIContextualAction(style: .normal, title: String(localized: "Edit")) { [weak self] _, _, done in
            self?.presentBudgetSheet(budget); done(true)
        }
        edit.image = UIImage(systemName: "pencil")
        edit.backgroundColor = .systemBlue
        // NOT `.destructive`: that style plays a fake row-removal animation before the
        // confirm, which the SwiftUI screen deliberately avoids.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(budget); done(true)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [edit, delete])
    }

    /// Leading swipe: quick-add a transaction scoped to this budget, prefilled with its
    /// first category — expense budgets and income goals alike are funded by real
    /// transactions.
    private func leadingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let budget = budgetByID[id] else { return nil }
        let add = UIContextualAction(style: .normal, title: String(localized: "Add Transaction")) { [weak self] _, _, done in
            self?.presentQuickAdd(for: budget); done(true)
        }
        add.image = UIImage(systemName: "plus")
        add.backgroundColor = .systemGreen
        return UISwipeActionsConfiguration(actions: [add])
    }

    private func confirmDelete(_ budget: BudgetRow) {
        let alert = UIAlertController(
            title: String(localized: "Delete this budget?"),
            message: String(localized: "This permanently deletes \(budget.name)."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            self?.delete(budget)
        })
        present(alert, animated: true)
    }

    private func delete(_ budget: BudgetRow) {
        do {
            try store.apply(.removeBudget, Args(["id": .string(budget.id)]))
            if selectedID == budget.id {
                selectedID = nil
                onSelect?(nil)   // the detail column falls back to its placeholder
            }
        } catch { presentError(i18nMessage(error)) }
    }

    private func confirmDeleteGroup(_ group: GroupRow) {
        let alert = UIAlertController(
            title: String(localized: "Delete group?"),
            message: String(localized: "Budgets in this group become ungrouped."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Delete \(group.name)"),
                                      style: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try self.store.apply(.deleteBudgetGroup, Args(["id": .string(group.id)])) }
            catch { self.presentError(i18nMessage(error)) }
        })
        present(alert, animated: true)
    }

    private func promptRenameGroup(_ group: GroupRow) {
        let alert = UIAlertController(title: String(localized: "Rename group"),
                                      message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = group.name; $0.placeholder = String(localized: "Name") }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Save"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            do {
                try self.store.apply(.updateBudgetGroup,
                                     Args(["id": .string(group.id), "patch": .object(["name": .string(name)])]))
            } catch { self.presentError(i18nMessage(error)) }
        })
        present(alert, animated: true)
    }

    /// Toggle a group's collapsed state and persist it.
    private func toggleGroup(_ name: String) {
        let nowCollapsed = !collapsedGroups.contains(name)
        if nowCollapsed { collapsedGroups.insert(name) } else { collapsedGroups.remove(name) }
        BudgetGroupCollapse.setCollapsed(name, nowCollapsed, ledger: store.activeLedgerId)
        applySnapshot()
    }

    // MARK: Presentation

    private func presentBudgetSheet(_ budget: BudgetRow?) {
        present(hostSheet(BudgetSheet(budget: budget)), animated: true)
    }

    private func presentAddGroup() {
        present(hostSheet(AddGroupSheet()), animated: true)
    }

    private func presentQuickAdd(for budget: BudgetRow) {
        present(hostSheet(AddTransactionSheet(defaultCategoryId: budget.categoryIds.first)), animated: true)
    }

    /// Hosting controllers inherit no environment — the trap that crashed
    /// `BackupSyncSettingsVC` in Phase 2 — so every presented sheet re-declares it.
    private func hostSheet(_ view: some View) -> UIViewController {
        UIHostingController(rootView:
            view
                .finchSectionSpacing()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(BiometricGate.shared))
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    /// A deep link stashed a budget id + switched to this tab — open it.
    private func consumeFocus() {
        guard let id = router.focusedId, store.budgets.contains(where: { $0.id == id }) else { return }
        router.focusedId = nil
        if onSelect != nil {
            selectedID = id
            onSelect?(id)
        } else {
            navigationController?.pushViewController(BudgetDetailVC(budgetId: id), animated: true)
        }
    }

}

// MARK: - Selection, context menus

extension BudgetsListVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        // The summary card and the state rows are not interactive.
        return !(id == Self.summaryID || id == Self.loadingID || id == Self.emptyID || id == Self.noResultsID)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }

        if isReordering {
            cv.deselectItem(at: indexPath, animated: false)
            // Only a real group row toggles; the pinned Ungrouped header does nothing.
            if let row = reorderRowByID[id], case .group(let gid?, _) = row {
                if expandedReorderGroups.contains(gid) { expandedReorderGroups.remove(gid) }
                else { expandedReorderGroups.insert(gid) }
                applySnapshot()
            }
            return
        }

        if id.hasPrefix(Self.groupPrefix) {
            cv.deselectItem(at: indexPath, animated: false)
            toggleGroup(String(id.dropFirst(Self.groupPrefix.count)))
            return
        }

        guard budgetByID[id] != nil else { return }
        if let onSelect {
            // Stay selected: the row is the current state of the column beside it, not a
            // button that fired.
            selectedID = id
            onSelect(id)
            return
        }
        cv.deselectItem(at: indexPath, animated: true)
        navigationController?.pushViewController(BudgetDetailVC(budgetId: id), animated: true)
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isReordering, let id = dataSource.itemIdentifier(for: indexPath) else { return nil }

        // Long-press a group → Edit / Delete, on real groups only.
        if id.hasPrefix(Self.groupPrefix) {
            let name = String(id.dropFirst(Self.groupPrefix.count))
            guard let group = store.budgetGroups.first(where: { $0.name == name }) else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                UIMenu(children: [
                    UIAction(title: String(localized: "Edit"),
                             image: UIImage(systemName: "pencil")) { _ in self?.promptRenameGroup(group) },
                    UIAction(title: String(localized: "Delete Group"),
                             image: UIImage(systemName: "trash"),
                             attributes: .destructive) { _ in self?.confirmDeleteGroup(group) },
                ])
            }
        }

        guard let budget = budgetByID[id] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Add Transaction"),
                         image: UIImage(systemName: "plus")) { _ in self?.presentQuickAdd(for: budget) },
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: String(localized: "Edit"),
                             image: UIImage(systemName: "pencil")) { _ in self?.presentBudgetSheet(budget) },
                    UIAction(title: String(localized: "Delete"),
                             image: UIImage(systemName: "trash"),
                             attributes: .destructive) { _ in self?.confirmDelete(budget) },
                ]),
            ])
        }
    }
}

extension BudgetsListVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        search = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}

// MARK: - Drag to reorder
//
// Two drop zones, not three: a budget has no nesting, only a position. The top half of
// the target row inserts BEFORE it and the bottom half AFTER — which is exactly the
// `to:` index `BudgetReorder.applyVisibleMove` expects, because it mirrors SwiftUI's
// `onMove` destination convention (an index in the pre-removal array).
//
// Long-press to lift, as `CategoriesVC` does — `idb` has no drag command, so the lift
// itself cannot be driven automatically; `BudgetReorder` is unit-tested instead.

extension BudgetsListVC: UICollectionViewDragDelegate {
    func collectionView(_ cv: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard isReordering, let id = dataSource.itemIdentifier(for: indexPath),
              let row = reorderRowByID[id] else { return [] }
        // The Ungrouped header is pinned; lifting it would be a no-op drag.
        if case .group(let gid, _) = row, gid == nil { return [] }
        draggingId = id
        let item = UIDragItem(itemProvider: NSItemProvider(object: id as NSString))
        item.localObject = id
        return [item]
    }

    func collectionView(_ cv: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        draggingId = nil
    }
}

extension BudgetsListVC: UICollectionViewDropDelegate {
    func collectionView(_ cv: UICollectionView, canHandle session: UIDropSession) -> Bool {
        isReordering && draggingId != nil
    }

    func collectionView(_ cv: UICollectionView,
                        dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard isReordering else { return UICollectionViewDropProposal(operation: .cancel) }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ cv: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard isReordering,
              let sourceID = coordinator.items.first?.dragItem.localObject as? String ?? draggingId else { return }
        let collapsed = Set(store.budgetGroups.map(\.id)).subtracting(expandedReorderGroups)
        let visible = BudgetReorder.visibleRows(reorderRows, collapsed: collapsed)
        guard let srcVisible = visible.firstIndex(where: { $0.id == sourceID }) else { return }

        let point = coordinator.session.location(in: cv)
        let destination: Int
        if let indexPath = cv.indexPathForItem(at: point),
           let targetID = dataSource.itemIdentifier(for: indexPath),
           let targetVisible = visible.firstIndex(where: { $0.id == targetID }) {
            let frame = cv.cellForItem(at: indexPath)?.frame ?? .zero
            let below = frame.height > 0 && (point.y - frame.minY) / frame.height > 0.5
            destination = below ? targetVisible + 1 : targetVisible
        } else {
            destination = visible.count      // dropped past the last row
        }
        guard destination != srcVisible else { return }

        reorderRows = BudgetReorder.applyVisibleMove(reorderRows, collapsed: collapsed,
                                                     from: IndexSet(integer: srcVisible), to: destination)
        applySnapshot()
        // Hand the lifted preview back to UIKit so it animates INTO its new row.
        // Without this the drop played the CANCEL animation — flying the preview all
        // the way back to the lift point — before the reordered list appeared
        // underneath it. `applySnapshot` above is synchronous and renders from
        // `reorderRows`, so the index path resolved here is already the new one.
        if let item = coordinator.items.first?.dragItem,
           let dest = dataSource.indexPath(for: sourceID) {
            coordinator.drop(item, toItemAt: dest)
        }
    }
}
#endif
