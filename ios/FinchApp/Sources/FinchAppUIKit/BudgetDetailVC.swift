#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 3: `BudgetDetailView` converted to UIKit.
///
/// Cycle progress, a History chart whose past-cycle bars tap through to that
/// cycle's numbers and transactions, this cycle's matched transactions, and
/// edit / clear-pending / delete. Re-resolves the budget from the store and pops
/// when it is deleted, as the SwiftUI screen did.
///
/// The display blocks — the progress summary, the bar chart, the selected-cycle
/// summary — stay SwiftUI, hosted via `UIHostingConfiguration`. They are LEAF
/// views (no scroll view, no navigation), so the `UICollectionView` remains the
/// screen's scroll view; hosting a whole SwiftUI scroll view in a pushed page is
/// reproducer B and brings the iOS 26 resume shadow back. Keeping them verbatim
/// also keeps their string-catalog keys identical to the SwiftUI original.
///
/// Rows here are tap-only: the SwiftUI screen gave budget-matched transactions no
/// swipe actions, so neither does this one.
final class BudgetDetailVC: UIViewController {

    // MARK: Model

    private let budgetId: String
    private let store = FinchStore.shared
    private var budget: BudgetRow? { store.budgets.first { $0.id == budgetId } }
    private var cancellables = Set<AnyCancellable>()

    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true

    /// Tapped History bar → that past cycle's numbers and transactions, keyed by the
    /// cycle's `from` so the selection survives reprojection. The current cycle never
    /// selects — its details are already on the page.
    private var selectedCycleFrom: String?

    private enum SectionID: Hashable {
        case progress
        case history
        case selectedCycle
        /// A multi-month SELECTED cycle's month buckets. Namespaced apart from
        /// `.month` because the current cycle and a selected past cycle can both be
        /// month-sectioned at once, and two equal section identifiers in one snapshot
        /// is a hard crash rather than a layout quirk.
        case selMonth(String)
        case income
        case pending
        case thisCycle
        case month(String)

        /// The progress block and the pending block are bare `Section { }` in SwiftUI.
        var wantsHeader: Bool {
            switch self {
            case .progress, .pending: return false
            default: return true
            }
        }
    }

    private static let progressID = "__progress__"
    private static let chartID = "__chart__"
    private static let chartCaptionID = "__chart_caption__"
    private static let chartHintID = "__chart_hint__"
    private static let cycleSummaryID = "__cycle_summary__"
    private static let savedID = "__saved__"
    private static let targetDateID = "__target_date__"
    private static let pendingAmountID = "__pending_amount__"
    private static let clearPendingID = "__clear_pending__"
    private static let emptyCycleID = "__empty_cycle__"
    private static let emptySelectedID = "__empty_selected__"
    /// Selected-cycle rows carry a prefix for the same reason `.selMonth` exists:
    /// duplicate item identifiers in one snapshot are fatal.
    private static let selPrefix = "__sel__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    /// Item id → transaction, so the prefixed selected-cycle ids resolve too.
    private var txByItemID: [String: Tx] = [:]
    private var sectionIDs: [SectionID] = []

    private enum HeaderContent {
        case plain(String?)
        case month(label: String, trailing: String)
    }
    private var headerContent: [SectionID: HeaderContent] = [:]

    private var moreItem: UIBarButtonItem?

