import UIKit
import SwiftUI
import Combine
import FinchCore

/// `AccountDetailView` (320 lines of SwiftUI) converted to UIKit — the pilot screen.
///
/// Chosen because it exercises nearly every pattern the migration will hit:
/// month-grouped sections, a pending bucket, search, swipe actions, a toolbar with
/// an overflow menu, and sheets. Where a sheet is still SwiftUI it is presented
/// through `UIHostingController`, which is exactly what the plan's Phase 2 does —
/// sheets are presented, never pushed, so they never shadow and never need
/// converting.
///
/// Deliberately NOT converted here: the calendar view mode and the holdings
/// section. They are additive, and leaving them out keeps the pilot's effort
/// measurement honest about what a *representative* screen costs.
final class AccountDetailVC: UIViewController {

    // MARK: Model

    private let accountId: String
    private var account: AccountRow? { FinchStore.shared.accounts.first { $0.id == accountId } }
    private var searchQuery = ""
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable {
        case pending
        case month(String)
        case empty
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    /// Diffable wants Hashable ids, so the source of truth stays `Tx` keyed by id.
    private var txByID: [String: Tx] = [:]

    init(accountId: String) {
        self.accountId = accountId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = account?.name ?? "Account"
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        configureSearch()
        configureToolbar()
        applySnapshot()

        // The SwiftUI store needs no rewrite: 18 @Published properties, observed
        // here with Combine instead of by the view-update system.
        FinchStore.shared.$txns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
        FinchStore.shared.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.title = self?.account?.name ?? "Account" }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActions(at: indexPath)
        }
        let layout = UICollectionViewCompositionalLayout.list(using: config)
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
            guard let tx = self?.txByID[id] else { return }
            var cfg = cell.defaultContentConfiguration()
            // Same labelling rule as the SwiftUI TxRow: the category is the title.
            cfg.text = FinchStore.shared.categoryName(tx.category) ?? String(localized: "Uncategorized")
            cfg.secondaryText = tx.date
            cell.contentConfiguration = cfg

            // The amount, privacy-aware — same helper the SwiftUI row uses, so the
            // money rules are not reimplemented.
            let amount = UILabel()
            amount.text = FinchStore.shared.displayMoneyBase(tx.amount)
            amount.font = .preferredFont(forTextStyle: .body)
            amount.textColor = tx.amount < 0 ? .label : .systemGreen
            cell.accessories = [.customView(configuration: .init(customView: amount, placement: .trailing()))]
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self else { return }
            var cfg = view.defaultContentConfiguration()
            let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            switch section {
            case .pending:
                let n = self.dataSource.snapshot().numberOfItems(inSection: .pending)
                cfg.text = "To confirm (\(n))"
            case .month(let key):
                cfg.text = MonthGrouping.label(key)
                let ids = self.dataSource.snapshot().itemIdentifiers(inSection: section)
                let txns = ids.compactMap { self.txByID[$0] }
                cfg.secondaryText = "Income \(FinchStore.shared.displayMoneyBase(MonthGrouping.income(txns)))"
                    + " · Spent \(FinchStore.shared.displayMoneyBase(MonthGrouping.expense(txns)))"
            case .empty:
                cfg.text = "Transactions"
            }
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    /// The SwiftUI original recomputes this inside `body`; here it is explicit —
    /// which is the single biggest day-to-day difference the migration introduces.
    private func applySnapshot() {
        guard let account else { return }
        let all = FinchStore.shared.transactions(for: account.id)
        let txns = searchQuery.isEmpty ? all
            : Selectors.selectTransactions(all, ListOptions(ledgerId: FinchStore.shared.activeLedgerId,
                                                            query: searchQuery))
        txByID = Dictionary(uniqueKeysWithValues: txns.map { ($0.id, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<SectionID, String>()
        let pending = txns.filter { $0.pending == true }
        let confirmed = txns.filter { $0.pending != true }

        if !pending.isEmpty {
            snapshot.appendSections([.pending])
            snapshot.appendItems(pending.map(\.id), toSection: .pending)
        }
        if confirmed.isEmpty {
            snapshot.appendSections([.empty])
        } else {
            for section in MonthGrouping.sections(confirmed) {
                snapshot.appendSections([.month(section.id)])
                snapshot.appendItems(section.txns.map(\.id), toSection: .month(section.id))
            }
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Search / toolbar / swipe — the SwiftUI one-liners, expanded

    private func configureSearch() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Search transactions")
        navigationItem.searchController = search
        // Matches the SwiftUI screen's `.navigationBarDrawer(displayMode: .always)`.
        navigationItem.hidesSearchBarWhenScrolling = false
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
        ])
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: menu)
        navigationItem.rightBarButtonItems = [more, add]
    }

    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let tx = txByID[id] else { return nil }
        let delete = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { _, _, done in
            // The write chokepoint is unchanged by the migration — the same helper
            // the SwiftUI screen calls (it also unlinks receipt files).
            do {
                try FinchStore.shared.deleteTransaction(tx.id)
                done(true)
            } catch { done(false) }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: Sheets — still SwiftUI, hosted. They are presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(FinchStore.shared)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    private func presentAddTransaction() {
        guard let account else { return }
        present(hosted(AddTransactionSheet(defaultAccountId: account.id)), animated: true)
    }

    private func presentEditAccount() {
        guard let account else { return }
        present(hosted(AccountSheet(account: account, defaultCurrency: FinchStore.shared.baseCurrency)), animated: true)
    }

    private func presentReconcile() {
        guard let account else { return }
        present(hosted(ReconcileSheet(preselect: account.id)), animated: true)
    }
}

extension AccountDetailVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let tx = txByID[id] else { return }
        present(hosted(EditTransactionSheet(txn: tx)), animated: true)
    }
}

extension AccountDetailVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}
