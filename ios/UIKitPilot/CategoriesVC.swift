import UIKit
import SwiftUI
import Combine
import FinchCore

/// `CategoriesView` converted to UIKit — the decisive pre-flight check for the
/// migration plan.
///
/// Why this screen: it is the ONE real finch screen that shadows under a UIKit
/// root, and it still shadows after adding the pinned search drawer that was the
/// last remaining structural explanation. Every other test so far took an
/// already-clean screen and showed it stayed clean, which is weak evidence.
/// This takes the FAILING case and applies the treatment.
///
/// If this is clean, conversion demonstrably fixes a screen that shadows, and the
/// migration plan is validated end to end. If it still shadows, converting pages
/// does not fix the bug either and the migration should be abandoned as a remedy.
///
/// Scope: the hierarchy, the kind picker, search, and the row content — everything
/// that determines what the scroll view renders. Not converted: reorder/drag,
/// merge/select mode, the import and copy-to-ledger sheets. Those are actions, not
/// scroll content, and they do not affect what is being measured.
final class CategoriesVC: UIViewController {

    /// `CategoryKind` is `private` to CategoriesView.swift, so the pilot carries
    /// its own copy of the same three cases. A real conversion would promote the
    /// original to internal instead.
    enum Kind: String, CaseIterable {
        case expense, income, transfer
        var label: String {
            switch self {
            case .expense:  return String(localized: "Expense")
            case .income:   return String(localized: "Income")
            case .transfer: return String(localized: "Transfer")
            }
        }
    }

    private var kind: Kind = .expense
    private var expanded: Set<String> = []
    private var search = ""
    private var cancellables = Set<AnyCancellable>()

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var flatByID: [String: FlatCategory] = [:]
    private var counts: [String: Int] = [:]

    private var rows: [CategoryRow] {
        FinchStore.shared.pickableCategories.filter { ($0.kind ?? "expense") == kind.rawValue }
    }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(rows), expanded: expanded, search: search)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Categories (UIKit)"
        navigationItem.largeTitleDisplayMode = .never
        configureKindPicker()
        configureCollectionView()
        configureDataSource()
        configureSearch()
        apply()

        // No `categories` slice is published; the screen derives from
        // `pickableCategories` and transaction counts, so track `txns`.
        FinchStore.shared.$txns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: [Tx]) in self?.apply() }
            .store(in: &cancellables)
    }

    /// The SwiftUI screen puts the kind picker in the List's first row so the list
    /// stays the primary scroll view. A UIKit segmented control in the nav bar's
    /// title view keeps the same property without a special-case cell.
    private func configureKindPicker() {
        let seg = UISegmentedControl(items: Kind.allCases.map { $0.label })
        seg.selectedSegmentIndex = Kind.allCases.firstIndex(of: kind) ?? 0
        seg.addAction(UIAction { [weak self, weak seg] _ in
            guard let self, let seg else { return }
            self.kind = Kind.allCases[seg.selectedSegmentIndex]
            self.apply()
        }, for: .valueChanged)
        navigationItem.titleView = seg
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
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
            guard let self, let item = self.flatByID[id] else { return }
            var cfg = cell.defaultContentConfiguration()
            cfg.text = item.row.name
            let n = self.counts[item.row.id] ?? 0
            cfg.secondaryText = n > 0 ? "\(n)" : nil
            // Depth as indentation — the SwiftUI screen renders the same hierarchy.
            cell.indentationLevel = item.depth
            cell.contentConfiguration = cfg
            cell.accessories = item.hasChildren
                ? [.outlineDisclosure(options: .init(style: .cell))]
                : []
        }
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) {
            cv, ip, id in cv.dequeueConfiguredReusableCell(using: cell, for: ip, item: id)
        }
    }

    private func configureSearch() {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = String(localized: "Search")
        navigationItem.searchController = sc
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func apply() {
        counts = Selectors.categoryTxCounts(FinchStore.shared.txns, FinchStore.shared.activeLedgerId)
        let items = visible
        flatByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var snap = NSDiffableDataSourceSnapshot<Int, String>()
        snap.appendSections([0])
        snap.appendItems(items.map(\.id), toSection: 0)
        dataSource.apply(snap, animatingDifferences: false)
    }
}

extension CategoriesVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        cv.deselectItem(at: ip, animated: true)
        guard let id = dataSource.itemIdentifier(for: ip), let item = flatByID[id] else { return }
        // Expand/collapse mirrors the SwiftUI screen's `expanded` set.
        if item.hasChildren {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            apply()
        }
    }
}

extension CategoriesVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        search = searchController.searchBar.text ?? ""
        apply()
    }
}