    init(budgetId: String) {
        self.budgetId = budgetId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Inline, like the account page and like the SwiftUI budget screen: a large
        // title belongs to a place you navigate TO (Accounts, Budgets, Settings), not
        // to a thing you opened.
        //
        // The account page also pins its figure in the bar as a subtitle, and this
        // screen deliberately does NOT follow it there. That worked because the
        // subtitle REPLACED the balance card. This card can't be replaced — it
        // carries the progress bar, the remaining amount and the cycle range as well
        // as the figure — so a subtitle would just repeat a number sitting 40pt
        // below it. Put a figure in the bar only when it lets you delete whatever was
        // showing it.
        navigationItem.largeTitleDisplayMode = .never
        title = budget?.name
        configureCollectionView()
        configureDataSource()
        configureToolbar()
        applySnapshot()

        store.$txns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
        // Clears the launch spinner when the projection lands on an empty cycle, where
        // `$txns` alone cannot tell "not projected yet" from "nothing matched".
        TxnsLoadingCell.observe(store) { [weak self] in self?.applySnapshot() }
            .store(in: &cancellables)
        store.$budgets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // The SwiftUI screen re-resolved by id and dismissed when the budget
                // vanished, which is how Delete leaves the page.
                guard let budget = self.budget else {
                    self.navigationController?.popViewController(animated: true)
                    return
                }
                self.title = budget.name
                self.configureToolbar()   // the ⋯ actions close over the budget
                self.applySnapshot()
            }
            .store(in: &cancellables)
        store.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureToolbar() }   // `+` disables with no accounts
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            config.headerMode = (kind?.wantsHeader ?? true) ? .supplementary : .none
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
            guard let self, let budget = self.budget else { return }
            cell.accessories = []

            switch id {
            case Self.progressID:
                let p = Selectors.budgetProgress(budget, self.store.txns, self.store.budgetToday, self.store.categoryNodes)
                cell.contentConfiguration = UIHostingConfiguration {
                    BudgetProgressBlock(store: self.store, budget: budget, progress: p)
                }

            case Self.chartID:
                let points = self.cycleHistory()
                let selected = self.selectedCycle()
                cell.contentConfiguration = UIHostingConfiguration {
                    BarChart(data: points.map { p in
                        BarChart.DataPoint(label: Self.cycleLabel(p.from, budget.frequency),
                                           value: p.used,
                                           color: (p.over ? Color.red : Color.green)
                                               .opacity(Self.barOpacity(p, selected: selected)))
                    }, xLabel: "Cycle", yLabel: "Spent", format: self.store.displayMoneyBase, masked: self.store.privacyMode,
                       referenceLine: budget.amount,
                       onBarTap: { [weak self] i in
                        guard let self, i < points.count else { return }
                        let p = points[i]
                        self.selectedCycleFrom = (p.isCurrent || p.from == self.selectedCycleFrom) ? nil : p.from
                        self.applySnapshot()
                    })
                    .frame(height: 140)
                }

            case Self.chartCaptionID:
                let points = self.cycleHistory()
                cell.contentConfiguration = UIHostingConfiguration {
                    Text("Last \(points.count) cycles · budget \(self.store.displayMoneyBase(budget.amount))")
                        .font(.caption).foregroundStyle(.secondary)
                }

            case Self.chartHintID:
                cell.contentConfiguration = UIHostingConfiguration {
                    Text("Tap a bar to view a past cycle")
                        .font(.caption2).foregroundStyle(.secondary)
                }

            case Self.cycleSummaryID:
                guard let cycle = self.selectedCycle() else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    CycleSummaryBlock(store: self.store, cycle: cycle)
                }

            case Self.savedID:
                self.configureValueRow(cell, String(localized: "Saved"),
                                       self.store.displayMoneyBase(budget.saved))

            case Self.targetDateID:
                let text = budget.endDate.flatMap { AppDate.isoDay.date(from: $0) }
                    .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
                self.configureValueRow(cell, String(localized: "Target date"), text)

            case Self.pendingAmountID:
                self.configureValueRow(cell, String(localized: "Pending next cycle"),
                                       self.store.displayMoneyBase(budget.pendingAmount ?? 0))

            case Self.clearPendingID:
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "Clear pending amount")
                cfg.textProperties.color = .tintColor
                cell.contentConfiguration = cfg

            case Self.emptyCycleID, Self.emptySelectedID:
                // Budget "spent" comes from the deferred txns projection, so at launch
                // the bars read $0 and the list reads empty for ~600ms before filling.
                if TxnsLoadingCell.shouldSpin(self.store) {
                    TxnsLoadingCell.configure(cell)
                    return
                }
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "No matching transactions")
                cfg.textProperties.font = .preferredFont(forTextStyle: .caption1)
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg

            default:
                guard let tx = self.txByItemID[id] else { return }
                // The SwiftUI row is merchant over date, with the amount trailing —
                // NOT the account detail's category-first row.
                var cfg = cell.defaultContentConfiguration()
                cfg.text = tx.merchant
                cfg.secondaryText = tx.date
                // A default list cell is taller than the SwiftUI List row it stands
                // in for. Tuned against the measured reference: the SwiftUI row is
                // ~66pt, the untouched default was ~72pt, and 8pt margins overshot
                // to ~58pt. Same kind of tuning TxRowCell does for the hosted rows.
                cfg.directionalLayoutMargins.top = 12
                cfg.directionalLayoutMargins.bottom = 12
                cell.contentConfiguration = cfg
                let amount = UILabel()
                amount.text = self.store.displayMoneyBase(tx.amount)
                amount.font = .preferredFont(forTextStyle: .body)
                cell.accessories = [.customView(configuration: .init(customView: amount, placement: .trailing()))]
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            self?.configureHeader(view, at: indexPath)
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    /// A `LabeledContent` row: label left, value trailing in secondary text.
    private func configureValueRow(_ cell: UICollectionViewListCell, _ label: String, _ value: String) {
        var cfg = cell.defaultContentConfiguration()
        cfg.text = label
        cell.contentConfiguration = cfg
        let trailing = UILabel()
        trailing.text = value
        trailing.font = .preferredFont(forTextStyle: .body)
        trailing.textColor = .secondaryLabel
        cell.accessories = [.customView(configuration: .init(customView: trailing, placement: .trailing()))]
    }

    /// Reads text computed in `applySnapshot` rather than deriving it from
    /// `dataSource.snapshot()`, which returns the PRE-apply sections while an apply is
    /// in flight and left every figure one generation stale on the account detail.
    private func configureHeader(_ view: UICollectionViewListCell, at indexPath: IndexPath) {
        guard sectionIDs.indices.contains(indexPath.section) else { return }
        switch headerContent[sectionIDs[indexPath.section]] {
        case .month(let label, let trailing):
            view.contentConfiguration = UIHostingConfiguration {
                MonthSectionHeader(label: label, trailing: trailing)
            }
        case .plain(let text):
            var cfg = view.defaultContentConfiguration()
            cfg.text = text
            view.contentConfiguration = cfg
        case nil:
            view.contentConfiguration = view.defaultContentConfiguration()
        }
    }

    private func refreshVisibleHeaders() {
        let kind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            guard let view = collectionView.supplementaryView(forElementKind: kind, at: indexPath)
                    as? UICollectionViewListCell else { continue }
            configureHeader(view, at: indexPath)
        }
    }

    // MARK: Snapshot

    private func cycleHistory() -> [Selectors.BudgetCyclePoint] {
        guard let budget else { return [] }
        return Selectors.budgetCycleHistory(budget, store.txns, store.today, store.categoryNodes)
    }

    /// The selected past cycle, if the tapped bar still exists after reprojection.
    private func selectedCycle() -> Selectors.BudgetCyclePoint? {
        cycleHistory().first { $0.from == selectedCycleFrom && !$0.isCurrent }
    }

    private func applySnapshot() {
        guard let budget else { return }
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        var headers: [SectionID: HeaderContent] = [:]
        var txns: [String: Tx] = [:]

        snap.appendSections([.progress])
        snap.appendItems([Self.progressID], toSection: .progress)

        // History, and the drill-in for a tapped bar. Hidden under two cycles — one
        // bar answers nothing.
        let points = cycleHistory()
        let selected = selectedCycle()
        if points.count >= 2 {
            snap.appendSections([.history])
            var historyItems = [Self.chartID, Self.chartCaptionID]
            if selected == nil { historyItems.append(Self.chartHintID) }
            snap.appendItems(historyItems, toSection: .history)
            headers[.history] = .plain(String(localized: "History"))

            if let cycle = selected {
                let cycleTx = Selectors.budgetMatchedTransactions(
                    budget, store.txns, from: cycle.from, to: cycle.to, store.categoryNodes)
                let sections = MonthGrouping.sections(cycleTx)
                let sectioned = groupByMonth && sections.count > 1

                snap.appendSections([.selectedCycle])
                headers[.selectedCycle] = .plain(String(localized: "Selected cycle"))
                var items = [Self.cycleSummaryID]
                // A multi-month cycle puts its rows in month sections BELOW the
                // summary; otherwise they stay flat inside it.
                if !sectioned {
                    if cycleTx.isEmpty {
                        items.append(Self.emptySelectedID)
                    } else {
                        for tx in cycleTx {
                            let id = Self.selPrefix + tx.id
                            txns[id] = tx
                            items.append(id)
                        }
                    }
                }
                snap.appendItems(items, toSection: .selectedCycle)

                if sectioned {
                    for section in sections {
                        snap.appendSections([.selMonth(section.id)])
                        let ids = section.txns.map { tx -> String in
                            let id = Self.selPrefix + tx.id
                            txns[id] = tx
                            return id
                        }
                        snap.appendItems(ids, toSection: .selMonth(section.id))
                        headers[.selMonth(section.id)] = monthHeader(section.id, section.txns)
                    }
                }
            }
        }

        if budget.type == "income" {
            snap.appendSections([.income])
            var items = [Self.savedID]
            if budget.endDate != nil { items.append(Self.targetDateID) }
            snap.appendItems(items, toSection: .income)
            headers[.income] = .plain(String(localized: "Income"))
        }

        if budget.pendingAmount != nil {
            snap.appendSections([.pending])
            snap.appendItems([Self.pendingAmountID, Self.clearPendingID], toSection: .pending)
        }

        // This cycle's matched transactions. Only a multi-month cycle (quarterly,
        // yearly, or off-calendar) benefits from sectioning; a monthly cycle is one
        // month, so it stays a flat "This cycle".
        let cycleTx = Selectors.budgetMatchedTransactions(budget, store.txns, store.budgetToday, store.categoryNodes)
        let sections = MonthGrouping.sections(cycleTx)
        if cycleTx.isEmpty {
            snap.appendSections([.thisCycle])
            snap.appendItems([Self.emptyCycleID], toSection: .thisCycle)
            headers[.thisCycle] = .plain(String(localized: "This cycle"))
        } else if groupByMonth && sections.count > 1 {
            for section in sections {
                snap.appendSections([.month(section.id)])
                for tx in section.txns { txns[tx.id] = tx }
                snap.appendItems(section.txns.map(\.id), toSection: .month(section.id))
                headers[.month(section.id)] = monthHeader(section.id, section.txns)
            }
        } else {
            snap.appendSections([.thisCycle])
            for tx in cycleTx { txns[tx.id] = tx }
            snap.appendItems(cycleTx.map(\.id), toSection: .thisCycle)
            headers[.thisCycle] = .plain(String(localized: "This cycle"))
        }

        // Diffable keeps the EXISTING cell for an unchanged item identifier. Nearly
        // every cell here is computed — progress figures, the chart, the cycle
        // summary, all under fixed identifiers — so without this they would keep
        // drawing pre-write values. Reconfiguring re-runs the provider for the
        // visible cells only, so it is not a reload.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        txByItemID = txns
        headerContent = headers
        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false) { [weak self] in
            self?.refreshVisibleHeaders()
        }
    }

    /// A month bucket's header: label and the month's net change. No running balance —
    /// a budget has none.
    private func monthHeader(_ key: String, _ txns: [Tx]) -> HeaderContent {
        .month(label: MonthGrouping.label(key),
               trailing: store.displayMoneyBase(MonthGrouping.net(txns)))
    }

    /// Selected bar stays full-strength and the rest recede; with no selection the
    /// current cycle is the muted one, since it is provisional — still filling.
    private static func barOpacity(_ p: Selectors.BudgetCyclePoint,
                                  selected: Selectors.BudgetCyclePoint?) -> Double {
        if let selected { return p.from == selected.from ? 1 : 0.3 }
        return p.isCurrent ? 0.45 : 1
    }

    /// Short x-axis label for a cycle start: month name for monthly, month + year for
    /// quarterly/yearly (labels must be UNIQUE across the windows — equal categorical
    /// labels collapse into one x-band and stack the bars), M/d for day-grained.
    private static func cycleLabel(_ from: String, _ frequency: String) -> String {
        let parts = from.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return from }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        switch frequency {
        case "daily", "weekly", "biweekly": return "\(m)/\(d)"
        case "quarterly", "yearly": return "\(months[m - 1]) '\(parts[0].suffix(2))"
        default: return months[m - 1]   // monthly — 6 consecutive months never repeat
        }
    }

    // MARK: Bars and writes

    private func configureToolbar() {
        // Budget-aware add: the sheet opens pre-filled with this budget's category
        // (and account, when the budget is account-filtered), so the transaction lands
        // in this budget.
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in
            self?.presentAddTransaction()
        })
        add.accessibilityLabel = String(localized: "Add Transaction")
        add.isEnabled = !store.accounts.isEmpty

        let menu = UIMenu(children: [
            UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.presentEdit()
            },
            UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                     attributes: .destructive) { [weak self] _ in
                self?.confirmDelete()
            },
        ])
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
        moreItem = more
        navigationItem.rightBarButtonItems = [more, add]
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    private func confirmDelete() {
        guard let budget else { return }
        let sheet = UIAlertController(title: String(localized: "Delete this budget?"),
                                      message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.apply(.removeBudget, Args(["id": .string(budget.id)])) }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = moreItem
        present(sheet, animated: true)
    }

    private func clearPending() {
        guard let budget else { return }
        run { try store.apply(.clearPendingAmount, Args(["id": .string(budget.id)])) }
    }

    // MARK: Sheets — still SwiftUI, hosted. They are presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    private func presentEdit() {
        guard let budget else { return }
        present(hosted(BudgetSheet(budget: budget)), animated: true)
    }

    private func presentAddTransaction() {
        guard let budget else { return }
        present(hosted(AddTransactionSheet(defaultAccountId: budget.accountIds.first,
                                           defaultCategoryId: budget.categoryIds.first)), animated: true)
    }
}

