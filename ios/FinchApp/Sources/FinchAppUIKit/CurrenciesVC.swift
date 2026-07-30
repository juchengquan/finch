#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 8: `CurrenciesView` converted to UIKit.
///
/// The FX home: auto-update controls on top, then every ISO currency (hub first,
/// tracked A–Z, rest A–Z, searchable) with its latest USD-per-unit rate and a
/// tracking switch. Tap a row for that currency's history. Writes stay on the
/// `setTrackedCurrencies` chokepoint and `RateAutoUpdater`.
///
/// The interesting shape here is new to this migration: every currency row is BOTH
/// a navigation target and a live control. In SwiftUI that was a `NavigationLink`
/// wrapping a `Toggle`; here the row's tap belongs to the collection view and the
/// switch is a trailing `UISwitch` accessory, which receives its own touches — the
/// same split that made the Categories expand-chevron work. Hosting the switch
/// inside the cell's content instead would put an interactive SwiftUI control under
/// the cell's selection, and the cell would swallow it.
///
/// The rate list is derived, not stored: `fxCurrencyRows` / `fxFilterRows` produce
/// the same ordering and filtering the SwiftUI screen used, so hub-first, tracked
/// A–Z, rest A–Z cannot drift.
final class CurrenciesVC: UIViewController {

    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private var query = ""
    private var refreshing = false
    private var lastUpdated: Date?
    /// The transient result of a manual refresh, shown beside "Refresh now".
    private var refreshNote: String?

    private enum SectionID: Hashable { case controls, active, inactive }

    private static let autoUpdateID = "__auto_update__"
    private static let lastUpdatedID = "__last_updated__"
    private static let refreshID = "__refresh__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []
    private var rowByCode: [String: FxCurrencyRow] = [:]

    /// The user's explicit tracked set, or the seeded default before any toggle.
    private var effectiveTracked: [String] {
        fxEffectiveTracked(stored: store.trackedCurrencies,
                           fallback: RateAutoUpdater.currenciesInUse(store: store))
    }

    /// Absent key == ON — the default-ON semantics shared with `RateAutoUpdater`.
    private var autoUpdateEnabled: Bool {
        UserDefaults.standard.object(forKey: RateAutoUpdater.toggleKey) == nil
            || UserDefaults.standard.bool(forKey: RateAutoUpdater.toggleKey)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Currencies")
        navigationItem.largeTitleDisplayMode = .never
        // The SwiftUI screen read the stamp in `.onAppear`.
        lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date
        configureCollectionView()
        configureDataSource()
        configureSearch()
        applySnapshot()

        // Rates and the tracked set both arrive through a reprojection.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        // Only the controls section carries a footer, so the layout is built
        // per-section rather than once.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .none
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            if kind == .controls { config.footerMode = .supplementary }
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
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self else { return }
            cell.accessories = []

            switch id {
            case Self.autoUpdateID:
                cell.contentConfiguration = UIHostingConfiguration {
                    HostedToggleRow(title: String(localized: "Auto-update exchange rates"),
                                    isOn: self.autoUpdateEnabled) { on in
                        UserDefaults.standard.set(on, forKey: RateAutoUpdater.toggleKey)
                    }
                }

            case Self.lastUpdatedID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Last updated")
                cell.contentConfiguration = cfg
                let value = UILabel()
                value.text = self.lastUpdated?.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale))
                value.font = .preferredFont(forTextStyle: .body)
                value.textColor = .secondaryLabel
                cell.accessories = [.customView(configuration: .init(customView: value, placement: .trailing()))]

            case Self.refreshID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Refresh now")
                cfg.textProperties.color = self.refreshing ? .secondaryLabel : .tintColor
                cell.contentConfiguration = cfg
                if self.refreshing {
                    let spinner = UIActivityIndicatorView(style: .medium)
                    spinner.startAnimating()
                    cell.accessories = [.customView(configuration: .init(customView: spinner, placement: .trailing()))]
                } else if let note = self.refreshNote {
                    let label = UILabel()
                    label.text = note
                    label.font = .preferredFont(forTextStyle: .caption1)
                    label.textColor = .secondaryLabel
                    cell.accessories = [.customView(configuration: .init(customView: label, placement: .trailing()))]
                }

            default:
                guard let row = self.rowByCode[id] else { return }
                let name = FxCurrencyInfo.name(row.code)
                let code = FxCurrencyInfo.symbol(row.code).map { "\(row.code) (\($0))" } ?? row.code
                let subtitle = row.isHub ? String(localized: "\(name) · hub") : name
                let rate = row.rate.map { String(format: "%.4f", $0) } ?? "—"
                let hasRate = row.rate != nil

