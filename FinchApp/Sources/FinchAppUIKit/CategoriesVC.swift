#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 5: `CategoriesView` converted to UIKit.
///
/// This is the conversion the whole migration was justified by. `CategoriesView`
/// is the ONE screen measured to keep the iOS 26 resume shadow even under a UIKit
/// root, while `AccountDetailView` did not — and converting it was measured to fix
/// it (`ios/docs/ios26-shadow-variant-matrix.md`, 2026-07-30 addendum). Nobody has
/// an explanation for why this screen and not that one, which is exactly why
/// conversion rather than a workaround is the fix.
///
/// A nested tree (depth capped by `Categories.maxDepth`) with three modes:
///   normal    — tap drills to the category's transactions; swipe / long-press give
///               Edit, Delete, Merge…, Copy to another ledger…
///   selecting — ⋯ → Merge…: tick two or more, then pick the survivor
///   reordering— ⋯ → Reorder: drag to reparent or resequence
///
/// The tree math is NOT reimplemented: `categoryForest` / `flattenCategories` give
/// the same visible flat list the SwiftUI screen rendered, and `CategoryReorder`
/// supplies the same drop math, so ordering, search-force-expand and the engine's
/// depth rules cannot drift.
///
/// Row visuals are a hosted SwiftUI LEAF (`CategoryRowVisual`) so the swatch, the
/// palette colours and `CountPill` stay pixel-identical. The chevron is a UIKit
/// accessory instead, because it must stay tappable independently of the row.
final class CategoriesVC: UIViewController {

    private enum Kind: String { case expense, income }

    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private var kind: Kind = .expense
    private var expanded: Set<String> = []
    private var search = ""
    private var isReordering = false
    private var isSelecting = false
    private var selected: Set<String> = []
    /// Set while a drag is in flight; `localObject` on the drag item, kept here too
    /// so the drop handler never has to load the item provider asynchronously.
    private var draggingId: String?
    /// The category folded away for the duration of a drag, if it was expanded when
    /// lifted — restored on `dragSessionDidEnd`. Nil when the dragged row was
    /// already collapsed or childless, so the restore never expands something the
    /// user had shut.
    private var collapsedForDrag: String?

    private enum SectionID: Hashable { case picker, rows, empty }

    private static let pickerID = "__kind_picker__"
    private static let emptyID = "__empty__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []
    /// The visible flat tree for the current kind / expansion / search.
    private var visible: [FlatCategory] = []
    private var flatByID: [String: FlatCategory] = [:]
    private var counts: [String: Int] = [:]

    /// Every category of the current kind, in projection (sort_order) order — what
    /// `CategoryReorder` expects, and the source for `byId`.
    private var kindRows: [CategoryRow] {
        store.pickableCategories.filter { ($0.kind ?? "expense") == kind.rawValue }
    }
    /// The in-flight tree while reordering — every drop edits THIS, not the database.
    ///
    /// Categories used to commit on each drop, alone among the reorder screens:
    /// Accounts and Budgets both hold their arrangement in memory and write once on
    /// ✓. Committing per drop meant a full ledger reprojection and the whole write
    /// side-effect set (Spotlight, notifications, widget, auto-backup, CloudKit
    /// outbox) for every single move, so a run of five drags paid all of it five
    /// times. It also left no way to back out.
    ///
    /// Empty when not reordering; `activeRows` falls back to the store then.
    private var reorderRows: [CategoryRow] = []

    /// What the screen renders and what the drop math runs against — the pending
    /// arrangement while reordering, the store otherwise.
    private var activeRows: [CategoryRow] { isReordering && !reorderRows.isEmpty ? reorderRows : kindRows }