extension BudgetDetailVC: UICollectionViewDelegate {
    /// Only the transaction rows and the clear-pending button do anything. Everything
    /// else is display — and the chart hosts an interactive SwiftUI view, which the
    /// cell's own selection would swallow.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return txByItemID[id] != nil || id == Self.clearPendingID
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if id == Self.clearPendingID { clearPending(); return }
        guard let tx = txByItemID[id] else { return }
        present(hosted(EditTransactionSheet(txn: tx)), animated: true)
    }
}

/// The cycle-progress block, kept verbatim from `BudgetDetailView` — same layout and,
/// because the `Text` literals are unchanged, the same string-catalog keys.
private struct BudgetProgressBlock: View {
    @ObservedObject var store: FinchStore
    let budget: BudgetRow
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(store.displayMoneyBase(progress.used)) of \(store.displayMoneyBase(progress.base))")
                    .fontWeight(.medium)
                Spacer()
                if progress.over { Text("Over").font(.caption).foregroundStyle(.red) }
            }
            if budget.carryForward > 0 {
                Text("+\(store.displayMoneyBase(budget.carryForward)) carried over")
                    .font(.caption).foregroundStyle(.green)
            }
            ProgressView(value: min(Double(progress.pct) / 100, 1.0))
                .tint(progress.over ? .red : (progress.pct >= 70 ? .yellow : .green))
            HStack {
                Text("\(store.displayMoneyBase(progress.remaining)) left")
                    .font(.caption).foregroundStyle(.secondary)
                if budget.rollover != 0 {
                    Text("· Rolls over").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(progress.from) – \(progress.to)").font(.caption2).foregroundStyle(.secondary)
            }
            if !budget.accountIds.isEmpty {
                let names = budget.accountIds
                    .compactMap { id in store.accounts.first { $0.id == id }?.name }
                    .joined(separator: ", ")
                if !names.isEmpty {
                    Text("Accounts: \(names)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The selected past cycle's summary — the same used/base/remaining block as the
/// header, windowed to that cycle. Also verbatim from the SwiftUI screen.
private struct CycleSummaryBlock: View {
    @ObservedObject var store: FinchStore
    let cycle: Selectors.BudgetCyclePoint

    var body: some View {
        let pct = cycle.base != 0 ? Int((cycle.used / cycle.base * 100).rounded()) : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(store.displayMoneyBase(cycle.used)) of \(store.displayMoneyBase(cycle.base))")
                    .fontWeight(.medium)
                Spacer()
                if cycle.over { Text("Over").font(.caption).foregroundStyle(.red) }
            }
            ProgressView(value: min(Double(pct) / 100, 1.0))
                .tint(cycle.over ? .red : (pct >= 70 ? .yellow : .green))
            HStack {
                Text("\(store.displayMoneyBase(cycle.base - cycle.used)) left")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(cycle.from) – \(cycle.to)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
/// Seeds the shell's floating `+` with this budget's first account and category —
/// the same pair `BudgetDetailView` publishes as a preference. `budget` is nil only
/// while the row is being deleted, where an unseeded sheet is the right fallback.
extension BudgetDetailVC: AddTxFABProviding {
    var addTxContext: AddTxContext {
        AddTxContext(accountId: budget?.accountIds.first,
                     categoryId: budget?.categoryIds.first)
    }
}

#endif
