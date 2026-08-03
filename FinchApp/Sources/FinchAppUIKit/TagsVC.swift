#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 6: `TagsView` converted to UIKit.
///
/// Tags admin — a flat, colour-only list. Structurally `CategoriesVC` minus
/// everything hierarchical: no tree, no kind picker, no reorder, and no expand
/// chevron (on the Settings lists a chevron always means "expandable parent", and
/// only Categories has those). Merge, both single and multi-select, mirrors
/// Categories exactly.
///
/// The row visual is a hosted SwiftUI LEAF reusing `TagSwatch` and `CountPill`, so
/// the swatch size and the pill stay identical to every other Settings list.
///
/// Three details differ from Categories and are deliberate, not oversights:
///   - the swipe order is Edit, Merge…, Delete (Categories puts Delete second);
///   - the delete message is shown ONLY when the tag is actually in use, and
///     names the transaction count rather than going through
///     `deleteImpactMessage` (tags have no children to promote);
///   - the empty state keys off the whole tag list, not the searched rows, so
///     searching to no matches leaves the list empty rather than claiming there
///     are no tags at all.
final class TagsVC: UIViewController {

    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private var search = ""
    private var isSelecting = false
    private var selected: Set<String> = []

    private enum SectionID: Hashable { case rows, empty }
    private static let emptyID = "__empty__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var tagByID: [String: TagRow] = [:]
    private var counts: [String: Int] = [:]

