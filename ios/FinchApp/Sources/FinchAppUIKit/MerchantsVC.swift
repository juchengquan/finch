#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 7: `MerchantsView` converted to UIKit.
///
/// A flat, name-only list with a transaction-count pill, plus verify/unverify and
/// merge (single and multi-select). The row visual reuses `MerchantLabel`, so the
/// verified seal renders exactly as it does everywhere else.
///
/// Four things differ from the Tags screen. They look like inconsistencies but each
/// one is in the SwiftUI original, so they are preserved rather than tidied:
///   - the empty state is a FULL-SCREEN `ContentUnavailableView`, not a list row,
///     and the search bar is absent with it (the SwiftUI screen attaches
///     `.searchable` to the List branch only);
///   - the swipe order is Rename, Delete, Merge… — Tags puts Merge second;
///   - the action is called "Rename", not "Edit";
///   - Verify/Unverify exists ONLY in the context menu, never on the swipe;
///   - the delete message has two branches, because deleting a merchant that has
///     transactions does not delete them — they keep the name and lose the link.
final class MerchantsVC: UIViewController {

    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private var search = ""
    private var isSelecting = false
    private var selected: Set<String> = []

    private enum SectionID: Hashable { case rows }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var merchantByID: [String: Counterparty] = [:]
    private var counts: [String: Int] = [:]
    private var searchController: UISearchController!