                // The whole row is hosted so SwiftUI draws the switch — see
                // HostedToggleRows for why UIKit cannot. The hub (USD) is always
                // active and gets no toggle, so it stays a plain tappable row.
                if row.isHub {
                    cell.contentConfiguration = UIHostingConfiguration {
                        Button { self.openHistory(row.code) } label: {
                            CurrencyRowLabel(code: code, subtitle: subtitle,
                                             rate: rate, hasRate: hasRate)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    let activate = String(localized: "Activate \(row.code)")
                    cell.contentConfiguration = UIHostingConfiguration {
                        HostedToggleNavigationRow(
                            isOn: row.tracked,
                            toggleLabel: activate,
                            onChange: { [weak self] on in self?.setTracked(row.code, on) },
                            onTap: { [weak self] in self?.openHistory(row.code) }
                        ) {
                            CurrencyRowLabel(code: code, subtitle: subtitle,
                                             rate: rate, hasRate: hasRate)
                        }
                    }
                }
            }
        }

        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { view, _, _ in
            var cfg = view.defaultContentConfiguration()
            cfg.text = String(localized: "Fetches daily reference rates for your currencies from free reference-rate services. Only currency codes are sent.")
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
        }
    }

    private func applySnapshot() {
        let rows = fxFilterRows(
            fxCurrencyRows(all: Currencies.iso, rates: store.exchangeRates, tracked: effectiveTracked),
            query: query)
        rowByCode = Dictionary(uniqueKeysWithValues: rows.map { ($0.code, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.controls])
        var controls = [Self.autoUpdateID]
        if lastUpdated != nil { controls.append(Self.lastUpdatedID) }
        controls.append(Self.refreshID)
        snap.appendItems(controls, toSection: .controls)

        // Active = the hub plus tracked; Inactive = everything else, omitted entirely
        // when empty (as the SwiftUI screen did).
        let active = rows.filter { $0.isHub || $0.tracked }
        snap.appendSections([.active])
        snap.appendItems(active.map(\.code), toSection: .active)

        let inactive = rows.filter { !$0.isHub && !$0.tracked }
        if !inactive.isEmpty {
            snap.appendSections([.inactive])
            snap.appendItems(inactive.map(\.code), toSection: .inactive)
        }

        // A rate arriving, a tracking flip, the refresh spinner and the note all
        // leave the identifiers alone, so the cells need an explicit reconfigure.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        sectionIDs = snap.sectionIdentifiers   // before apply — the layout reads it
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func configureSearch() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = controller
        // Plain `.searchable` on the SwiftUI screen, i.e. the DEFAULT placement, which
        // hides on scroll — unlike the Categories/Tags lists, which pin it.
        navigationItem.hidesSearchBarWhenScrolling = true
    }

    // MARK: Writes

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: String(localized: "Data problem"),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
        present(alert, animated: true)
    }

    /// Tracking writes materialize the app_state key (seed ± code). Toggling ON a
    /// currency with no stored rate fetches immediately — manual-act semantics.
    private func setTracked(_ code: String, _ on: Bool) {
        var set = Set(effectiveTracked)
        if on { set.insert(code) } else { set.remove(code) }
        do {
            try store.apply(.setTrackedCurrencies,
                            Args(["codes": .array(set.sorted().map { JSONValue.string($0) })]))
            if on && fxLatest(store.exchangeRates, code) == nil { refreshNow() }
        } catch {
            presentError(i18nMessage(error))
            applySnapshot()   // put the switch back where the data says it is
        }
    }

    /// A deliberate manual act — bypasses the toggle and the throttle.
    private func refreshNow() {
        refreshing = true
        refreshNote = nil
        applySnapshot()
        Task { @MainActor in
            let outcome = await RateAutoUpdater.refresh(store: store)
            refreshing = false
            lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date
            switch outcome {
            case .updated(let n): refreshNote = String(localized: "Updated \(n) rates")
            case .skipped: refreshNote = String(localized: "Nothing to update")
            case .failed:
                refreshNote = nil
                presentError(String(localized: "Couldn't fetch exchange rates. Check your connection and try again."))
            }
            applySnapshot()
        }
    }
}

extension CurrenciesVC {
    /// Pushed from the hosted row's button. Converted, so the drill is native.
    func openHistory(_ code: String) {
        navigationController?.pushViewController(ExchangeRateHistoryVC(currency: code), animated: true)
    }
}

/// The two-line currency label plus its rate — the non-interactive part of the row.
private struct CurrencyRowLabel: View {
    let code: String
    let subtitle: String
    let rate: String
    let hasRate: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: code)
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: rate).foregroundStyle(hasRate ? .primary : .secondary)
        }
    }
}

extension CurrenciesVC: UICollectionViewDelegate {
    /// Only "Refresh now" is a cell-level tap now. The currency rows host their own
    /// button, because a selectable cell would swallow the switch beside it.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) == Self.refreshID && !refreshing
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard dataSource.itemIdentifier(for: indexPath) == Self.refreshID else { return }
        refreshNow()
    }
}

extension CurrenciesVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}
#endif
