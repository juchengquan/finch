#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// `AccountsTab` converted to UIKit — Phase 3b step 5, the last and largest.
///
/// **One list, both widths.** The compact tab root (via `RootTabBarController`, wrapped
/// in `TabChromeVC`) and the iPad supplementary column (via `SplitShellVC`) are this one
/// view controller. `onSelect == nil` means compact, where a row pushes
/// `AccountDetailVC`; non-nil means this list drives a split view's detail column.
///
/// Structurally this is `BudgetsListVC` with more on it — the same collapsible groups,
/// per-ledger collapse persistence, search, two swipe edges, context menus and reorder
/// editor. What Accounts adds:
///
/// - a **summary section**: the net-worth / liabilities row and the All Transactions
///   entry, which pushes the converted feed rather than opening a sheet;
/// - **archive**, a third row verb that Budgets has no equivalent of;
/// - a much larger ⋯ overflow: Add Group, Reorder, Archived Accounts, Holdings,
///   Reconcile. (There was an "Import statement (CSV)" entry here; the feature is gone
///   — `ReconcileSheet` already does that job by hand and says when you are square.
///   See FEATURE_IDEAS 9.3 if it is ever built properly.)
///
/// Hosted SwiftUI is limited to leaves — `AccountRowView`, `StatusSummaryRow`, the group
/// header — and to sheets, which are presented rather than pushed and so cannot shadow.
/// The write forms stay SwiftUI on purpose: `AccountSheet`, `ReconcileSheet`,
/// `AddAccountGroupSheet`, `ArchivedAccountsView` are the same ones the Mac renders,
/// and retyping them in UIKit would fork logic that must not drift.
final class AccountsListVC: UIViewController {

    private let store = FinchStore.shared
    private let router = DeepLinkRouter.shared
    private var cancellables = Set<AnyCancellable>()

    /// Selection mode. `nil` → compact: a row PUSHES its detail. Non-nil → this list
    /// drives a split view's detail column and reports the id instead. `String?` so
    /// deleting or archiving the selected account can clear the column.
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
    private var reorderRows: [ReorderRow] = []
    /// Reorder mode starts with every real group collapsed, as the SwiftUI editor did —
    /// dragging a whole block is the common case and a flat list of every account is not
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

    private static let netWorthID = "__net_worth__"
    private static let allTxnsID = "__all_transactions__"
    private static let loadingID = "__loading__"
    private static let emptyID = "__empty__"
    private static let noResultsID = "__noresults__"
    private static let groupPrefix = "__grp__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!

    private var accountByID: [String: AccountRow] = [:]
    private var reorderRowByID: [String: ReorderRow] = [:]

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Accounts")
        collapsedGroups = AccountGroupCollapse.collapsed(ledger: store.activeLedgerId)
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()
        consumeFocus()

        // `accounts` / `accountGroups` are not @Published slices — they are plain
        // properties the reprojection rewrites, and the SwiftUI screen picked changes up
        // by observing the store as an ObservableObject. This is that same signal, and it
        // also covers the balances (which depend on txns), the privacy toggle and
        // `txnsReady`.
        store.objectWillChange
            .receive(on: DispatchQueue.main)   // delivered after the mutation lands
            .sink { [weak self] _ in self?.setNeedsSnapshot() }
            .store(in: &cancellables)

