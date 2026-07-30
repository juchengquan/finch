#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 12: `ExchangeRateHistoryView` converted to UIKit.
///
/// One currency's full rate history: a trend sparkline (only at three or more
/// points, where a line means something) above date-descending rows. Per-row delete
/// and "Delete all" both go through the `deleteExchangeRate` chokepoint, and the
/// screen pops when the last row goes.
///
/// This was the LAST hosted SwiftUI screen sitting in a pushed page. With it
/// converted, every drill chain reachable from a converted list — Categories, Tags,
/// Merchants, Currencies — is native end to end, so none of them can hit reproducer
/// B (a SwiftUI scroll view inside a push, the shape that shadows).
///
/// The sparkline and the row are hosted SwiftUI leaves: `Sparkline` and
/// `SourceBadge` already exist and are pure drawing, so rebuilding them in UIKit
/// would only invite drift in the provenance colours.
final class ExchangeRateHistoryVC: UIViewController {

    private let currency: String
    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case chart, rows }

    private static let sparklineID = "__sparkline__"
    private static let emptyID = "__empty__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    /// Keyed by date: the engine treats (date, currency) as unique, and the currency
    /// is fixed for this screen.
    private var rateByDate: [String: ExchangeRate] = [:]
    private var series: [Double] = []
    private var moreItem: UIBarButtonItem?

    /// Date-descending, as the SwiftUI screen listed them.
    private var rows: [ExchangeRate] {
        store.exchangeRates.filter { $0.currency == currency }.sorted { $0.date > $1.date }
    }

    init(currency: String) {
        self.currency = currency
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = currency
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        configureToolbar()
        applySnapshot()

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

            if id == Self.sparklineID {
                let values = self.series
                cell.contentConfiguration = UIHostingConfiguration {
                    Sparkline(values: values).frame(height: 48)
                }
                return
            }
            if id == Self.emptyID {
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "No rates yet.")
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg
                return
            }
            guard let rate = self.rateByDate[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                RateRowVisual(day: fxDisplayDay(rate.date, withYear: true),
                              rate: String(format: "%.4f", rate.rate),
                              source: rate.source)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    private func applySnapshot() {
        let current = rows
        rateByDate = Dictionary(uniqueKeysWithValues: current.map { ($0.date, $0) })
        series = fxSeries(store.exchangeRates, currency)

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        // A sparkline over one or two points draws a line that means nothing, so the
        // SwiftUI screen hid it under three. Same threshold.
        if series.count >= 3 {
            snap.appendSections([.chart])
            snap.appendItems([Self.sparklineID], toSection: .chart)
        }
        snap.appendSections([.rows])
        snap.appendItems(current.isEmpty ? [Self.emptyID] : current.map(\.date), toSection: .rows)

        // The sparkline sits under a fixed identifier and redraws from `series`, so
        // deleting a row would otherwise leave the old curve on screen.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        dataSource.apply(snap, animatingDifferences: false)
        configureToolbar()   // "Delete all" appears only while there are rows
    }

    // MARK: Bar

    private func configureToolbar() {
        var children: [UIMenuElement] = []
        if !rows.isEmpty {
            children.append(UIAction(title: String(localized: "Delete all \(currency) rates"),
                                     image: UIImage(systemName: "trash"),
                                     attributes: .destructive) { [weak self] _ in
                self?.confirmDeleteAll()
            })
        }
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"),
                                   menu: UIMenu(children: children))
        more.accessibilityLabel = String(localized: "More")
        moreItem = more
        navigationItem.rightBarButtonItems = [more]
    }

    private func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let rate = rateByDate[id] else { return nil }
        // Not `.destructive`: that style animates the row away before the alert is
        // answered.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(rate); done(false)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
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

    private func confirmDelete(_ rate: ExchangeRate) {
        let alert = UIAlertController(title: String(localized: "Delete rate?"),
                                      message: "\(currency) · \(rate.date)",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run {
                try self.store.apply(.deleteExchangeRate, Args(["date": .string(rate.date),
                                                                "currency": .string(rate.currency)]))
            }
            // The SwiftUI screen re-derived `rows` after the write and dismissed when
            // the last one went. Same rule, same place.
            if self.rows.isEmpty { self.navigationController?.popViewController(animated: true) }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func confirmDeleteAll() {
        let count = rows.count
        guard count > 0 else { return }
        let sheet = UIAlertController(title: String(localized: "Delete all \(currency) rates"),
                                      message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Delete \(count) rates"),
                                      style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run {
                for rate in self.rows {
                    try self.store.apply(.deleteExchangeRate, Args(["date": .string(rate.date),
                                                                    "currency": .string(rate.currency)]))
                }
            }
            self.navigationController?.popViewController(animated: true)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        // iPad needs an anchor; the ⋯ item is where the SwiftUI dialog was anchored.
        sheet.popoverPresentationController?.barButtonItem = moreItem
        present(sheet, animated: true)
    }
}

extension ExchangeRateHistoryVC: UICollectionViewDelegate {
    /// Rows are read-only here — the SwiftUI row was a plain HStack, not a button.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let rate = rateByDate[id] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in self?.confirmDelete(rate) },
            ])
        }
    }
}

/// Day, rate, and the provenance badge — reusing `SourceBadge` so the ECB / Yahoo /
/// manual colours cannot drift from the rest of the app.
private struct RateRowVisual: View {
    let day: String
    let rate: String
    let source: String?

    var body: some View {
        HStack {
            Text(verbatim: day)
            Spacer()
            Text(verbatim: rate)
            SourceBadge(source: source)
        }
    }
}
#endif
