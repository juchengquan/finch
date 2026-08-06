#if os(iOS)
import UIKit
import Combine
import FinchCore

/// Phase 4: the Settings tab ROOT converted. `SettingsTab`'s destinations went native
/// back in Phase 2 — this is the menu that reaches them.
///
/// It is the smallest conversion in the migration and almost entirely wiring: a static
/// list of ten rows in six sections, every one of which pushes a view controller that
/// already exists. No store reads, no diffing against live data, nothing to keep in
/// sync. The snapshot is applied once.
///
/// **It also removes a seam rather than adding one.** The hosted root reached those
/// same view controllers through an `environment(\.nativeRoute)` closure and a
/// `SettingsDrill -> NativeRoute` mapping, because a SwiftUI list cannot push a UIKit
/// screen directly. A native root just pushes. That indirection stays alive only for
/// `-uikitActivity NO` and for macOS, where `SettingsTab` is still the real screen.
///
/// **`SettingsTab.swift` is deliberately untouched.** macOS renders it with plain
/// `NavigationLink`s (`onDrill == nil`), and `NavigationUITests` runs its whole suite
/// once per implementation — that dual run is the only thing asserting the two stay in
/// step, so deleting the SwiftUI root would delete half the coverage.
final class SettingsListVC: UIViewController {

    /// Whether to draw the Ledger corner control.
    ///
    /// **Why this is an explicit flag and not the house `onSelect == nil` idiom.** Every
    /// other converted list — Accounts, Budgets, Scheduled, Ledgers, Activity — decides
    /// "am I a column?" from whether a selection closure was passed, because at regular
    /// width a row selects into a sibling detail column. Settings has nothing to select:
    /// on iPad it is a TWO-column tab (`threeColumnTabs` excludes it), so this screen IS
    /// the secondary column and its rows push within it exactly as on iPhone.
    ///
    /// Passing a selection closure that is never called, purely to reuse the idiom,
    /// would be a lie in the shape of consistency. The one thing that genuinely differs
    /// by width is this button, so the parameter says that and nothing else.
    ///
    /// False on iPad because `SectionSidebar` already lists Ledger as a top-level row —
    /// the same reason `AccountsListVC` and `BudgetsListVC` hide theirs in column mode.
    private let showsLedgerControl: Bool

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, Row>!
    private var cancellables = Set<AnyCancellable>()

    private let store = FinchStore.shared
    private let router = DeepLinkRouter.shared

