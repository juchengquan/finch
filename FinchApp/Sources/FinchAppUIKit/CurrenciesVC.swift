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

    /// `effectiveTracked` as of the moment this screen opened — and the ONLY thing
    /// that decides ordering and section membership for the rest of the visit.
    ///
    /// Toggling a currency used to re-derive the sections from the live set, so the
    /// row travelled from the lower group up into the active one the instant it was
    /// switched on: it left the finger that toggled it, took the scroll position with
    /// it, and threw VoiceOver focus. Freezing the grouping keeps the row exactly
    /// where it was touched while its switch and rate stay live.
    ///
    /// Nothing thaws it. `RootTabBarController` builds a fresh `CurrenciesVC` on every
    /// push, so leaving and returning re-tidies the list for free — which is also the
    /// only moment a row is ever seen to move.
    ///
    /// This is why the two currency sections carry NO headers: a row switched on while
    /// sitting in the lower group is only honest as long as nothing labels that group
    /// "Inactive". Don't add section titles here — `CurrencyPickerSheet` has them
    /// because it has no toggles to contradict.
    private var frozenGrouping: [String] = []

    /// Absent key == ON — the default-ON semantics shared with `RateAutoUpdater`.
    private var autoUpdateEnabled: Bool {
        UserDefaults.standard.object(forKey: RateAutoUpdater.toggleKey) == nil
            || UserDefaults.standard.bool(forKey: RateAutoUpdater.toggleKey)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Currencies")
        navigationItem.largeTitleDisplayMode = .always
        // The SwiftUI screen read the stamp in `.onAppear`.
        lastUpdated = UserDefaults.standard.object(forKey: RateAutoUpdater.stampKey) as? Date
        // Before the first `applySnapshot()` — it is what the sections are built from.
        frozenGrouping = effectiveTracked
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
            // Both tagged accessories are REUSED rather than rebuilt (see
            // ToggleAccessory / TrailingLabel), so a reused cell may carry either one
            // over from whatever row it showed last. Carrying them is only correct
            // when the incoming row wants the same pair — otherwise clear, which drops
            // the tagged views and lets the installers below build fresh ones.
            //
            // Clearing unconditionally is what this dance exists to avoid: it removes
            // an installed switch from the hierarchy, which kills iOS 26's glass on it
            // and makes it swallow the tap in progress.
            let wantsToggle: Bool, wantsLabel: Bool
            switch id {
            case Self.autoUpdateID:  wantsToggle = true;  wantsLabel = false
            case Self.lastUpdatedID: wantsToggle = false; wantsLabel = true
            // The spinner/note swap needs a real accessory reassignment, so this row
            // opts out of both tagged accessories and assigns its own below.
            case Self.refreshID:     wantsToggle = false; wantsLabel = false
            // The hub (USD) is always active and cannot be toggled off.
            default:                 wantsToggle = self.rowByCode[id]?.isHub == false
                                     wantsLabel = true
            }
            if ToggleAccessory.isInstalled(on: cell) != wantsToggle
                || TrailingLabel.isInstalled(on: cell) != wantsLabel {
                cell.accessories = []
            }

            switch id {
            case Self.autoUpdateID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Auto-update exchange rates")
                cell.contentConfiguration = cfg
                ToggleAccessory.install(on: cell, isOn: self.autoUpdateEnabled) { on in
                    UserDefaults.standard.set(on, forKey: RateAutoUpdater.toggleKey)
                }

            case Self.lastUpdatedID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Last updated")
                cell.contentConfiguration = cfg
                TrailingLabel.install(on: cell, text: self.lastUpdated?.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale)),
                                      color: .secondaryLabel)

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
                } else {
                    // Explicit: a carried-over spinner or note must go.
                    cell.accessories = []
                }

            default:
                guard let row = self.rowByCode[id] else { return }
                // Code + symbol on the first line ("EUR (€)"), the localized name on
                // the second, with the hub suffixed through the catalog.
                let name = FxCurrencyInfo.name(row.code)
                var cfg = cell.defaultContentConfiguration()
                cfg.text = FxCurrencyInfo.symbol(row.code).map { "\(row.code) (\($0))" } ?? row.code
                cfg.textProperties.font = .preferredFont(forTextStyle: .body)
                cfg.secondaryText = row.isHub ? String(localized: "\(name) · hub") : name
                cell.contentConfiguration = cfg

                // Mutated in place on a reconfigure — a fresh rate arriving must not
                // cost the row its switch.
                TrailingLabel.install(on: cell,
                                      text: row.rate.map { String(format: "%.4f", $0) } ?? "—",
                                      color: row.rate == nil ? .secondaryLabel : .label)
                // `tracked` is LIVE here; `grouped` decided the section. See FxDerive.
                if !row.isHub {
                    ToggleAccessory.install(on: cell, isOn: row.tracked,
                                            accessibilityLabel: String(localized: "Activate \(row.code)")) { [weak self] on in
                        self?.setTracked(row.code, on)
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
            fxCurrencyRows(all: Currencies.iso, rates: store.exchangeRates,
                           tracked: effectiveTracked, grouping: frozenGrouping),
            query: query)
        rowByCode = Dictionary(uniqueKeysWithValues: rows.map { ($0.code, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.controls])
        var controls = [Self.autoUpdateID]
        if lastUpdated != nil { controls.append(Self.lastUpdatedID) }
        controls.append(Self.refreshID)
        snap.appendItems(controls, toSection: .controls)

        // Active = the hub plus the FROZEN group; Inactive = everything else, omitted
        // entirely when empty (as the SwiftUI screen did). Grouping deliberately reads
        // `grouped`, not `tracked` — that is what keeps a just-toggled row in place.
        let active = rows.filter { $0.isHub || $0.grouped }
        snap.appendSections([.active])
        snap.appendItems(active.map(\.code), toSection: .active)

        let inactive = rows.filter { !$0.isHub && !$0.grouped }
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
            // Names the shortfall without guessing its cause — a provider we could
            // not reach and a currency nobody carries look identical from here.
            case .partial(let n, let requested): refreshNote = String(localized: "Updated \(n) of \(requested)")
            case .skipped: refreshNote = String(localized: "Nothing to update")
            case .failed:
                refreshNote = nil
                presentError(String(localized: "Couldn't fetch exchange rates. Check your connection and try again."))
            }
            applySnapshot()
        }
    }
}

extension CurrenciesVC: UICollectionViewDelegate {
    /// The two read-only control rows do nothing; the switch rows are still
    /// selectable, because in SwiftUI the row was a NavigationLink WITH a toggle
    /// inside it — the switch handles its own touches as a UIKit accessory.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        // The auto-update row is flipped by its SWITCH only, as in Settings.app (see
        // `ToggleAccessory`). The CURRENCY rows stay selectable: a tap there must
        // navigate to the rate history, and their switch keeps its own touches.
        if id == Self.autoUpdateID { return false }
        if id == Self.lastUpdatedID { return false }
        if id == Self.refreshID { return !refreshing }
        return rowByCode[id] != nil
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if id == Self.refreshID { refreshNow(); return }
        guard let row = rowByCode[id] else { return }
        // Converted too, so this drill is native end to end.
        navigationController?.pushViewController(
            ExchangeRateHistoryVC(currency: row.code), animated: true)
    }
}

extension CurrenciesVC: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        applySnapshot()
    }
}
#endif