    private var byID: [String: CategoryRow] {
        Dictionary(uniqueKeysWithValues: activeRows.map { ($0.id, $0) })
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Categories")
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()

        // `categories` is NOT an @Published slice — it is a plain property the
        // reprojection rewrites, and the SwiftUI screen picked changes up simply by
        // observing the store as an ObservableObject. This is that same signal, and
        // it also covers the count pills, which depend on txns.
        store.objectWillChange
            .receive(on: DispatchQueue.main)   // delivered after the mutation lands
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        // Merge sits on its own edge on all three power-tools screens: it acts on
        // TWO entities, not one, and three actions crowded onto the trailing edge
        // pushed the labels toward icons.
        config.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.leadingSwipeActions(at: indexPath)
        }
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActions(at: indexPath)
        }
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
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
            case Self.pickerID:
                // The picker is the list's FIRST ROW, not a safeAreaInset: that keeps
                // the collection view the primary scroll view. The SwiftUI comment
                // records that a safeAreaInset here made the title disappear.
                cell.contentConfiguration = UIHostingConfiguration {
                    Picker("", selection: Binding(
                        get: { self.kind },
                        set: { newKind in
                            // Switching kind mid-reorder would strand the pending
                            // arrangement — it belongs to the OTHER kind's rows. Commit
                            // it first, then re-seed for the kind now on screen.
                            if self.isReordering {
                                self.persistReorder()
                                self.reorderRows = []
                            }
                            self.kind = newKind
                            self.selected = []
                            if self.isReordering { self.reorderRows = self.kindRows }
                            self.applySnapshot()
                        })) {
                        Text(String(localized: "Expense")).tag(Kind.expense)
                        Text(String(localized: "Income")).tag(Kind.income)
                    }
                    .pickerStyle(.segmented)
                }
                // No card behind it — see ActivityFeedVC's mode picker. An
                // insetGrouped list gives every cell the grouped background, which
                // the bare SwiftUI picker row doesn't have.
                .margins(.top, 0)
                .margins(.bottom, Metrics.modePickerBottomGap)
                cell.backgroundConfiguration = .clear()
                return

            case Self.emptyID:
                // A LIST ROW, not a contentUnavailableConfiguration: the kind picker
                // above must stay visible so the other kind is reachable.
                let message = self.kind == .expense
                    ? String(localized: "No expense categories yet")
                    : String(localized: "No income categories yet")
                cell.contentConfiguration = UIHostingConfiguration {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(.secondary)
                        Text(verbatim: message).font(.headline)
                        Text(String(localized: "Tap + to add one.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
                return

            default:
                guard let item = self.flatByID[id] else { return }
                let row = item.row
                let map = self.byID
                let dimmed = self.isSelecting
                    && mergeSelectionDisabled(row.id, selected: self.selected, byId: map)
                cell.contentConfiguration = UIHostingConfiguration {
                    CategoryRowVisual(depth: item.depth,
                                      colorHex: effectiveColor(row, map),
                                      symbol: CategoryIcon.symbol(for: effectiveIcon(row, map)),
                                      name: row.name,
                                      count: self.counts[row.id] ?? 0,
                                      // Reorder swaps the pill for the grip rather than
                                      // adding one — see `CategoryRowVisual.showsCount`.
                                      showsCount: !self.isReordering,
                                      dimmed: dimmed)
                }
                cell.accessories = self.accessories(for: item)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    /// Leading tick in select mode; trailing expand chevron for parents, and a
    /// drag grip while reordering.
    ///
    /// The chevron is a UIKit accessory rather than part of the hosted content
    /// because it has to be tappable on its own — an interactive control inside a
    /// hosted cell fights the cell's selection. Childless rows still reserve the
    /// slot, so trailing edges line up across parent and leaf rows exactly as the
    /// SwiftUI `ExpandChevron.slot` did.
    ///
    /// Both trailing slots are `Metrics.tapTargetMin` wide. The chevron was 22×30
    /// — a third of the HIG minimum — sitting at the trailing edge of a row whose
    /// own tap DRILLS into the category's transactions, so a near-miss cost a push
    /// and a Back rather than doing nothing.
    private func accessories(for item: FlatCategory) -> [UICellAccessory] {
        var list: [UICellAccessory] = []
        if isSelecting {
            let ticked = selected.contains(item.row.id)
            let mark = UIImageView(image: UIImage(systemName: ticked ? "checkmark.circle.fill" : "circle"))
            mark.tintColor = ticked ? .tintColor : .secondaryLabel
            list.append(.customView(configuration: .init(customView: mark, placement: .leading())))
        }

        let side = Metrics.tapTargetMin
        let slot: UIView
        if item.hasChildren {
            let button = UIButton(type: .system)
            // Search force-expands the tree, so the chevron is inert while searching —
            // same rule as the SwiftUI `.disabled(!search.isEmpty)`.
            let open = expanded.contains(item.row.id) || !search.isEmpty
            button.setImage(UIImage(systemName: open ? "chevron.down" : "chevron.right"), for: .normal)
            button.tintColor = .secondaryLabel
            button.isEnabled = search.isEmpty
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if self.expanded.contains(item.row.id) { self.expanded.remove(item.row.id) }
                else { self.expanded.insert(item.row.id) }
                self.applySnapshot()
            }, for: .touchUpInside)
            slot = button
        } else {
            slot = UIView()
        }
        list.append(.customView(configuration: .init(
            customView: AccessorySquare(side: side, content: slot),
            placement: .trailing(), reservedLayoutWidth: .custom(side))))

        if isReordering { list.append(reorderGripAccessory(side: side)) }
        return list
    }

    private func applySnapshot() {
        let rows = activeRows
        counts = Selectors.categoryTxCounts(store.txns, store.activeLedgerId)
        visible = flattenCategories(categoryForest(rows), expanded: expanded, search: search)
        flatByID = Dictionary(uniqueKeysWithValues: visible.map { ($0.row.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.picker])
        snap.appendItems([Self.pickerID], toSection: .picker)
        if rows.isEmpty {
            snap.appendSections([.empty])
            snap.appendItems([Self.emptyID], toSection: .empty)
        } else {
            snap.appendSections([.rows])
            snap.appendItems(visible.map(\.row.id), toSection: .rows)
        }

        // Renames, recolouring, count changes and every mode switch leave the item
        // identifiers alone, so without this the cells would keep their old content.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
        collectionView.dragInteractionEnabled = isReordering
        configureToolbar()
    }

    // MARK: Bars

    private func configureSearch() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = controller
        // `SearchableModifier` pins the bar on iOS (.navigationBarDrawer(.always)).
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func configureToolbar() {
        if isSelecting {
            let merge = UIBarButtonItem(
                title: String(localized: "Merge (\(selected.count))"),
                primaryAction: UIAction { [weak self] _ in self?.promptMergeMany() })
            merge.isEnabled = selected.count >= 2
            let cancel = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                         primaryAction: UIAction { [weak self] _ in
                self?.isSelecting = false
                self?.selected = []
                self?.applySnapshot()
            })
            cancel.accessibilityLabel = String(localized: "Cancel")
            navigationItem.rightBarButtonItems = [merge]
            navigationItem.leftBarButtonItems = [cancel]
            return
        }

        if isReordering {
            // ✕ discards the pending arrangement, ✓ commits it — the same pair
            // Accounts and Budgets have. Categories used to offer only ✓ because
            // every drop had already been written; now there is something to cancel.
            let cancel = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                         primaryAction: UIAction { [weak self] _ in
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
            navigationItem.rightBarButtonItems = [done]
            navigationItem.leftBarButtonItems = [cancel]
            return
        }

        let add = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                  primaryAction: UIAction { [weak self] _ in self?.presentCreate() })
        add.accessibilityLabel = String(localized: "New category")

        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [
            UIAction(title: String(localized: "Reorder"),
                     image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
                guard let self else { return }
                self.isReordering = true
                self.reorderRows = self.kindRows   // snapshot the tree to edit in memory
                self.applySnapshot()
            },
            UIAction(title: String(localized: "Merge…"),
                     image: UIImage(systemName: "arrow.triangle.merge")) { [weak self] _ in
                self?.isSelecting = true
                self?.selected = []
                self?.applySnapshot()
            },
            UIAction(title: String(localized: "Import from another ledger…"),
                     image: UIImage(systemName: "square.and.arrow.down.on.square")) { [weak self] _ in
                self?.presentImport()
            },
        ]))
        more.accessibilityLabel = String(localized: "More")
        navigationItem.rightBarButtonItems = [more, add]
        navigationItem.leftBarButtonItems = nil
    }

    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isSelecting, !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let row = flatByID[id]?.row else { return nil }

        // Edit is FIRST so it sits at the outer edge and is the full-swipe action —
        // a careless full swipe edits, never deletes.
        let edit = UIContextualAction(style: .normal, title: String(localized: "Edit")) { [weak self] _, _, done in
            self?.presentEdit(row); done(true)
        }
        edit.image = UIImage(systemName: "pencil")
        edit.backgroundColor = .tintColor

        // Not `.destructive`: that style animates the row away before the
        // confirmation is answered.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(row); done(false)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed

        return UISwipeActionsConfiguration(actions: [edit, delete])
    }

    /// Merge — the leading (swipe-right) edge. See `swipeActions` for why it is not
    /// crowded in with edit and delete.
    private func leadingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let row = flatByID[id]?.row else { return nil }
        let merge = UIContextualAction(style: .normal, title: String(localized: "Merge…")) { [weak self] _, _, done in
            self?.presentMergeTargets(for: row); done(true)
        }
        merge.image = UIImage(systemName: "arrow.triangle.merge")
        merge.backgroundColor = .systemOrange
        return UISwipeActionsConfiguration(actions: [merge])
    }

    // MARK: Writes — all through the same chokepoints the SwiftUI screen used

    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    private func confirmDelete(_ row: CategoryRow) {
        let alert = UIAlertController(
            title: String(localized: "Delete \(row.name)?"),
            message: deleteImpactMessage(txCount: counts[row.id] ?? 0,
                                         subcatCount: kindRows.filter { $0.parentId == row.id }.count),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.apply(.deleteCategory, Args(["id": .string(row.id)])) }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    /// Pairwise merge: the alert picks which name survives.
    private func promptMergeChoice(_ a: CategoryRow, _ b: CategoryRow) {
        let alert = UIAlertController(title: String(localized: "Keep which name after merge?"),
                                      message: mergeImpactMessage(txCount: mergeTxCount(a, b)),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Keep \"\(a.name)\""), style: .default) { [weak self] _ in
            self?.merge(source: b, target: a)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Keep \"\(b.name)\""), style: .default) { [weak self] _ in
            self?.merge(source: a, target: b)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    /// Multi-select merge: one button per candidate survivor, as in SwiftUI.
    private func promptMergeMany() {
        let picks = selected.compactMap { byID[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard picks.count >= 2 else { return }
        let alert = UIAlertController(title: String(localized: "Keep which name?"),
                                      message: mergeImpactMessage(txCount: mergeManyTxCount(picks)),
                                      preferredStyle: .alert)
        for survivor in picks {
            alert.addAction(UIAlertAction(title: String(localized: "Keep \"\(survivor.name)\""),
                                         style: .default) { [weak self] _ in
                self?.mergeMany(keeping: survivor, from: picks)
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func merge(source: CategoryRow, target: CategoryRow) {
        run { try store.apply(.mergeCategory, Args(["sourceId": .string(source.id),
                                                    "targetId": .string(target.id)])) }
    }

    private func mergeMany(keeping survivor: CategoryRow, from all: [CategoryRow]) {
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        run {
            try store.apply(.mergeCategories, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false
            selected = []
        }
        applySnapshot()
    }

    /// Choice-independent union of transactions referencing either category.
    private func mergeTxCount(_ a: CategoryRow, _ b: CategoryRow) -> Int {
        let ledger = store.activeLedgerId
        return Set(Selectors.categoryTransactions(store.txns, a.id, ledger).map(\.purchaseKey))
            .union(Selectors.categoryTransactions(store.txns, b.id, ledger).map(\.purchaseKey))
            .count
    }

    private func mergeManyTxCount(_ rows: [CategoryRow]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for row in rows { ids.formUnion(Selectors.categoryTransactions(store.txns, row.id, ledger).map(\.purchaseKey)) }
        return ids.count
    }

    /// Apply moves through the chokepoint, in order. The engine rejects
    /// self/descendant/too-deep with a localized error; the first throw stops the run
    /// and surfaces it.
    /// Leave reorder mode and drop the working copy. Callers decide first whether
    /// to keep the arrangement (`persistReorder`) or bin it (clear `reorderRows`).
    private func exitReorder() {
        isReordering = false
        reorderRows = []
        collapsedForDrag = nil
        configureToolbar()
        applySnapshot()
    }

    /// Apply a drop to the PENDING tree. No database write — see `reorderRows`.
    private func applyMoves(_ moves: [CategoryMove]) {
        guard !moves.isEmpty else { return }
        if reorderRows.isEmpty { reorderRows = kindRows }
        var byId = Dictionary(uniqueKeysWithValues: reorderRows.map { ($0.id, $0) })
        for move in moves {
            guard let row = byId[move.id] else { continue }
            byId[move.id] = CategoryRow(id: row.id, ledgerId: row.ledgerId, name: row.name,
                                        parentId: move.parentId, kind: row.kind,
                                        icon: row.icon, color: row.color, sortOrder: move.sortOrder)
        }
        // Keep projection order: parent before child, then sort_order — what
        // `categoryForest` and `CategoryReorder` both expect of their input.
        reorderRows = reorderRows.compactMap { byId[$0.id] }
            .sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
    }

    /// Commit the pending tree in ONE action, sending only the rows that actually
    /// moved. Mirrors `AccountsListVC.persistReorder` / `BudgetsListVC.persistReorder`,
    /// which have always deferred to ✓; Categories was the outlier.
    private func persistReorder() {
        guard !reorderRows.isEmpty else { return }
        let current = Dictionary(uniqueKeysWithValues: kindRows.map { ($0.id, ($0.parentId, $0.sortOrder)) })
        let changed = reorderRows.filter { row in
            guard let cur = current[row.id] else { return false }
            return cur.0 != row.parentId || cur.1 != row.sortOrder
        }
        guard !changed.isEmpty else { return }
        run {
            try store.apply(.setCategoryOrder, Args(["moves": .array(changed.map { row in
                .object(["id": .string(row.id),
                         "parentId": row.parentId.map(JSONValue.string) ?? .null,
                         "sortOrder": .int(row.sortOrder)])
            })]))
        }
    }

    private func copyDone(_ added: Int) {
        ToastCenter.shared.show(added > 0 ? "\(added) added" : "Nothing new to copy")
        Haptics.success()
    }

    // MARK: Sheets — SwiftUI, hosted. They are presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    private func presentCreate() {
        present(hosted(CategoryEditSheet(createIn: kind.rawValue)), animated: true)
    }

    private func presentEdit(_ row: CategoryRow) {
        present(hosted(CategoryEditSheet(category: row)), animated: true)
    }

    private func presentImport() {
        present(hosted(LedgerPickerSheet(title: "Import categories from…") { [weak self] from in
            guard let self else { return }
            self.run {
                self.copyDone(try self.store.applyReturningCount(.copyCategories, Args([
                    "fromLedgerId": .string(from),
                    "toLedgerId": .string(self.store.activeLedgerId)])))
            }
        }), animated: true)
    }

    private func presentCopy(_ row: CategoryRow) {
        present(hosted(LedgerPickerSheet(title: "Copy \(row.name) to…") { [weak self] to in
            guard let self else { return }
            self.run {
                self.copyDone(try self.store.applyReturningCount(.copyCategories, Args([
                    "fromLedgerId": .string(self.store.activeLedgerId),
                    "toLedgerId": .string(to),
                    "ids": .array([.string(row.id)])])))
            }
        }), animated: true)
    }

    /// The merge-target picker. Presented, so it stays SwiftUI — and the keep-name
    /// prompt is raised from its dismissal rather than chained into it, because
    /// dismissing and presenting in one transaction can drop the second
    /// presentation. That ordering bug is documented on the SwiftUI screen.
    private func presentMergeTargets(for a: CategoryRow) {
        let map = byID
        let targets = mergeTargets(excluding: a)
        present(hosted(MergeTargetPicker(source: a, targets: targets, byId: map) { [weak self] picked in
            guard let self else { return }
            self.dismiss(animated: true) {
                if let picked { self.promptMergeChoice(a, picked) }
            }
        }), animated: true)
    }

    /// Same-kind categories eligible as a merge target: everything of this kind
    /// except `a` and `a`'s descendants. Tree-ordered for an indented list.
    private func mergeTargets(excluding a: CategoryRow) -> [FlatCategory] {
        let rows = kindRows
        let flat = flattenCategories(categoryForest(rows), expanded: Set(rows.map(\.id)), search: "")
        var excluded: Set<String> = [a.id]
        for item in flat where item.row.parentId.map(excluded.contains) == true {
            excluded.insert(item.row.id)
        }
        return flat.filter { !excluded.contains($0.row.id) }
    }
}

// MARK: - Selection and menus

extension CategoriesVC: UICollectionViewDelegate {
    /// The picker, the drop zone and the empty state are not rows. In reorder mode
    /// nothing selects — taps would fight the drag.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return flatByID[id] != nil && !isReordering
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = flatByID[id]?.row else { return }

        if isSelecting {
            // A relative of an already-ticked row cannot be ticked — merging a
            // parent into its own descendant is meaningless.
            guard !mergeSelectionDisabled(row.id, selected: selected, byId: byID) else { return }
            if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
            applySnapshot()
            return
        }

        // Converted too, so this whole drill is native — no hosted SwiftUI scroll view
        // in a pushed page, which is the shape that shadows.
        navigationController?.pushViewController(TxListDetailVC(.category(row)), animated: true)
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isSelecting, !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let row = flatByID[id]?.row else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { _ in
                    self?.presentEdit(row)
                },
                UIAction(title: String(localized: "Merge…"),
                         image: UIImage(systemName: "arrow.triangle.merge")) { _ in
                    self?.presentMergeTargets(for: row)
                },
                UIAction(title: String(localized: "Copy to another ledger…"),
                         image: UIImage(systemName: "square.and.arrow.up.on.square")) { _ in
                    self?.presentCopy(row)
                },
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in
                    self?.confirmDelete(row)
                },
            ])
        }
    }
}

extension CategoriesVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        search = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}

