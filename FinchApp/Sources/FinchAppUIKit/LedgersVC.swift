#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// `LedgerListView` converted to UIKit — the ledger list.
///
/// **Why this one, and why with its detail.** The ledger flow is the last hosted
/// SwiftUI scroll view left in the UIKit shell: `RootTabBarController` presents
/// `LedgerListView` inside a `.rightSlideDrill` cover even under `-uikitActivity YES`,
/// where every other screen is native. Converting the list ALONE would have made
/// things worse, not better — a native list pushing a hosted `LedgerDetailView` is
/// reproducer B exactly (a hosted SwiftUI scroll view at navigation depth), so the
/// detail had to land in the same change. See `LedgerDetailVC`.
///
/// Sheets stay in SwiftUI (`AddLedgerSheet`, `EditLedgerSheet`): they are presented,
/// never pushed, so they cannot shadow, and they own write forms it would be reckless
/// to retype.
final class LedgersVC: UIViewController {

    private let store = FinchStore.shared
    private let gate = BiometricGate.shared
    private var cancellables = Set<AnyCancellable>()

    /// Selection mode. `nil` → compact: a row PUSHES its detail. Non-nil → this list
    /// drives a split view's detail column and reports the id instead.
    ///
    /// The UIKit counterpart of the `selection: Binding<String?>?` the SwiftUI screens
    /// carry. A closure rather than a binding because the owner here is a view
    /// controller, and because the list never needs to read the value back — only the
    /// highlight does, and that comes through `selectedID`.
    private let onSelect: ((String) -> Void)?
    /// Fires when this screen leaves a navigation stack — the back button or the
    /// interactive swipe-back. When the ledger is PUSHED onto a tab's stack (rather
    /// than presented as a modal) nothing else tells the shell it closed, so
    /// `router.showLedger` would stay true and the corner control would do nothing on
    /// the next tap. The nav controller's delegate slot is already taken by
    /// `TabChromeVC`, which is why this is a callback and not a second delegate.
    var onPoppedFromStack: (() -> Void)?
    /// The row to show as selected, when a split view owns the selection.
    var selectedID: String? {
        didSet { guard selectedID != oldValue else { return }; applySnapshot() }
    }

    init(onSelect: ((String) -> Void)? = nil) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private enum SectionID: Hashable { case ledgers }
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!

    /// Ledger by id, so the diffable ids stay `Hashable` strings.
    private var ledgerByID: [String: Ledger] = [:]

    /// Reorder mode, entered from the ⋯ overflow like Accounts, Budgets and
    /// Categories. The draft order lives here until ✓ — ✕ throws it away without a
    /// write, so a drag that looked wrong costs nothing.
    ///
    /// A flat `[String]` where those three screens need a row model: ledgers have no
    /// groups and nothing nests, so the whole move is one `move(fromOffsets:toOffset:)`.
    private var isReordering = false
    private var reorderIDs: [String] = []
    /// The id under the finger. `localObject` usually carries it, but a drop that
    /// lands with no items still needs to know what was lifted.
    private var draggingID: String?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { onPoppedFromStack?() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Ledgers")
        configureCollectionView()
        configureDataSource()
        configureToolbar()
        applySnapshot()

        // `ledgers` is @Published; `activeLedgerId` drives the checkmark, and the net
        // worth column moves with the transactions.
        Publishers.Merge3(store.$ledgers.map { _ in () },
                          store.$activeLedgerId.map { _ in () },
                          store.$txns.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applySnapshot() }
            .store(in: &cancellables)
        // The net-worth column is masked at build time; hide-amounts is not one of
        // the three slices above.
        store.$privacyMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        config.trailingSwipeActionsConfigurationProvider = { [weak self] ip in
            self?.swipeActions(at: ip)
        }
        config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
            self?.leadingSwipeActions(at: ip)
        }
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = false   // only in reorder mode
        // Named so a UI test can assert this list's ORDER. `app.cells` is not enough:
        // the ledger flow is PUSHED over Accounts, whose rows stay in the hierarchy and
        // answer the same query, so an unscoped order assertion reads both screens.
        collectionView.accessibilityIdentifier = "ledgerList"
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
            guard let self, let ledger = self.ledgerByID[id] else { return }
            // Identifies the ROW rather than its text, so a UI test can assert the
            // order without depending on labels: the net worth is stripped in reorder
            // mode, and a cell's staticTexts are not returned in visual order, so
            // matching on text reads a different string in each mode.
            cell.accessibilityIdentifier = "ledger.\(ledger.id)"
            var cfg = cell.defaultContentConfiguration()
            cfg.text = ledger.name
            cfg.secondaryText = ledger.base          // the base currency, as the SwiftUI row shows
            cfg.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            cfg.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = cfg