    /// Search filters by name only — tags have no tree, so this is a plain
    /// case-insensitive contains, exactly as the SwiftUI screen did.
    private var rows: [TagRow] {
        guard !search.isEmpty else { return store.tags }
        return store.tags.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Tags")
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()

        // `tags` IS an @Published slice, but the count pills depend on `txns` and a
        // rename arrives through the same reprojection, so the ObservableObject is
        // the one signal that covers everything. Same choice as CategoriesVC.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActions(at: indexPath)
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
            cell.accessories = []

            if id == Self.emptyID {
                cell.contentConfiguration = UIHostingConfiguration {
                    VStack(spacing: 8) {
                        Image(systemName: "tag").font(.largeTitle).foregroundStyle(.secondary)
                        Text(String(localized: "No tags yet")).font(.headline)
                        Text(String(localized: "Tap + to add one.")).font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
                return
            }

            guard let tag = self.tagByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                TagRowVisual(colorHex: tag.color, name: tag.name, count: self.counts[tag.id] ?? 0)
            }
            if self.isSelecting {
                let ticked = self.selected.contains(tag.id)
                let mark = UIImageView(image: UIImage(systemName: ticked ? "checkmark.circle.fill" : "circle"))
                mark.tintColor = ticked ? .tintColor : .secondaryLabel
                cell.accessories = [.customView(configuration: .init(customView: mark, placement: .leading()))]
            }
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    private func applySnapshot() {
        counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)
        let visible = rows
        tagByID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        // Keyed off the WHOLE list, not the searched rows: searching to no matches
        // must not claim there are no tags.
        if store.tags.isEmpty {
            snap.appendSections([.empty])
            snap.appendItems([Self.emptyID], toSection: .empty)
        } else {
            snap.appendSections([.rows])
            snap.appendItems(visible.map(\.id), toSection: .rows)
        }

        // Renames, recolouring, count changes and entering select mode all leave the
        // identifiers alone, so the cells need an explicit reconfigure.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        dataSource.apply(snap, animatingDifferences: false)
        configureToolbar()
    }

    // MARK: Bars

    private func configureSearch() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = controller
        navigationItem.hidesSearchBarWhenScrolling = false   // SearchableModifier pins it
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

        let add = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                  primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.present(self.hosted(TagEditSheet(tag: nil)), animated: true)
        })
        add.accessibilityLabel = String(localized: "New tag")

        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [
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

    /// Edit sits at the outer edge, so a careless full swipe edits and never deletes.
    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isSelecting,
              let id = dataSource.itemIdentifier(for: indexPath),
              let tag = tagByID[id] else { return nil }

        let edit = UIContextualAction(style: .normal, title: String(localized: "Edit")) { [weak self] _, _, done in
            guard let self else { return done(false) }
            self.present(self.hosted(TagEditSheet(tag: tag)), animated: true)
            done(true)
        }
        edit.image = UIImage(systemName: "pencil")
        edit.backgroundColor = .tintColor

        let merge = UIContextualAction(style: .normal, title: String(localized: "Merge…")) { [weak self] _, _, done in
            self?.presentMergeTargets(for: tag); done(true)
        }
        merge.image = UIImage(systemName: "arrow.triangle.merge")
        merge.backgroundColor = .systemOrange

        // Not `.destructive`: that style animates the row away before the alert is
        // answered.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(tag); done(false)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed

        return UISwipeActionsConfiguration(actions: [edit, merge, delete])
    }

    // MARK: Writes

    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    private func confirmDelete(_ tag: TagRow) {
        let n = counts[tag.id] ?? 0
        let alert = UIAlertController(
            title: String(localized: "Delete \(tag.name)?"),
            // Only when the tag is actually in use — an unused tag needs no warning.
            message: n > 0 ? String(localized: "\(tag.name) is removed from \(n) transactions.") : nil,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.apply(.deleteTag, Args(["id": .string(tag.id)])) }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func promptMergeChoice(_ a: TagRow, _ b: TagRow) {
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

    private func promptMergeMany() {
        let picks = selected.compactMap { id in store.tags.first { $0.id == id } }
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

    private func merge(source: TagRow, target: TagRow) {
        run { try store.apply(.mergeTag, Args(["sourceId": .string(source.id),
                                               "targetId": .string(target.id)])) }
    }

    private func mergeMany(keeping survivor: TagRow, from all: [TagRow]) {
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        run {
            try store.apply(.mergeTags, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false
            selected = []
        }
        applySnapshot()
    }

    /// Choice-independent union of transactions referencing either tag.
    private func mergeTxCount(_ a: TagRow, _ b: TagRow) -> Int {
        let ledger = store.activeLedgerId
        return Set(Selectors.tagTransactions(store.txns, a.id, ledger).map(\.purchaseKey))
            .union(Selectors.tagTransactions(store.txns, b.id, ledger).map(\.purchaseKey))
            .count
    }

    private func mergeManyTxCount(_ tags: [TagRow]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for tag in tags { ids.formUnion(Selectors.tagTransactions(store.txns, tag.id, ledger).map(\.purchaseKey)) }
        return ids.count
    }

    private func copyDone(_ added: Int) {
        Haptics.success()
        ToastCenter.shared.show(added > 0 ? "\(added) added" : "Nothing new to copy")
    }

    // MARK: Sheets — SwiftUI, hosted. They are presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    private func presentImport() {
        present(hosted(LedgerPickerSheet(title: "Import tags from…") { [weak self] from in
            guard let self else { return }
            self.run {
                self.copyDone(try self.store.applyReturningCount(.copyTags, Args([
                    "fromLedgerId": .string(from),
                    "toLedgerId": .string(self.store.activeLedgerId)])))
            }
        }), animated: true)
    }

    private func presentCopy(_ tag: TagRow) {
        present(hosted(LedgerPickerSheet(title: "Copy \(tag.name) to…") { [weak self] to in
            guard let self else { return }
            self.run {
                self.copyDone(try self.store.applyReturningCount(.copyTags, Args([
                    "fromLedgerId": .string(self.store.activeLedgerId),
                    "toLedgerId": .string(to),
                    "ids": .array([.string(tag.id)])])))
            }
        }), animated: true)
    }

    /// The keep-name prompt is raised from the picker's DISMISSAL, not chained into
    /// it: dismissing and presenting in one transaction can drop the second
    /// presentation. Same ordering the SwiftUI screen documented.
    private func presentMergeTargets(for a: TagRow) {
        let others = store.tags.filter { $0.id != a.id }
        present(hosted(TagMergeTargetPicker(source: a, targets: others) { [weak self] picked in
            guard let self else { return }
            self.dismiss(animated: true) {
                if let picked { self.promptMergeChoice(a, picked) }
            }
        }), animated: true)
    }
}

extension TagsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return tagByID[id] != nil
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let tag = tagByID[id] else { return }

        if isSelecting {
            // No relative-exclusion rule here: tags are flat, so any two can merge.
            if selected.contains(tag.id) { selected.remove(tag.id) } else { selected.insert(tag.id) }
            applySnapshot()
            return
        }
        // Converted too, so this drill is native end to end — no hosted SwiftUI
        // scroll view in a pushed page, which is the shape that shadows.
        navigationController?.pushViewController(TxListDetailVC(.tag(tag)), animated: true)
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isSelecting,
              let id = dataSource.itemIdentifier(for: indexPath),
              let tag = tagByID[id] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { _ in
                    guard let self else { return }
                    self.present(self.hosted(TagEditSheet(tag: tag)), animated: true)
                },
                UIAction(title: String(localized: "Merge…"),
                         image: UIImage(systemName: "arrow.triangle.merge")) { _ in
                    self?.presentMergeTargets(for: tag)
                },
                UIAction(title: String(localized: "Copy to another ledger…"),
                         image: UIImage(systemName: "square.and.arrow.up.on.square")) { _ in
                    self?.presentCopy(tag)
                },
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in
                    self?.confirmDelete(tag)
                },
            ])
        }
    }
}

extension TagsVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        search = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}

// MARK: - Hosted leaves

/// Swatch, name, count pill — reusing `TagSwatch` and `CountPill` so this row stays
/// identical to the other Settings lists. Non-interactive: the tap is UIKit's.
private struct TagRowVisual: View {
    let colorHex: String?
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            TagSwatch(hex: colorHex)
            Text(verbatim: name).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            CountPill(count: count)
        }
    }
}

/// The merge-target list — every other tag, flat.
private struct TagMergeTargetPicker: View {
    let source: TagRow
    let targets: [TagRow]
    /// nil = cancelled.
    let onPick: (TagRow?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if targets.isEmpty {
                    ContentUnavailableView("No other tags", systemImage: "arrow.triangle.merge",
                                           description: Text("There's nothing to merge \(source.name) with yet."))
                } else {
                    ForEach(targets) { tag in
                        Button { onPick(tag) } label: {
                            HStack(spacing: 10) {
                                TagSwatch(hex: tag.color)
                                Text(verbatim: tag.name).foregroundStyle(.primary)
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