// MARK: - Drag to reparent and resequence
//
// The same three drop zones the SwiftUI screen used: a row's top quarter inserts
// BEFORE it, its bottom quarter AFTER it, and the middle half nests under it. The
// A drop joins the TARGET's sibling group, so landing beside a top-level row
// un-nests. The zone math reads the drop point against the target
// cell's own frame, which is what `rowHeights` + `location.y / h` did in SwiftUI.

extension CategoriesVC: UICollectionViewDragDelegate {
    func collectionView(_ cv: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        // No dragging while searching. The visible list is filtered AND
        // force-expanded, but `CategoryReorder` computes sibling order from the
        // FULL row list — so what you see is not what you'd be reordering. It also
        // makes the collapse below impossible, since search overrides `expanded`.
        // The chevron is already inert during search for the same reason.
        guard isReordering, search.isEmpty,
              let id = dataSource.itemIdentifier(for: indexPath),
              flatByID[id] != nil else { return [] }
        draggingId = id
        let item = UIDragItem(itemProvider: NSItemProvider(object: id as NSString))
        item.localObject = id      // read back synchronously on drop
        return [item]
    }

    /// Fold the dragged category's children away for the duration of the drag.
    ///
    /// A move only rewrites the dragged row's own `parent_id`/`sort_order` — its
    /// children point at it and travel with it wherever it lands. But an expanded
    /// parent lifts as ONE row while its children stay sitting in the list, so the
    /// thing under your finger reads as a single category tearing itself out of its
    /// group. Collapsing first makes that one row genuinely *be* the whole group.
    ///
    /// It also removes the drop targets that produced errors: with the children
    /// hidden you cannot drop a parent onto its own child, which `reorder` would
    /// otherwise turn into `parentId == sourceId` for the engine to reject with
    /// "A category cannot be its own parent".
    ///
    /// Done here rather than in `itemsForBeginning` so the snapshot isn't rewritten
    /// underneath UIKit while it is still assembling the lift.
    func collectionView(_ cv: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        guard let id = draggingId, expanded.contains(id) else { return }
        expanded.remove(id)
        collapsedForDrag = id
        applySnapshot()
    }

