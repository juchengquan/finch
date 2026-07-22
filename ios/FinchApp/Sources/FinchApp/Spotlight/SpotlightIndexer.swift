import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import FinchCore

/// Phase 6.1 — pushes finch entities into the system Spotlight index so a
/// system-wide search ("starbucks", "chase", "groceries") surfaces finch
/// transactions / accounts / categories / merchants / budgets. The iOS analogue
/// of the web's ⌘K palette. Indexing is idempotent (same uniqueIdentifier
/// replaces), so a full re-index on launch / after a write is a cheap re-assert.
@MainActor
public final class SpotlightIndexer {
    public static let shared = SpotlightIndexer()
    private let index = CSSearchableIndex.default()
    /// The in-flight rebuild/clear. Each new one awaits its predecessor, so the
    /// delete-all + index pairs can't interleave and the LAST snapshot wins.
    private var inFlight: Task<Void, Never>?

    /// Authoritative re-index of the active ledger's projected state: drop
    /// everything finch indexed, then index the current entities. Called on
    /// launch, after every write, and after import. Clearing first means deleted
    /// rows (and a swapped-in pack's old entities) don't linger in the system
    /// index (the additive-only version left stale results — audit 2026-06-14).
    ///
    /// Snapshotting the store is the only MainActor work (cheap value copies).
    /// Building one CSSearchableItem per transaction — NumberFormatter money
    /// strings included — runs on a detached utility task, so launch / unlock /
    /// post-write re-indexes no longer stall the UI for seconds on large data
    /// (audit 2026-07-22: the foreground jam).
    public func indexAll(store: FinchStore) async {
        let snapshot = SpotlightSnapshot(store: store)
        await enqueue { [index] in
            let items = snapshot.entities().map { $0.searchableItem }
            try? await index.deleteAllSearchableItems()
            try? await index.indexSearchableItems(items)
        }
    }

    public func deindex(_ identifiers: [String]) async {
        try? await index.deleteSearchableItems(withIdentifiers: identifiers)
    }

    /// Drop everything finch indexed (e.g. on reset/import of a different pack,
    /// or when the biometric lock engages). Serialized behind any in-flight
    /// rebuild so a lock-triggered clear can't lose to a slower re-index.
    public func clearAll() async {
        await enqueue { [index] in
            try? await index.deleteAllSearchableItems()
        }
    }

    /// Run `work` off the MainActor, strictly after the previous enqueued work.
    private func enqueue(_ work: @escaping @Sendable () async -> Void) async {
        let previous = inFlight
        let task = Task.detached(priority: .utility) {
            await previous?.value
            await work()
        }
        inFlight = task
        await task.value
    }
}

/// Everything `indexAll` needs, copied off the store on the MainActor so item
/// building can leave it. Money formatting mirrors `displayMoneyBase` (privacy
/// mask → convert base→display → format) with the store's values captured at
/// snapshot time.
struct SpotlightSnapshot {
    let txns: [Tx]
    let accounts: [AccountRow]
    let categories: [CategoryRow]
    let merchants: [Counterparty]
    let budgets: [BudgetRow]
    private let masked: Bool
    private let base: String
    private let display: String
    private let rates: [String: Double]

    @MainActor init(store: FinchStore) {
        txns = store.txns; accounts = store.accounts
        categories = store.pickableCategories
        merchants = store.merchants; budgets = store.budgets
        masked = store.privacyMode
        base = store.baseCurrency; display = store.displayCurrency
        rates = store.rateMap
    }

    /// `FinchStore.displayMoneyBase` minus the store (same mask/convert/format).
    private func money(_ baseAmount: Double) -> String {
        if masked { return FinchStore.moneyMask }
        let v = Money.convert(baseAmount, from: base, to: display, rates: rates) ?? baseAmount
        return Money.format(v, currency: display)
    }

    func entities() -> [SpotlightEntity] {
        var out: [SpotlightEntity] = []
        out += txns.map { .transaction($0, merchant: $0.merchant, amount: money($0.amount)) }
        out += accounts.map { .account($0) }
        let nameById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        out += categories.map { .category($0, parent: $0.parentId.flatMap { nameById[$0] }) }
        out += merchants.map { .merchant($0) }
        out += budgets.map { .budget($0) }
        return out
    }
}

/// One indexable finch entity → a `CSSearchableItem`. Identifier shape
/// `<domain>:<id>` is parsed back by `DeepLinkRouter` on tap.
public enum SpotlightEntity {
    case transaction(Tx, merchant: String, amount: String)
    case account(AccountRow)
    case category(CategoryRow, parent: String?)
    case merchant(Counterparty)
    case budget(BudgetRow)

    var uniqueIdentifier: String {
        switch self {
        case .transaction(let t, _, _): return "tx:\(t.id)"
        case .account(let a): return "account:\(a.id)"
        case .category(let c, _): return "category:\(c.id)"
        case .merchant(let m): return "counterparty:\(m.id)"
        case .budget(let b): return "budget:\(b.id)"
        }
    }
    var domainIdentifier: String { String(uniqueIdentifier.prefix(while: { $0 != ":" })) }

    private var title: String {
        switch self {
        case .transaction(_, let merchant, _): return merchant
        case .account(let a): return a.name ?? "Account"
        case .category(let c, let parent): return parent.map { "\(c.name) › \($0)" } ?? c.name
        case .merchant(let m): return m.name
        case .budget(let b): return b.name
        }
    }
    private var contentDescription: String {
        switch self {
        case .transaction(let t, _, let amount): return "\(amount) · \(t.date)"
        case .account(let a): return (a.type ?? "account").capitalized
        case .category: return "Category"
        case .merchant: return "Merchant"
        case .budget(let b): return "Budget · \(b.frequency)"
        }
    }
    private var keywords: [String] {
        switch self {
        case .transaction(let t, let merchant, _): return [merchant, t.date, "transaction", "finch"]
        case .account(let a): return [a.name ?? "", a.type ?? "", "account", "finch"]
        case .category(let c, _): return [c.name, "category", "finch"]
        case .merchant(let m): return [m.name, "merchant", "finch"]
        case .budget(let b): return [b.name, "budget", "finch"]
        }
    }

    var searchableItem: CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .content)
        attrs.title = title
        attrs.contentDescription = contentDescription
        attrs.keywords = keywords
        return CSSearchableItem(uniqueIdentifier: uniqueIdentifier,
                                domainIdentifier: domainIdentifier, attributeSet: attrs)
    }
}
