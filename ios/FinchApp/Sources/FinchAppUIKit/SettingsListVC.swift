#if os(iOS)
import UIKit
import SwiftUI
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
        case privacy
        case appearance, notifications, security
        case categories, tags
        case merchants, currencies
        case backupsSync
        case powerTools
        case about

        var section: SectionID {
            switch self {
            case .privacy, .appearance, .notifications, .security: .general
            case .categories, .tags: .ledger
            case .merchants, .currencies: .shared
            case .backupsSync: .data
            case .powerTools: .labs
            case .about: .about
            }
        }

        var title: String {
            switch self {
            case .privacy:       String(localized: "Privacy mode")
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
            case .privacy:       "eye.slash"
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

        /// `nil` for a row that is a CONTROL rather than a destination. Optional
        /// rather than a fatalError branch, so the compiler keeps the two in
        /// step: adding another toggle row cannot silently push a screen.
        @MainActor func destination() -> UIViewController? {
            switch self {
            case .privacy:       nil
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
            .sink { [weak self] _ in
                self?.configureToolbar()
                // The row shows the same state the toolbar button did, so it goes
                // stale the same way — and on iPhone it is now the ONLY visible
                // indicator of the mode, so a stale one is worse than none.
                self?.applySnapshot()
            }
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
            // Hosted rather than a `defaultContentConfiguration`, for two reasons that
            // only a diff against the `-uikitActivity NO` control build surfaces — both
            // of which this migration has been caught by before (`AccountsListVC`'s
            // "All Transactions" row carries the same comment).
            //
            // 1. ACCESSIBILITY. The SwiftUI rows are `Button`s, so they announce as
            //    buttons, and tests drive them as `app.buttons["Categories"]`. A content
            //    configuration OWNS the cell's accessibility — setting
            //    `cell.accessibilityTraits` afterwards does nothing — so a plain
            //    configuration leaves the row announcing as static text. That is not a
            //    test detail: it is what VoiceOver reads out.
            //
            // 2. NO CHEVRON. `SettingsRootList` uses a plain `Button`, which draws no
            //    disclosure indicator. Adding `.disclosureIndicator()` here looked more
            //    "native" and was simply a different screen.
            // Every other row is a Label that pushes a subpage; privacy is a
            // TOGGLE and stays put. Branching here rather than adding a
            // UISwitch accessory keeps one rendering path for the whole list.
            //
            // This row is the VISIBLE home for a control that is otherwise a
            // long-press of the ledger button — without it, hiding amounts does
            // not exist for anyone who was not told the gesture.
            if row == .privacy {
                let store = self.store
                cell.contentConfiguration = UIHostingConfiguration {
                    PrivacyToggleRow(store: store, title: row.title, symbol: row.symbol)
                }
            } else {
                cell.contentConfiguration = UIHostingConfiguration {
                    Label(row.title, systemImage: row.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                }
            }
            cell.accessories = []
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

    /// Re-applied when `privacyMode` changes: the privacy row renders that state,
    /// so it is the one row here that DOES depend on the store. It used to be true
    /// that nothing did.
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

        // Label AND value: the value is what makes the toggle testable, and what
        // distinguishes a working control from one that renders but drives nothing.
        let privacy = UIBarButtonItem(
            image: UIImage(systemName: store.privacyMode ? "eye.slash" : "eye"),
            primaryAction: UIAction { [weak self] _ in self?.store.privacyMode.toggle() })
        privacy.accessibilityLabel = String(localized: "Privacy mode")
        privacy.accessibilityValue = store.privacyMode ? String(localized: "on") : String(localized: "off")
        // Same rule, different flag: this screen tracks compactness with
        // `showsLedgerControl` rather than `onSelect`. On iPhone the toolbar is
        // now empty, which is correct — the row in the list below is the visible
        // home for privacy.
        navigationItem.rightBarButtonItems = showsLedgerControl ? [] : [privacy]
    }
}

/// The privacy row's SwiftUI content.
///
/// A dedicated view with `@ObservedObject` rather than an inline `Toggle` over a
/// hand-rolled `Binding`: `UIHostingConfiguration` captures its content closure,
/// so nothing re-renders when `privacyMode` changes elsewhere. The inline version
/// flipped the store and left the switch showing its old position — and this row
/// is the ONLY visible indicator of the mode on iPhone, so a stale one is worse
/// than none.
private struct PrivacyToggleRow: View {
    @ObservedObject var store: FinchStore
    let title: String
    let symbol: String
    var body: some View {
        Toggle(isOn: $store.privacyMode) {
            Label(title, systemImage: symbol)
        }
    }
}

// MARK: - Delegate

extension SettingsListVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath),
              let destination = row.destination() else { return }
        navigationController?.pushViewController(destination, animated: true)
    }
}
#endif