    func collectionView(_ cv: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        draggingId = nil
        // Restore the expansion, whether the drop landed, missed, or the engine
        // rejected it — so you can see the group arrived intact, and a refused move
        // gives you back exactly the tree you started with.
        if let id = collapsedForDrag {
            expanded.insert(id)
            collapsedForDrag = nil
            applySnapshot()
        }
    }
}

extension CategoriesVC: UICollectionViewDropDelegate {
    func collectionView(_ cv: UICollectionView, canHandle session: UIDropSession) -> Bool {
        isReordering && draggingId != nil
    }

    func collectionView(_ cv: UICollectionView,
                        dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard isReordering else { return UICollectionViewDropProposal(operation: .cancel) }

        // The INTENT follows the zone, because the two intents are the only way to
        // ask UIKit for the two different pieces of feedback this screen needs:
        //
        //   .insertAtDestinationIndexPath   → the list OPENS A SPACE at the boundary
        //   .insertIntoDestinationIndexPath → the row under the finger HIGHLIGHTS
        //
        // This used to return `.insertInto…` unconditionally — inherited from the
        // SwiftUI version, which gave its feedback by tinting the row — so no drag
        // could ever open a gap, whether it was going to nest or to insert between
        // two rows. Both read as "highlight a row", and where the category would
        // actually land was left to the imagination.
        //
        // Deriving both this and the drop itself from `dropTarget(at:)` is what
        // keeps the space you see and the position you get from disagreeing.
        guard let target = dropTarget(at: session.location(in: collectionView)) else {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        switch target.zone {
        case .before, .after:
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        case .into:
            return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
        }
    }

    /// The row under `point` and which of its three zones the point falls in.
    ///
    /// Deliberately shared by `dropSessionDidUpdate` and `performDropWith`: the
    /// first decides which feedback UIKit shows (a space, or a highlighted row),
    /// the second decides where the category actually goes. Computing them from
    /// two copies of this arithmetic is how a gap ends up opening in one place and
    /// the row landing in another.
    private func dropTarget(at point: CGPoint) -> (id: String, zone: CategoryDropZone)? {
        guard let indexPath = collectionView.indexPathForItem(at: point),
              let id = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let frame = collectionView.cellForItem(at: indexPath)?.frame ?? .zero
        // A drop can only go INSIDE a group that is already on screen: the receiver
        // must have children and be open. Every other row splits 50/50 into
        // before/after, so it cannot nest by accident.
        let item = flatByID[id]
        let canReceive = CategoryDropZone.canReceiveChild(
            hasChildren: item?.hasChildren ?? false,
            isExpanded: expanded.contains(id))
        return (id, CategoryDropZone.at(pointY: point.y,
                                        cellMinY: frame.minY,
                                        cellHeight: frame.height,
                                        allowsNesting: canReceive))
    }

    func collectionView(_ cv: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let source = coordinator.items.first?.dragItem.localObject as? String ?? draggingId else { return }
        let rows = activeRows

        guard let target = dropTarget(at: coordinator.session.location(in: cv)) else { return }

        guard flatByID[target.id] != nil, target.id != source else { return }

        switch target.zone {
        case .before: applyMoves(CategoryReorder.reorder(source, .before, of: target.id, in: rows))
        case .after:  applyMoves(CategoryReorder.reorder(source, .after, of: target.id, in: rows))
        case .into:
            if let move = CategoryReorder.reparent(source, under: target.id, in: rows) { applyMoves([move]) }
        }
        settle(coordinator, on: source)
    }

    /// Hand the lifted preview back to UIKit so it animates INTO its new row.
    ///
    /// Without this the drop looked slow, and it was: `performDropWith` computed the
    /// move and returned without ever telling the coordinator where the item went,
    /// so UIKit had no destination and played the CANCEL animation — flying the
    /// preview all the way back to where it was picked up — before the reprojected
    /// snapshot swapped in the new order underneath it. Half a second of motion in
    /// the wrong direction on every drop.
    ///
    /// `applySnapshot()` has to run first, and synchronously. The usual refresh
    /// arrives via `store.objectWillChange.receive(on: DispatchQueue.main)`, which
    /// hops a runloop turn even when it is already on main — so at this point
    /// `visible` still describes the PRE-move list, and the index path derived from
    /// it would point at the wrong row.
    private func settle(_ coordinator: UICollectionViewDropCoordinator, on id: String) {
        guard let item = coordinator.items.first?.dragItem else { return }
        applySnapshot()
        guard let section = sectionIDs.firstIndex(of: .rows),
              let row = visible.firstIndex(where: { $0.row.id == id }) else { return }
        coordinator.drop(item, toItemAt: IndexPath(item: row, section: section))
    }
}



// MARK: - Hosted leaves

/// The row visual, matching `CategoriesView.rowContent`: swatch, name, count pill,
/// indented by depth. Deliberately NON-interactive — the row's tap is UIKit's and
/// the chevron is a UIKit accessory, so nothing here competes for the touch.
private struct CategoryRowVisual: View {
    let depth: Int
    let colorHex: String
    let symbol: String
    let name: String
    let count: Int
    /// False while reordering, where the grip takes the pill's place.
    ///
    /// The pill is dropped rather than pushed aside so the trailing chrome stays
    /// two `tapTargetMin` slots wide in BOTH modes — the name column keeps its
    /// width and rows don't reflow when Reorder is entered or left. The count is
    /// also the one thing on the row that reorder can't change: you are arranging
    /// hierarchy, not reading spend, and the numbers return on Done.
    var showsCount: Bool = true
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 10) {
            RowGlyphView(symbol: symbol, tint: Color(hex: colorHex) ?? .secondary)
            Text(verbatim: name).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsCount { CountPill(count: count) }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .opacity(dimmed ? 0.35 : 1)
    }
}

/// The merge-target list, mirroring the sheet the SwiftUI screen presented inline.
private struct MergeTargetPicker: View {
    let source: CategoryRow
    let targets: [FlatCategory]
    let byId: [String: CategoryRow]
    /// nil = cancelled.
    let onPick: (CategoryRow?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if targets.isEmpty {
                    ContentUnavailableView("No other categories", systemImage: "arrow.triangle.merge",
                                           description: Text("There's nothing to merge \(source.name) with yet."))
                } else {
                    ForEach(targets) { item in
                        Button { onPick(item.row) } label: {
                            HStack(spacing: 10) {
                                RowGlyphView(
                                    symbol: CategoryIcon.symbol(for: effectiveIcon(item.row, byId)),
                                    tint: Color(hex: effectiveColor(item.row, byId)) ?? .secondary)
                                Text(verbatim: String(repeating: "   ", count: item.depth) + item.row.name)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Merge \(source.name) with…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onPick(nil) } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
            }
        }
    }
}
#endif