        // Collapse state is per-ledger, so a ledger switch loads a different set.
        store.$activeLedgerId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lid in
                guard let self else { return }
                self.collapsedGroups = AccountGroupCollapse.collapsed(ledger: lid)
                self.applySnapshot()
            }
            .store(in: &cancellables)

        // An `account:` deep link stashed an id and switched to this tab.
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
        // The app-wide grouped-section gap. A collection view does not inherit
        // `.finchSectionSpacing()`, and UIKit's insetGrouped default is ~36pt against
        // SwiftUI's 12 — see BudgetsListVC, where the difference was measured against a
        // control build. `interSectionSpacing` on the layout configuration does NOT move
        // a list layout; the inset has to be set per section.
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
            case Self.netWorthID:
                let net = self.store.netWorthDisplay
                let liab = self.store.liabilitiesDisplay
                cell.contentConfiguration = UIHostingConfiguration {
                    StatusSummaryRow(leadingLabel: String(localized: "Net worth"), leadingValue: net,
                                     trailingLabel: String(localized: "Liabilities"), trailingValue: liab)
                        .environmentObject(self.store)
                }
                return

            case Self.allTxnsID:
                // Hosted rather than a `defaultContentConfiguration`, purely for
                // accessibility: the SwiftUI screen's row is a `Button`, and
                // `NavigationUITests` drives the Accounts→Activity drill via
                // `app.buttons["All Transactions"]`. A content configuration owns the
                // cell's accessibility, so setting `cell.accessibilityTraits` after it
                // does nothing — the row stayed a plain cell and the test could not find
                // an entry point. Combining in SwiftUI is what the other rows do.
                //
                // No disclosure chevron, matching the SwiftUI screen — it uses a plain
                // Button for exactly that reason ("so there's no trailing disclosure
                // chevron — same convention as the Accounts rows"). Caught by diffing
                // against a control build.
                cell.contentConfiguration = UIHostingConfiguration {
                    Label(String(localized: "All Transactions"), systemImage: "list.bullet")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                }
                return

            case Self.loadingID:
                cell.contentConfiguration = UIHostingConfiguration {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 64)
                }
                return

            case Self.emptyID:
                let hasLedger = !self.store.ledgers.isEmpty
                cell.contentConfiguration = UIHostingConfiguration {
                    EmptyState(tab: .accounts,
                               description: hasLedger ? String(localized: "Tap + to add an account.") : nil)
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
            guard let account = self.accountByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                // One VoiceOver element per row, as the SwiftUI `Button` gave — hosting
                // the row bare exposes its name, type, balance and any reconcile badge
                // as separate elements, which is several swipes per account.
                AccountRowView(account: account)
                    .environmentObject(self.store)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    /// The collapsible group row — a ROW, not a section header, matching `AccountsTab`
    /// (#223): a tappable row makes the chevron fire reliably and keeps the default look.
    private func configureGroupHeader(_ cell: UICollectionViewListCell, name: String) {
        let collapsed = collapsedGroups.contains(name)
        let hex = store.accountGroups.first(where: { $0.name == name })?.color
        let subtotal = store.subtotalDisplay(for: name)
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
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(collapsed ? String(localized: "Collapsed") : String(localized: "Expanded"))
            .accessibilityHint(collapsed ? String(localized: "Double tap to expand")
                                         : String(localized: "Double tap to collapse"))
        }
    }

    /// A row in the flat reorder editor: a group header (collapsible, drags as a block)
    /// or an account.
    private func configureReorderRow(_ cell: UICollectionViewListCell, row: ReorderRow) {
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
            let hex = store.accountGroups.first(where: { $0.id == gid })?.color
            let count = AccountReorder.accountCount(of: gid, in: reorderRows)
            cell.contentConfiguration = UIHostingConfiguration {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
                    if let hex, let c = Color(hex: hex) {
                        Circle().fill(c).frame(width: 8, height: 8)
                    }
                    Text(verbatim: name).fontWeight(.semibold)
                    Text(verbatim: "· \(count) accounts").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        case .account(let account):
            cell.contentConfiguration = UIHostingConfiguration {
                AccountRowView(account: account).environmentObject(self.store)
            }
        }
    }

    private func configureSearch() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = controller
        // `AccountsTab` pins the bar on iOS (.navigationBarDrawer(.always)).
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
        // itself, so the column must not carry a redundant button.
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

        let privacy = UIBarButtonItem(
            image: UIImage(systemName: store.privacyMode ? "eye.slash" : "eye"),
            primaryAction: UIAction { [weak self] _ in self?.store.privacyMode.toggle() })
        privacy.accessibilityLabel = String(localized: "Privacy mode")
        privacy.accessibilityValue = store.privacyMode ? String(localized: "on") : String(localized: "off")

        let add = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                  primaryAction: UIAction { [weak self] _ in self?.presentAccountSheet(nil) })
        add.accessibilityLabel = String(localized: "Add Account")
        // An account needs a ledger — each tab's + gates on its own prerequisite.
        add.isEnabled = !store.ledgers.isEmpty

        let hasAccounts = !store.accounts.isEmpty
        let reorder = UIAction(title: String(localized: "Reorder"),
                               image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
            self?.enterReorder()
        }
        reorder.attributes = hasAccounts ? [] : .disabled
        let reconcile = UIAction(title: String(localized: "Reconcile"),
                                 image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
            self?.present(self?.hostSheet(ReconcileSheet()) ?? UIViewController(), animated: true)
        }
        reconcile.attributes = hasAccounts ? [] : .disabled

        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [
            UIAction(title: String(localized: "Add Group"),
                     image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                self?.present(self?.hostSheet(AddAccountGroupSheet()) ?? UIViewController(), animated: true)
            },
            reorder,
            UIAction(title: String(localized: "Archived Accounts"),
                     image: UIImage(systemName: "archivebox")) { [weak self] _ in
                guard let self else { return }
                self.present(self.hostSheet(NavigationStack { ArchivedAccountsView() }), animated: true)
            },
            UIAction(title: String(localized: "Holdings"),
                     image: UIImage(systemName: "chart.bar")) { [weak self] _ in
                self?.pushOrSelectHoldings()
            },
            reconcile,
        ]))
        more.accessibilityLabel = String(localized: "More")
        // The eye is regular-width only. On iPhone the toolbar is cramped and
        // privacy's home is the Settings row; at regular width there is room and
        // no Settings tab a thumb can reach as quickly. `onSelect != nil` IS
        // "this list is a split-view column", the same flag that gates the ledger
        // button the other way, so the two cannot disagree about shape.
        //
        // (A hold on the ledger button also toggled it for a day. That went: a
        // gesture with nothing to announce it is not a control anyone finds.)
        navigationItem.rightBarButtonItems = onSelect != nil ? [more, add, privacy] : [more, add]
    }

    // MARK: Snapshot

    private var searchActive: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func filteredAccounts(in group: String) -> [AccountRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let accounts = store.accounts(in: group)
        guard !q.isEmpty else { return accounts }
        return accounts.filter { ($0.name ?? "").lowercased().contains(q) }
    }

    private var filteredUngroupedAccounts: [AccountRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let accounts = store.ungroupedAccounts
        guard !q.isEmpty else { return accounts }
        return accounts.filter { ($0.name ?? "").lowercased().contains(q) }
    }

    private var groupsToShow: [String] {
        searchActive ? store.accountGroupsOrdered.filter { !filteredAccounts(in: $0).isEmpty }
                     : store.accountGroupsOrdered
    }

    /// Coalesce a burst of `objectWillChange` into ONE rebuild.
    ///
    /// `reprojectActiveLedger` assigns ~17 @Published slices back to back, so the
    /// store emits ~17 times in a few milliseconds and this list rebuilt itself once
    /// per emission — measured at 37 full rebuilds in 1.1s on launch.
    private var snapshotScheduled = false
    private func setNeedsSnapshot() {
        guard !snapshotScheduled else { return }
        snapshotScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshotScheduled = false
            self.applySnapshot()
        }
    }

    /// - Parameters:
    ///   - animated: whether the apply animates. Default false, which is what every
    ///     caller but the collapse toggle wants: a sync landing, a search keystroke or a
    ///     ledger switch must not make the list move under a thumb that is reading it.
    ///     Ten callers, one of which is a deliberate gesture — that one animates.
    ///   - reconfiguring: which carried items to re-render. Default nil = all of them,
    ///     today's behaviour. The toggle passes the single group row whose chevron
    ///     flipped, because on a collapse nothing else on screen changes and an animated
    ///     apply crossfades everything it is told to reconfigure.
    private func applySnapshot(animated: Bool = false, reconfiguring: [String]? = nil) {
        // The split shell sets `selectedID` BEFORE this view loads — `install(columns:)`
        // runs while the column is still being assembled — so `dataSource` is nil here on
        // a deep link that opens straight into a selection. Applying then trapped on the
        // implicitly-unwrapped nil and killed the app at launch, on iPad only, on the
        // widget / Spotlight / App Intent path. Nothing hit it interactively, where the
        // view always exists before a row can be tapped. `viewDidLoad` applies once the
        // data source is built, and `selectedID` is already stored by then, so skipping
        // here loses nothing.
        guard dataSource != nil else { return }
        accountByID = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()

        if isReordering {
            reorderRowByID = Dictionary(uniqueKeysWithValues: reorderRows.map { ($0.id, $0) })
            let collapsed = Set(store.accountGroups.map(\.id)).subtracting(expandedReorderGroups)
            snap.appendSections([.reorder])
            snap.appendItems(AccountReorder.visibleRows(reorderRows, collapsed: collapsed).map(\.id),
                             toSection: .reorder)
        } else if !store.txnsReady {
            snap.appendSections([.state])
            snap.appendItems([Self.loadingID], toSection: .state)
        } else {
            // The summary section stays even with no accounts: it carries All
            // Transactions, and the SwiftUI screen keeps it above the empty state too.
            snap.appendSections([.summary])
            snap.appendItems([Self.netWorthID, Self.allTxnsID], toSection: .summary)

            if store.accounts.isEmpty {
                snap.appendSections([.state])
                snap.appendItems([Self.emptyID], toSection: .state)
            } else {
                let ungrouped = filteredUngroupedAccounts
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
                        snap.appendItems(filteredAccounts(in: name).map(\.id), toSection: .group(name))
                    }
                }
            }
        }

        // Renames, balance changes, privacy toggles and collapse toggles all leave the
        // item identifiers alone, so without this the cells keep their old content.
        //
        // `reconfiguring` narrows that set, and only the collapse toggle passes it. The
        // reason is the animation: an ANIMATED apply crossfades every reconfigured cell,
        // so reconfiguring everything carried — correct and invisible while unanimated —
        // would make one group opening shimmer the whole list. That is not a guess; it
        // is what #702's second attempt did and why it was withdrawn.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        let toReconfigure = reconfiguring ?? snap.itemIdentifiers.filter(carried.contains)
        snap.reconfigureItems(toReconfigure.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: animated)

        // Re-assert the highlight: `apply` clears the selection, so without this the row
        // stops looking selected every time a balance changes underneath it.
        if let selectedID, let ip = dataSource.indexPath(for: selectedID) {
            collectionView.selectItem(at: ip, animated: false, scrollPosition: [])
        }
        dropSelectionIfGone()
        configureToolbar()
    }

    /// Clear the column when the selected account stops existing — deleted, archived, or
    /// gone with a ledger switch. Done off the snapshot rather than in each action:
    /// there are three ways an account leaves the list and a detail column pointed at a
    /// missing id is the same bug however it happened.
    private func dropSelectionIfGone() {
        guard let onSelect, let id = selectedID else { return }
        guard !store.accounts.contains(where: { $0.id == id }) else { return }
        selectedID = nil
        onSelect(nil)
    }

    // MARK: Reorder

    private func enterReorder() {
        isReordering = true
        reorderRows = AccountReorder.buildRows(groups: store.accountGroups, accounts: store.accounts)
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

    /// Persist on ✓ (diff-aware, mirroring the SwiftUI editor).
    ///
    /// NOTE the difference from `BudgetsListVC`: budgets have a `setBudgetOrder` action
    /// that takes the whole ordered id list, accounts do not. Each account's `sortOrder`
    /// is patched individually via `updateAccount`, alongside its group membership, and
    /// only when one of the two actually changed. Writes go through the per-call
    /// `store.apply` chokepoint, so it is not atomic — a mid-loop failure is cosmetic
    /// and self-heals on the next reorder.
    private func persistReorder() {
        guard !reorderRows.isEmpty else { return }
        let plan = AccountReorder.persistencePlan(reorderRows)
        let curGroupOrder = Dictionary(uniqueKeysWithValues: store.accountGroups.enumerated().map { ($1.id, $0) })
        let curAcct = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, ($0.groupId, $0.sortOrder ?? 0)) })
        do {
            for g in plan.groups where curGroupOrder[g.id] != g.order {
                try store.apply(.updateAccountGroup,
                                Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(g.order)])]))
            }
            for a in plan.accounts {
                let cur = curAcct[a.id]
                if cur?.0 != a.groupId || cur?.1 != a.order {
                    var patch: [String: JSONValue] = ["sortOrder": .int(a.order)]
                    patch["groupId"] = a.groupId.map(JSONValue.string) ?? .null
                    try store.apply(.updateAccount, Args(["id": .string(a.id), "patch": .object(patch)]))
                }
            }
        } catch { presentError(i18nMessage(error)) }
    }

    // MARK: Row actions

    private func trailingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let account = accountByID[id] else { return nil }
        let edit = UIContextualAction(style: .normal, title: String(localized: "Edit")) { [weak self] _, _, done in
            self?.presentAccountSheet(account); done(true)
        }
        edit.image = UIImage(systemName: "pencil")
        edit.backgroundColor = .systemBlue
        // NOT `.destructive`: that style plays a fake row-removal animation before the
        // confirm, which the SwiftUI screen deliberately avoids.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(account); done(true)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [edit, delete])
    }

    /// Leading swipe: quick-add only (full swipe = Add). Reconcile is menu-only, as in
    /// the SwiftUI screen.
    private func leadingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let account = accountByID[id] else { return nil }
        let add = UIContextualAction(style: .normal, title: String(localized: "Add Transaction")) { [weak self] _, _, done in
            self?.present(self?.hostSheet(AddTransactionSheet(defaultAccountId: account.id)) ?? UIViewController(),
                          animated: true)
            done(true)
        }
        add.image = UIImage(systemName: "plus")
        add.backgroundColor = .systemGreen
        return UISwipeActionsConfiguration(actions: [add])
    }

    private func confirmDelete(_ account: AccountRow) {
        let name = account.name ?? String(localized: "this account")
        let alert = UIAlertController(
            title: String(localized: "Delete this account?"),
            message: String(localized: "This permanently deletes \(name)."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Delete \(name)"),
                                      style: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try self.store.apply(.deleteAccount, Args(["id": .string(account.id)])) }
            catch { self.presentError(i18nMessage(error)) }
        })
        present(alert, animated: true)
    }

    private func archive(_ account: AccountRow) {
        do { try store.apply(.archiveAccount, Args(["id": .string(account.id)])) }
        catch { presentError(i18nMessage(error)) }
    }

    private func confirmDeleteGroup(_ group: AccountGroupRow) {
        let alert = UIAlertController(
            title: String(localized: "Delete group?"),
            message: String(localized: "Accounts in this group become ungrouped."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Delete \(group.name)"),
                                      style: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try self.store.apply(.deleteAccountGroup, Args(["id": .string(group.id)])) }
            catch { self.presentError(i18nMessage(error)) }
        })
        present(alert, animated: true)
    }

    private func promptRenameGroup(_ group: AccountGroupRow) {
        let alert = UIAlertController(title: String(localized: "Rename group"),
                                      message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = group.name; $0.placeholder = String(localized: "Name") }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Save"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            do {
                try self.store.apply(.updateAccountGroup,
                                     Args(["id": .string(group.id), "patch": .object(["name": .string(name)])]))
            } catch { self.presentError(i18nMessage(error)) }
        })
        present(alert, animated: true)
    }

    /// Toggle a group's collapsed state and persist it.
    ///
    /// The one apply on this screen that animates. `AccountsTab` — the SwiftUI screen
    /// this was converted from, still reachable under `-uikitActivity NO` — wraps the
    /// same toggle in `withAnimation`; the conversion dropped it, so the two disagreed
    /// about the same gesture on the same screen.
    ///
    /// Reconfiguring ONLY this group's row is what makes animating safe. Its chevron
    /// flips, so it genuinely changed; every other visible row is untouched by a
    /// collapse, and marking them would have UIKit crossfade the lot while the group
    /// opens.
    private func toggleGroup(_ name: String) {
        let nowCollapsed = !collapsedGroups.contains(name)
        if nowCollapsed { collapsedGroups.insert(name) } else { collapsedGroups.remove(name) }
        AccountGroupCollapse.setCollapsed(name, nowCollapsed, ledger: store.activeLedgerId)
        applySnapshot(animated: true, reconfiguring: [Self.groupPrefix + name])
    }

    // MARK: Presentation

    private func presentAccountSheet(_ account: AccountRow?) {
        present(hostSheet(AccountSheet(account: account, defaultCurrency: store.baseCurrency)), animated: true)
    }

    /// All Transactions and Holdings PUSH in compact mode. In column mode they push
    /// inside the supplementary column's own navigation controller, which is what the
    /// SwiftUI screen's `NavigationLink` did there.
    private func pushOrSelectHoldings() {
        navigationController?.pushViewController(HoldingsVC(), animated: true)
    }

    private func pushAllTransactions() {
        navigationController?.pushViewController(ActivityFeedVC(), animated: true)
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

    /// A deep link stashed an account id + switched to this tab — open it.
    private func consumeFocus() {
        guard let id = router.focusedId, store.accounts.contains(where: { $0.id == id }) else { return }
        router.focusedId = nil
        if onSelect != nil {
            selectedID = id
            onSelect?(id)
        } else {
            navigationController?.pushViewController(AccountDetailVC(accountId: id), animated: true)
        }
    }
}