            // Reorder mode: a grip and nothing else. The net worth is not what you are
            // arranging, and the disclosure chevron would promise a push that the mode
            // has disabled. The tick goes too — `Projection.ledgers` no longer sorts by
            // it, so which ledger is active has nothing to do with where its row sits.
            if self.isReordering {
                cell.accessories = [reorderGripAccessory()]
                return
            }

            // Trailing: net worth, preceded by a tick on the active ledger.
            let worth = UILabel()
            worth.text = self.store.displayMoney(self.store.netWorth(forLedger: ledger.id),
                                                 forLedger: ledger.id)
            worth.font = .preferredFont(forTextStyle: .subheadline)
            worth.textColor = .secondaryLabel
            var accessories: [UICellAccessory] = [
                .customView(configuration: .init(customView: worth, placement: .trailing()))
            ]
            // A chevron promises a push. In selection mode the row fills a column
            // beside it instead, so the chevron would be a lie.
            if self.onSelect == nil { accessories.append(.disclosureIndicator()) }
            if ledger.id == self.store.activeLedgerId {
                let tick = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
                tick.tintColor = .tintColor
                tick.contentMode = .scaleAspectFit
                accessories.insert(.customView(configuration: .init(customView: tick, placement: .trailing())),
                                   at: 0)
            }
            cell.accessories = accessories
        }
        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    private func configureToolbar() {
        // Reorder mode owns the whole bar: ✕ discards the draft, ✓ writes it. Same
        // shape as Accounts / Budgets / Categories, down to the icons.
        guard !isReordering else {
            let cancel = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                         primaryAction: UIAction { [weak self] _ in
                // Clear FIRST so `persistReorder`'s guard no-ops if anything else
                // reaches it — the other three screens all discard this way.
                self?.reorderIDs = []
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
            return
        }
        // The back button owns the left slot outside reorder mode; leaving the ✕ there
        // would strand the user on a screen with two ways back and no way out.
        navigationItem.leftBarButtonItems = nil

        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
            self?.presentAddLedger()
        })
        add.accessibilityLabel = String(localized: "Add Ledger")

        let reorder = UIAction(title: String(localized: "Reorder"),
                               image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
            self?.enterReorder()
        }
        // Nothing to arrange with one ledger — the same threshold Delete uses.
        reorder.attributes = store.ledgers.count > 1 ? [] : .disabled
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [reorder]))
        more.accessibilityLabel = String(localized: "More")

        navigationItem.rightBarButtonItems = [more, add]
    }

    // MARK: Reorder

    private func enterReorder() {
        isReordering = true
        reorderIDs = store.ledgers.map(\.id)
        collectionView.dragInteractionEnabled = true
        configureToolbar()
        applySnapshot()
    }

    private func exitReorder() {
        isReordering = false
        reorderIDs = []
        draggingID = nil
        collectionView.dragInteractionEnabled = false
        configureToolbar()
        applySnapshot()
    }

    /// Persist on ✓ — one `setLedgerOrder` for the whole drag, through the action
    /// chokepoint like every other write on this screen.
    ///
    /// Writes the full list every time rather than a diff: the stored order is the
    /// list, so a partial write would leave the untouched ids to fall back on name and
    /// silently undo an earlier drag.
    private func persistReorder() {
        guard !reorderIDs.isEmpty, reorderIDs != store.ledgers.map(\.id) else { return }
        do {
            try store.apply(.setLedgerOrder, Args(["ledgerIds": .array(reorderIDs.map { .string($0) })]))
        } catch {
            presentError(i18nMessage(error))
        }
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
        ledgerByID = Dictionary(uniqueKeysWithValues: store.ledgers.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.ledgers])
        // While reordering, the draft is the truth on screen — `store.ledgers` still
        // holds the saved order until ✓.
        //
        // The draft is reconciled against the store on every republish rather than
        // just filtered for display: a ledger deleted under the mode (an import, a
        // sync) would otherwise name a row that no longer exists, and one that arrived
        // would be invisible until ✓ and then be missing from the very list ✓ writes.
        if isReordering {
            reorderIDs = LedgerReorder.reconciled(draft: reorderIDs, live: store.ledgers.map(\.id))
        }
        snap.appendItems(isReordering ? reorderIDs : store.ledgers.map(\.id), toSection: .ledgers)
        // Ids are stable across a rename or an active-ledger switch, so carried-over
        // rows must be told to re-read or the tick and the net worth stay stale.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)

        // Re-assert the highlight: `apply` clears the selection, so without this the
        // row stops looking selected every time a net worth changes underneath it.
        if let selectedID, let ip = dataSource.indexPath(for: selectedID) {
            collectionView.selectItem(at: ip, animated: false, scrollPosition: [])
        }
    }

    // MARK: Actions

    /// Delete is disabled at one ledger: the app has no meaningful state with none,
    /// and the SwiftUI row disables it the same way.
    /// Leading swipe: make this ledger the active one.
    ///
    /// The constructive verb goes on the LEADING edge, matching `AccountsListVC` and
    /// `BudgetsListVC`, which both put "Add Transaction" there with Delete trailing.
    ///
    /// No confirmation, deliberately: the detail page's row has never asked for one and
    /// the action is reversible — activating another ledger undoes it. A dialog on a
    /// reversible switch is how people learn to dismiss dialogs unread, which is what
    /// makes the Delete confirmation stop working.
    ///
    /// The ACTIVE ledger gets a grey, non-acting "Active" chip rather than nothing, so
    /// the gesture answers the same on every row. `UIContextualAction` has no
    /// `isEnabled`, so "disabled" can only mean "does nothing" — hence a checkmark and a
    /// status word rather than a button that visibly refuses. Known limitation:
    /// VoiceOver still announces it as a button; contextual actions expose no disabled
    /// trait.
    private func leadingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let ledger = ledgerByID[id] else { return nil }

        if ledger.id == store.activeLedgerId {
            // "Current", not "Active": the existing "Active" key is translated 启用
            // ("enable"), which is a verb about switching something on. This is a status
            // — the ledger the app is scoped to — and 当前 matches "Make active ledger"
            // (设为当前账本), so the two read as the same concept in both languages.
            // Deliberately NOT built through `SwipeAction.make`: this is a status
            // badge, not an action — it does nothing, so a haptic would announce
            // something that did not happen.
            let current = UIContextualAction(style: .normal,
                                             title: String(localized: "Current")) { _, _, done in
                done(false)   // a status, not an action
            }
            current.image = UIImage(systemName: "checkmark")
            current.backgroundColor = .systemGray3
            let config = UISwipeActionsConfiguration(actions: [current])
            config.performsFirstActionWithFullSwipe = false
            return config
        }

        let activate = SwipeAction.make(String(localized: "Make active"),
                                        systemImage: "checkmark.circle",
                                        tint: .systemBlue) { [weak self] done in
            guard let self else { return done(false) }
            do {
                // The SAME write the detail page makes (`LedgerDetailVC.makeActive`):
                // through the action chokepoint, not a bare assignment. Two ways to
                // switch ledgers is exactly the drift the conversion notes warn about.
                try self.store.apply(.setDefaultLedger, Args(["id": .string(ledger.id)]))
                self.store.activeLedgerId = ledger.id
                done(true)
            } catch {
                self.presentError(i18nMessage(error))
                done(false)
            }
        }
        let config = UISwipeActionsConfiguration(actions: [activate])
        // Same reason Delete here is `.normal`: switching a whole ledger should be a
        // deliberate tap on the revealed button, not the end of a fast flick.
        config.performsFirstActionWithFullSwipe = false
        return config
    }

    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let ledger = ledgerByID[id], store.ledgers.count > 1 else { return nil }
        let delete = SwipeAction.make(String(localized: "Delete"),
                                      systemImage: "trash",
                                      tint: .systemRed) { [weak self] done in
            self?.confirmDelete(ledger); done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func confirmDelete(_ ledger: Ledger) {
        // A centred alert, not a row-anchored dialog — the SwiftUI screen notes that a
        // row-anchored popout dies with the row when the swipe collapses.
        let alert = UIAlertController(
            title: String(localized: "Delete this ledger?"),
            message: String(localized: "This permanently deletes \(ledger.name) and all its data."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Delete \(ledger.name)"),
                                      style: .destructive) { [weak self] _ in self?.delete(ledger) })
        present(alert, animated: true)
    }

    private func delete(_ ledger: Ledger) {
        // Destroying a ledger destroys its data — gated like the other sensitive
        // actions, exactly as the SwiftUI screen gates it.
        Task { @MainActor in
            guard await gate.confirmSensitive() else { return }
            do {
                try store.apply(.deleteLedger, Args(["id": .string(ledger.id)]))
                if store.activeLedgerId == ledger.id {
                    // Deleted the active one — fall back to whatever remains, or the
                    // rest of the app is scoped to a ledger that no longer exists.
                    store.activeLedgerId = store.defaultLedgerId
                }
            } catch {
                presentError(i18nMessage(error))
            }
        }
    }

    private func presentAddLedger() {
        let host = UIHostingController(rootView:
            AddLedgerSheet()
                .environmentObject(store)
                .environmentObject(gate))
        present(host, animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

extension LedgersVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // A tap in reorder mode is a mis-hit, not a drill: the rows are being arranged.
        guard !isReordering else { return cv.deselectItem(at: indexPath, animated: false) }
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if let onSelect {
            // Stay selected: the row is the current state of the column beside it, not
            // a button that fired.
            selectedID = id
            onSelect(id)
            return
        }
        cv.deselectItem(at: indexPath, animated: true)
        navigationController?.pushViewController(LedgerDetailVC(ledgerId: id), animated: true)
    }

    /// Long-press delete, mirroring the SwiftUI row's context menu.
    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isReordering,
              let id = dataSource.itemIdentifier(for: indexPath),
              let ledger = ledgerByID[id], store.ledgers.count > 1 else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Delete"),
                         image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in self?.confirmDelete(ledger) }
            ])
        }
    }
}

