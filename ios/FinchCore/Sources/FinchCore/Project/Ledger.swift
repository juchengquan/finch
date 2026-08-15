import Foundation

/// A ledger (the top-level book). The display field is `base` (NOT `baseCurrency`)
/// to match the web client `Tx`/ledger JSON — see WIRE_FORMAT §2.2. Sourced from
/// the `ledgers` table (`base_currency` column → `base`).
public struct Ledger: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let base: String       // from the `base_currency` column
    public let color: String?
    public let tagline: String?
    /// The ledger the DB marks `is_default = 1` — the one the app activates on a
    /// fresh launch, and after an import.
    ///
    /// Carried as a FIELD because the list no longer sorts by it. It used to be
    /// communicated by POSITION alone: `Projection.ledgers` ordered
    /// `is_default DESC, name` and two call sites read `ledgers.first` to mean "the
    /// default one". That coupling is what made activating a ledger jump it to the
    /// top of the list. Mirrors the web `LedgerRow.isDefault`, which has always
    /// carried it explicitly.
    public let isDefault: Bool

    public init(id: String, name: String, base: String, color: String?, tagline: String?,
                isDefault: Bool = false) {
        self.id = id; self.name = name; self.base = base; self.color = color; self.tagline = tagline
        self.isDefault = isDefault
    }
}

/// The user's manual ledger order (`app_state.ledgerOrder`).
///
/// Native-first, exactly like `setBudgetOrder`: the order is a list of ids in
/// app_state rather than a `sort_order` column, so it needs no schema change, no
/// migration and no `SCHEMA_VERSION` bump — and the web (frozen, and with no
/// reorder UI) simply ignores the key. Ledgers are global, not ledger-scoped, so
/// this is one flat array where budgets keep a per-ledger map.
public enum LedgerOrder {
    /// The app_state key holding the id list.
    public static let stateKey = "ledgerOrder"

    /// Apply `order` to `ledgers`, which arrive sorted by name.
    ///
    /// Ids missing from `order` — a ledger created or imported since the last drag —
    /// keep their incoming (name) order and sit AFTER the ordered ones, matching how
    /// `applyBudgetOrder` treats a newly created budget. Ids in `order` that no longer
    /// exist are ignored rather than leaving a hole.
    public static func sorted(_ ledgers: [Ledger], order: [String]) -> [Ledger] {
        guard !order.isEmpty else { return ledgers }
        let pos = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return ledgers.enumerated().sorted {
            (pos[$0.element.id] ?? order.count + $0.offset) < (pos[$1.element.id] ?? order.count + $1.offset)
        }.map(\.element)
    }
}