// MARK: - Selection, context menus

extension AccountsListVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        // The net-worth row and the state rows are not interactive.
        return !(id == Self.netWorthID || id == Self.loadingID
                 || id == Self.emptyID || id == Self.noResultsID)
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

        if id == Self.allTxnsID {
            cv.deselectItem(at: indexPath, animated: true)
            pushAllTransactions()
            return
        }

        if id.hasPrefix(Self.groupPrefix) {
            cv.deselectItem(at: indexPath, animated: false)
            toggleGroup(String(id.dropFirst(Self.groupPrefix.count)))
            return
        }

        guard accountByID[id] != nil else { return }
        if let onSelect {
            // Stay selected: the row is the current state of the column beside it, not a
            // button that fired.
            selectedID = id
            onSelect(id)
            return
        }
        cv.deselectItem(at: indexPath, animated: true)
        navigationController?.pushViewController(AccountDetailVC(accountId: id), animated: true)
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isReordering, let id = dataSource.itemIdentifier(for: indexPath) else { return nil }

        // Long-press a group → Edit / Delete, on real groups only.
        if id.hasPrefix(Self.groupPrefix) {
            let name = String(id.dropFirst(Self.groupPrefix.count))
            guard let group = store.accountGroups.first(where: { $0.name == name }) else { return nil }
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

        guard let account = accountByID[id] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: String(localized: "Add Transaction"),
                             image: UIImage(systemName: "plus")) { _ in
                        guard let self else { return }
                        self.present(self.hostSheet(AddTransactionSheet(defaultAccountId: account.id)),
                                     animated: true)
                    },
                    UIAction(title: String(localized: "Reconcile"),
                             image: UIImage(systemName: "checkmark.circle")) { _ in
                        guard let self else { return }
                        self.present(self.hostSheet(ReconcileSheet(preselect: account.id)), animated: true)
                    },
                ]),
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: String(localized: "Edit"),
                             image: UIImage(systemName: "pencil")) { _ in self?.presentAccountSheet(account) },
                    UIAction(title: String(localized: "Archive"),
                             image: UIImage(systemName: "archivebox")) { _ in self?.archive(account) },
                    UIAction(title: String(localized: "Delete"),
                             image: UIImage(systemName: "trash"),
                             attributes: .destructive) { _ in self?.confirmDelete(account) },
                ]),
            ])
        }
    }
}

extension AccountsListVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        search = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}

// MARK: - Drag to reorder
//
// Two drop zones, not three: an account has no nesting, only a position. The top half of
// the target row inserts BEFORE it and the bottom half AFTER — which is exactly the
// `to:` index `AccountReorder.applyVisibleMove` expects, because it mirrors SwiftUI's
// `onMove` destination convention (an index in the pre-removal array).

extension AccountsListVC: UICollectionViewDragDelegate {
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

extension AccountsListVC: UICollectionViewDropDelegate {
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
        let collapsed = Set(store.accountGroups.map(\.id)).subtracting(expandedReorderGroups)
        let visible = AccountReorder.visibleRows(reorderRows, collapsed: collapsed)
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

        reorderRows = AccountReorder.applyVisibleMove(reorderRows, collapsed: collapsed,
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
