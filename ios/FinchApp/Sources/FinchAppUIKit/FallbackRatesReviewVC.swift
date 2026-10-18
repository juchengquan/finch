#if os(iOS)
import UIKit
import Combine
import FinchCore

/// The review behind Currencies' "N rates were saved as 1:1 by mistake" notice.
///
/// Lists every rate `FallbackFxRates` flags — currency, date, how many entries it
/// converted — and removes them only on an explicit, counted confirmation. Nothing
/// is removed by opening this screen, and nothing at launch.
///
/// Entries already booked at 1:1 are COUNTED, not changed (see
/// `FinchStore+FallbackRates` for why there is no "recalculate"). Tapping a rate,
/// or the total, lists them (`TxListDetailVC.Source.bookedAtOneToOne`), each opening
/// in the Edit sheet, so "check them and correct any that are wrong" has somewhere
/// to start.
///
/// The total stays on screen after the rates are removed, for as long as the
/// review is open: removing them is what makes the entries worth checking, and
/// once Currencies' notice is gone nothing else leads back to them. Leaving the
/// review lets them go.
final class FallbackRatesReviewVC: UIViewController {

    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case rates, entries, remove }

    private static let entriesID = "__entries__"
    private static let removeID = "__remove__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []
    private var suspects: [FallbackFxRates.Suspect] = []
    private var suspectByID: [String: FallbackFxRates.Suspect] = [:]

    /// Every rate this screen has listed, removed or not, oldest first. The entries
    /// row reads these, so it outlives the rates (see the type's comment).
    private var listed: [FallbackFxRates.Suspect] = []
    /// What the entries row shows: every entry `listed` converted, each once, and
    /// how many of those a transaction list here can't show.
    private var entryTotal = 0
    private var entriesUnlisted = 0

    private static func id(_ s: FallbackFxRates.Suspect) -> String { "\(s.currency)|\(s.date)" }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Rates saved as 1:1")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        // A refresh or a rate typed elsewhere can turn a suspect row into a real one.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .none
            let kind = self?.sectionIDs.indices.contains(index) == true ? self?.sectionIDs[index] : nil
            config.footerMode = kind == .remove ? .none : .supplementary
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
            cell.accessibilityIdentifier = switch id {
            case Self.removeID: "fallback-rates-remove"
            case Self.entriesID: "fallback-rates-entries"
            default: nil
            }
            var cfg = cell.defaultContentConfiguration()
            switch id {
            case Self.entriesID:
                let n = self.entryTotal
                cfg.text = n == 1 ? String(localized: "1 entry was booked at 1:1")
                                  : String(localized: "\(n) entries were booked at 1:1")
                // The list shows the active ledger's transactions, and no ledger lists
                // an opening balance; say so rather than let the list look short.
                let m = self.entriesUnlisted
                if m > 0 {
                    cfg.secondaryText = m == 1
                        ? String(localized: "1 is an opening balance or in another ledger, so it isn't listed.")
                        : String(localized: "\(m) are opening balances or in other ledgers, so they aren't listed.")
                    cfg.secondaryTextProperties.color = .secondaryLabel
                }
                cell.accessories = [.disclosureIndicator()]
            case Self.removeID:
                cfg.text = self.removeTitle(self.suspects.count)
                cfg.textProperties.color = .systemRed
            default:
                guard let s = self.suspectByID[id] else { return }
                cfg.text = FxCurrencyInfo.symbol(s.currency).map { "\(s.currency) (\($0))" } ?? s.currency
                cfg.secondaryText = fxDisplayDay(s.date, withYear: true)
                let used: String = switch s.entryCount {
                case 0: String(localized: "Not used")
                case 1: String(localized: "1 entry")
                default: String(localized: "\(s.entryCount) entries")
                }
                if s.entryCount > 0 { cell.accessories = [.disclosureIndicator()] }
                TrailingLabel.install(on: cell, text: used, color: .secondaryLabel)
            }
            cell.contentConfiguration = cfg
        }

        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            switch self.sectionIDs[indexPath.section] {
            case .rates:
                cfg.text = String(localized: "An earlier version converted a currency it had no exchange rate for at 1:1, and saved that 1 as the currency's rate. These rates still convert it 1:1. Rates you typed or fetched are never listed here.")
            case .entries:
                cfg.text = String(localized: "Removing the rates leaves these entries as they are. They aren't recalculated, because that would change account balances and entries you have reconciled. Once a real rate is in, check them and correct any that are wrong.")
            case .remove:
                break
            }
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
        suspects = store.fallbackRateSuspects()
        let known = Set(listed.map(Self.id))
        listed = (listed + suspects.filter { !known.contains(Self.id($0)) })
            .sorted { ($0.date, $0.currency) < ($1.date, $1.currency) }
        let ids = store.fallbackRateEntryIds(listed)
        entryTotal = ids.count
        entriesUnlisted = ids.count - FallbackFxRates.rows(store.txns, entryIds: ids).count

        // Nothing left to review or to check (removed here, or became real
        // elsewhere, and no entries were booked with them): go back.
        if suspects.isEmpty && entryTotal == 0 {
            if navigationController?.topViewController === self {
                navigationController?.popViewController(animated: true)
            }
            return
        }
        suspectByID = Dictionary(uniqueKeysWithValues: suspects.map { (Self.id($0), $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        if !suspects.isEmpty {
            snap.appendSections([.rates])
            snap.appendItems(suspects.map(Self.id), toSection: .rates)
        }
        if entryTotal > 0 {
            snap.appendSections([.entries])
            snap.appendItems([Self.entriesID], toSection: .entries)
        }
        if !suspects.isEmpty {
            snap.appendSections([.remove])
            snap.appendItems([Self.removeID], toSection: .remove)
        }

        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        sectionIDs = snap.sectionIdentifiers   // before apply — the layout reads it
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func removeTitle(_ n: Int) -> String {
        n == 1 ? String(localized: "Remove 1 rate") : String(localized: "Remove \(n) rates")
    }

    // MARK: Writes

    /// The second, counted step. The action sheet names exactly what goes.
    private func confirmRemove(from source: UIView?) {
        let toRemove = suspects
        guard !toRemove.isEmpty else { return }
        let sheet = UIAlertController(
            title: nil,
            message: String(localized: "A write in these currencies will then ask for a real rate. Turn the currency on in Currencies and tap Refresh now to fetch one."),
            preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: removeTitle(toRemove.count), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.store.removeFallbackRates(toRemove)
            // The reprojection's sink re-reads. The entries row stays to be checked;
            // with none booked, an empty list pops back to Currencies.
            self.applySnapshot()
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        sheet.popoverPresentationController?.sourceRect = source?.bounds ?? .zero
        present(sheet, animated: true)
    }
}

extension FallbackRatesReviewVC: UICollectionViewDelegate {
    /// The remove row confirms; the entries row and any rate that converted
    /// something list those entries. A rate nothing used has nothing to open.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        if id == Self.removeID || id == Self.entriesID { return true }
        return (suspectByID[id]?.entryCount ?? 0) > 0
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        let source: TxListDetailVC.Source
        switch id {
        case Self.removeID:
            confirmRemove(from: cv.cellForItem(at: indexPath))
            return
        case Self.entriesID:
            // `listed`, not `suspects`: after a removal this is the only way back in.
            source = .bookedAtOneToOne(title: String(localized: "Booked at 1:1"), rates: listed)
        default:
            guard let s = suspectByID[id] else { return }
            source = .bookedAtOneToOne(title: "\(s.currency) · \(fxDisplayDay(s.date))", rates: [s])
        }
        navigationController?.pushViewController(TxListDetailVC(source), animated: true)
    }
}
#endif