    /// Lowercased `contains`, matching the SwiftUI screen (Tags uses
    /// `localizedCaseInsensitiveContains`; the difference is theirs, not a slip here).
    private var filtered: [Counterparty] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? store.merchants
                             : store.merchants.filter { $0.name.lowercased().contains(query) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Merchants")
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()

        // `counterparties` (behind `store.merchants`) is a plain property the
        // reprojection rewrites, not an @Published slice, so a slice-specific sink
        // would miss renames and verify toggles entirely.
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
            guard let self, let merchant = self.merchantByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                MerchantRowVisual(name: merchant.name,
                                  isVerified: merchant.isVerified,
                                  count: self.counts[merchant.id] ?? 0)
            }
            if self.isSelecting {
                let ticked = self.selected.contains(merchant.id)
                let mark = UIImageView(image: UIImage(systemName: ticked ? "checkmark.circle.fill" : "circle"))
                mark.tintColor = ticked ? .tintColor : .secondaryLabel
                cell.accessories = [.customView(configuration: .init(customView: mark, placement: .leading()))]
            } else {
                cell.accessories = []
            }
        }
        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    private func applySnapshot() {
        counts = Selectors.counterpartyTxCounts(store.txns, store.merchants, store.activeLedgerId)
        let visible = filtered
        merchantByID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.rows])
        snap.appendItems(visible.map(\.id), toSection: .rows)
        // A rename, a verify toggle or a changed count leaves the id alone.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)

        updateEmptyState()
        configureToolbar()
    }

    /// The SwiftUI screen swaps the whole List for a `ContentUnavailableView` and,
    /// because `.searchable` hangs off the List, loses the search bar with it. Both
    /// halves of that are reproduced here — searching an empty list is pointless, and
    /// leaving a stray search bar over the placeholder would look like a bug.
    private func updateEmptyState() {
        guard store.merchants.isEmpty else {
            contentUnavailableConfiguration = nil
            if navigationItem.searchController == nil { navigationItem.searchController = searchController }
            return
        }
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "storefront")
        config.text = String(localized: "No merchants")
        config.secondaryText = String(localized: "Merchants appear as you add transactions, or add one with +.")
        contentUnavailableConfiguration = config
        navigationItem.searchController = nil
    }

    // MARK: Bars

    private func configureSearch() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
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
            self.present(self.hosted(CounterpartyNameSheet(counterparty: nil)), animated: true)
        })
        add.accessibilityLabel = String(localized: "Add Merchant")

        // Only Merge… here — merchants have no import-from-ledger action.
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [
            UIAction(title: String(localized: "Merge…"),
                     image: UIImage(systemName: "arrow.triangle.merge")) { [weak self] _ in
                self?.isSelecting = true
                self?.selected = []
                self?.applySnapshot()
            },
        ]))
        more.accessibilityLabel = String(localized: "More")
        navigationItem.rightBarButtonItems = [more, add]
        navigationItem.leftBarButtonItems = nil
    }

    /// Rename sits at the outer edge, so a careless full swipe renames, never deletes.
    /// Note the order — Rename, Delete, Merge… — differs from Tags on purpose.
    /// In select mode the SwiftUI row carries no swipe actions at all.
    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isSelecting,
              let id = dataSource.itemIdentifier(for: indexPath),
              let merchant = merchantByID[id] else { return nil }

        let rename = UIContextualAction(style: .normal, title: String(localized: "Rename")) { [weak self] _, _, done in
            guard let self else { return done(false) }
            self.present(self.hosted(CounterpartyNameSheet(counterparty: merchant)), animated: true)
            done(true)
        }
        rename.image = UIImage(systemName: "pencil")
        rename.backgroundColor = .tintColor

        // Not `.destructive`: the alert confirms first.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(merchant); done(false)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed

        let merge = UIContextualAction(style: .normal, title: String(localized: "Merge…")) { [weak self] _, _, done in
            self?.presentMergeTargets(for: merchant); done(true)
        }
        merge.image = UIImage(systemName: "arrow.triangle.merge")
        merge.backgroundColor = .systemOrange

        return UISwipeActionsConfiguration(actions: [rename, delete, merge])
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

    private func toggleVerify(_ merchant: Counterparty) {
        run {
            try store.apply(merchant.isVerified ? .unverifyCounterparty : .verifyCounterparty,
                            Args(["id": .string(merchant.id)]))
        }
    }

    /// Two messages, because deleting a merchant that has transactions does NOT
    /// delete them — they keep the name and lose the link.
    private func confirmDelete(_ merchant: Counterparty) {
        let n = counts[merchant.id] ?? 0
        let alert = UIAlertController(
            title: String(localized: "Delete \(merchant.name)?"),
            message: n > 0
                ? String(localized: "\(merchant.name) — \(n) transactions keep the name but lose the merchant link.")
                : String(localized: "This permanently deletes \(merchant.name)."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.apply(.deleteCounterparty, Args(["id": .string(merchant.id)])) }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func promptMergeChoice(_ a: Counterparty, _ b: Counterparty) {
        let alert = UIAlertController(title: String(localized: "Keep which name?"),
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
        let byId = Dictionary(uniqueKeysWithValues: store.merchants.map { ($0.id, $0) })
        let picks = selected.compactMap { byId[$0] }
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

    private func merge(source: Counterparty, target: Counterparty) {
        run { try store.apply(.mergeCounterparty, Args(["sourceId": .string(source.id),
                                                        "targetId": .string(target.id)])) }
    }

    private func mergeMany(keeping survivor: Counterparty, from all: [Counterparty]) {
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        run {
            try store.apply(.mergeCounterparties, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false
            selected = []
        }
        applySnapshot()
    }

    /// Choice-independent union of transactions referencing either merchant. Pending
    /// rows are included, as in the SwiftUI screen.
    private func mergeTxCount(_ a: Counterparty, _ b: Counterparty) -> Int {
        let ledger = store.activeLedgerId
        return Set(Selectors.merchantTransactions(store.txns, store.merchants, a.id, ledger,
                                                  includePending: true).map(\.purchaseKey))
            .union(Selectors.merchantTransactions(store.txns, store.merchants, b.id, ledger,
                                                 includePending: true).map(\.purchaseKey))
            .count
    }

    private func mergeManyTxCount(_ merchants: [Counterparty]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for merchant in merchants {
            ids.formUnion(Selectors.merchantTransactions(store.txns, store.merchants, merchant.id,
                                                         ledger, includePending: true).map(\.purchaseKey))
        }
        return ids.count
    }

    // MARK: Sheets — SwiftUI, hosted. They are presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    /// The keep-name prompt is raised from the picker's DISMISSAL: chaining dismiss
    /// and present in one transaction can drop the second presentation.
    private func presentMergeTargets(for a: Counterparty) {
        let targets = store.merchants.filter { $0.id != a.id }
        present(hosted(MerchantMergeTargetPicker(source: a, targets: targets) { [weak self] picked in
            guard let self else { return }
            self.dismiss(animated: true) {
                if let picked { self.promptMergeChoice(a, picked) }
            }
        }), animated: true)
    }
}

extension MerchantsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return merchantByID[id] != nil
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let merchant = merchantByID[id] else { return }

        if isSelecting {
            if selected.contains(merchant.id) { selected.remove(merchant.id) }
            else { selected.insert(merchant.id) }
            applySnapshot()
            return
        }
        // Converted too — the same shared detail screen, so this drill is native end
        // to end and no hosted SwiftUI scroll view sits in a pushed page.
        navigationController?.pushViewController(TxListDetailVC(.merchant(merchant)), animated: true)
    }

    /// Verify/Unverify lives ONLY here, never on the swipe — the SwiftUI screen's
    /// choice, kept.
    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isSelecting,
              let id = dataSource.itemIdentifier(for: indexPath),
              let merchant = merchantByID[id] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Rename"), image: UIImage(systemName: "pencil")) { _ in
                    guard let self else { return }
                    self.present(self.hosted(CounterpartyNameSheet(counterparty: merchant)), animated: true)
                },
                UIAction(title: merchant.isVerified ? String(localized: "Unverify")
                                                    : String(localized: "Verify"),
                         image: UIImage(systemName: "checkmark.seal")) { _ in
                    self?.toggleVerify(merchant)
                },
                UIAction(title: String(localized: "Merge…"),
                         image: UIImage(systemName: "arrow.triangle.merge")) { _ in
                    self?.presentMergeTargets(for: merchant)
                },
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in
                    self?.confirmDelete(merchant)
                },
            ])
        }
    }
}

extension MerchantsVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        search = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}

// MARK: - Hosted leaves

/// Name (with the verified seal, via the shared `MerchantLabel`) and the count pill.
private struct MerchantRowVisual: View {
    let name: String
    let isVerified: Bool
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            MerchantLabel(name: name, isVerified: isVerified)
            Spacer(minLength: 8)
            CountPill(count: count)
        }
    }
}

/// The merge-target list — every other merchant, flat.
private struct MerchantMergeTargetPicker: View {
    let source: Counterparty
    let targets: [Counterparty]
    /// nil = cancelled.
    let onPick: (Counterparty?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if targets.isEmpty {
                    ContentUnavailableView("No other merchants", systemImage: "arrow.triangle.merge",
                                           description: Text("There's nothing to merge \(source.name) with yet."))
                } else {
                    ForEach(targets) { merchant in
                        Button { onPick(merchant) } label: {
                            MerchantLabel(name: merchant.name, isVerified: merchant.isVerified)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
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
