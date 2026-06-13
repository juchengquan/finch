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

    /// Full re-index of the active ledger's projected state. Called on launch
    /// and after every successful write (fire-and-forget; the in-memory store is
    /// the UI's source of truth regardless of Spotlight state).
    public func indexAll(store: FinchStore) async {
        let items = SpotlightEntity.all(from: store).map { $0.searchableItem }
        try? await index.indexSearchableItems(items)
    }

    public func deindex(_ identifiers: [String]) async {
        try? await index.deleteSearchableItems(withIdentifiers: identifiers)
    }

    /// Drop everything finch indexed (e.g. on reset/import of a different pack).
    public func clearAll() async {
        try? await index.deleteAllSearchableItems()
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

    @MainActor static func all(from store: FinchStore) -> [SpotlightEntity] {
        var out: [SpotlightEntity] = []
        out += store.txns.map { .transaction($0, merchant: $0.merchant, amount: store.displayMoneyBase($0.amount)) }
        out += store.accounts.map { .account($0) }
        let nameById = Dictionary(uniqueKeysWithValues: store.pickableCategories.map { ($0.id, $0.name) })
        out += store.pickableCategories.map { .category($0, parent: $0.parentId.flatMap { nameById[$0] }) }
        out += store.merchants.map { .merchant($0) }
        out += store.budgets.map { .budget($0) }
        return out
    }

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