extension LedgersVC: UICollectionViewDragDelegate {
    func collectionView(_ cv: UICollectionView,
                        itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard isReordering, let id = dataSource.itemIdentifier(for: indexPath) else { return [] }
        draggingID = id
        let item = UIDragItem(itemProvider: NSItemProvider(object: id as NSString))
        item.localObject = id
        return [item]
    }

    func collectionView(_ cv: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        draggingID = nil
    }
}

extension LedgersVC: UICollectionViewDropDelegate {
    func collectionView(_ cv: UICollectionView, canHandle session: UIDropSession) -> Bool {
        isReordering && draggingID != nil
    }

    func collectionView(_ cv: UICollectionView,
                        dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard isReordering else { return UICollectionViewDropProposal(operation: .cancel) }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    /// The drop math is `BudgetsListVC`'s, minus the group flattening: the row under
    /// the finger decides the slot, and which HALF of it the finger is over decides
    /// whether the dragged ledger lands above or below it. Past the last row means
    /// last.
    func collectionView(_ cv: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard isReordering,
              let sourceID = coordinator.items.first?.dragItem.localObject as? String ?? draggingID,
              let src = reorderIDs.firstIndex(of: sourceID) else { return }

        let point = coordinator.session.location(in: cv)
        var destination: Int
        if let indexPath = cv.indexPathForItem(at: point),
           let targetID = dataSource.itemIdentifier(for: indexPath),
           let target = reorderIDs.firstIndex(of: targetID) {
            let frame = cv.cellForItem(at: indexPath)?.frame ?? .zero
            let below = frame.height > 0 && (point.y - frame.minY) / frame.height > 0.5
            destination = below ? target + 1 : target
        } else {
            destination = reorderIDs.count      // dropped past the last row
        }
        guard destination != src, destination != src + 1 else { return }

        var next = reorderIDs
        next.move(fromOffsets: IndexSet(integer: src), toOffset: destination)
        reorderIDs = next
        applySnapshot()

        // Hand the lifted preview back to UIKit so it animates INTO its new row.
        // Without this the drop plays the CANCEL animation — flying the preview back
        // to the lift point — before the reordered list appears underneath it.
        // `applySnapshot` above is synchronous, so this index path is already the new one.
        if let item = coordinator.items.first?.dragItem,
           let dest = dataSource.indexPath(for: sourceID) {
            coordinator.drop(item, toItemAt: dest)
        }
    }
}
#endif