    init(showsLedgerControl: Bool = true) {
        self.showsLedgerControl = showsLedgerControl
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Model

    /// Section order and grouping mirror `SettingsRootList` exactly. Four of the six
    /// sections are titled; the last two are deliberately untitled there, and a
    /// difference here would read as a redesign rather than a port.
    private enum SectionID: Int, Hashable, CaseIterable {
        case general, ledger, shared, data, labs, about

        var title: String? {
            switch self {
            case .general: String(localized: "General")
            case .ledger:  String(localized: "Ledger")
            case .shared:  String(localized: "Shared")
            case .data:    String(localized: "Data")
            case .labs, .about: nil
            }
        }
    }

    /// The rows, each carrying its own title, symbol and destination — so the list, the
    /// snapshot and the push cannot disagree about what a row is.
    private enum Row: Int, Hashable, CaseIterable {
        case appearance, notifications, security
        case categories, tags
        case merchants, currencies
        case backupsSync
        case powerTools
        case about

        var section: SectionID {
            switch self {
            case .appearance, .notifications, .security: .general
            case .categories, .tags: .ledger
            case .merchants, .currencies: .shared
            case .backupsSync: .data
            case .powerTools: .labs
            case .about: .about
            }
        }

        var title: String {
            switch self {
            case .appearance:    String(localized: "Appearance & Language")
            case .notifications: String(localized: "Notifications")
            case .security:      String(localized: "Security")
            case .categories:    String(localized: "Categories")
            case .tags:          String(localized: "Tags")
            case .merchants:     String(localized: "Merchants")
            case .currencies:    String(localized: "Currencies")
            case .backupsSync:   String(localized: "Backup & Sync")
            case .powerTools:    String(localized: "Experimental Labs")
            case .about:         String(localized: "About")
            }
        }

        var symbol: String {
            switch self {
            case .appearance:    "paintbrush"
            case .notifications: "bell"
            case .security:      "lock"
            case .categories:    "square.grid.2x2"
            case .tags:          "tag"
            case .merchants:     "storefront"
            case .currencies:    "dollarsign.circle"
            case .backupsSync:   "arrow.triangle.2.circlepath"
            case .powerTools:    "flask"
            case .about:         "info.circle"
            }
        }

        @MainActor func destination() -> UIViewController {
            switch self {
            case .appearance:    AppearanceSettingsVC()
            case .notifications: NotificationsSettingsVC()
            case .security:      SecuritySettingsVC()
            case .categories:    CategoriesVC()
            case .tags:          TagsVC()
            case .merchants:     MerchantsVC()
            case .currencies:    CurrenciesVC()
            case .backupsSync:   BackupSyncSettingsVC()
            case .powerTools:    PowerToolsVC()
            case .about:         AboutSettingsVC()
            }
        }
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Settings")
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        configureToolbar()
        applySnapshot()

        // The privacy button draws its own state (icon, and the on/off accessibility
        // value), so it has to be rebuilt when the mode changes from anywhere else —
        // another screen's toggle, or a deep link. `809cb9fc` fixed five converted
        // screens that showed the button and then ignored the mode.
        store.$privacyMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureToolbar() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let kind = SectionID(rawValue: index)
            config.headerMode = (kind?.title != nil) ? .supplementary : .none
            _ = self
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

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { cell, _, row in
            var cfg = cell.defaultContentConfiguration()
            cfg.text = row.title
            cfg.image = UIImage(systemName: row.symbol)
            cell.contentConfiguration = cfg
            cell.accessories = [.disclosureIndicator()]
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { view, _, indexPath in
            var cfg = view.defaultContentConfiguration()
            cfg.text = SectionID(rawValue: indexPath.section)?.title
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, Row>(collectionView: collectionView) {
            cv, indexPath, row in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: row)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    /// Applied once. Nothing here depends on the store, so there is no republish to
    /// react to and no reconfigure to get right.
    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<SectionID, Row>()
        for section in SectionID.allCases {
            snap.appendSections([section])
            snap.appendItems(Row.allCases.filter { $0.section == section }, toSection: section)
        }
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Toolbar

    private func configureToolbar() {
        // Compact only — on iPad `SectionSidebar` lists Ledger as a top-level row, so a
        // button here would be a second way to the same place. Same rule as
        // `AccountsListVC` and `BudgetsListVC`.
        if showsLedgerControl {
            let ledger = UIBarButtonItem(image: UIImage(systemName: "books.vertical"),
                                         primaryAction: UIAction { [weak self] _ in
                self?.router.showLedger = true
            })
            ledger.accessibilityLabel = String(localized: "Ledger")
            navigationItem.leftBarButtonItems = [ledger]
        } else {
            navigationItem.leftBarButtonItems = nil
        }

        // Label AND value: the value is what makes the toggle testable, and what
        // distinguishes a working control from one that renders but drives nothing.
        let privacy = UIBarButtonItem(
            image: UIImage(systemName: store.privacyMode ? "eye.slash" : "eye"),
            primaryAction: UIAction { [weak self] _ in self?.store.privacyMode.toggle() })
        privacy.accessibilityLabel = String(localized: "Privacy mode")
        privacy.accessibilityValue = store.privacyMode ? String(localized: "on") : String(localized: "off")
        navigationItem.rightBarButtonItems = [privacy]
    }
}

// MARK: - Delegate

extension SettingsListVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        navigationController?.pushViewController(row.destination(), animated: true)
    }
}
#endif
