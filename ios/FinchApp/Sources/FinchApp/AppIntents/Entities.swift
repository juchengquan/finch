import AppIntents
import FinchCore

/// Phase 6.4 — App Intent entities wrapping finch reference data for Siri
/// parameter resolution. Each query reads the active ledger's projected state
/// from `FinchStore.shared`.

public struct AccountEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    public static var defaultQuery = AccountQuery()
    public let id: String
    public let name: String
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct AccountQuery: EntityQuery {
    public init() {}
    @MainActor public func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        FinchStore.shared.accounts.filter { identifiers.contains($0.id) }
            .map { AccountEntity(id: $0.id, name: $0.name ?? "Account") }
    }
    @MainActor public func suggestedEntities() async throws -> [AccountEntity] {
        FinchStore.shared.accounts.map { AccountEntity(id: $0.id, name: $0.name ?? "Account") }
    }
}

public struct CategoryEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    public static var defaultQuery = CategoryQuery()
    public let id: String
    public let name: String
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct CategoryQuery: EntityQuery {
    public init() {}
    @MainActor public func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        FinchStore.shared.pickableCategories.filter { identifiers.contains($0.id) }
            .map { CategoryEntity(id: $0.id, name: $0.name) }
    }
    @MainActor public func suggestedEntities() async throws -> [CategoryEntity] {
        FinchStore.shared.pickableCategories.map { CategoryEntity(id: $0.id, name: $0.name) }
    }
}

public struct LedgerEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ledger"
    public static var defaultQuery = LedgerQuery()
    public let id: String
    public let name: String
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct LedgerQuery: EntityQuery {
    public init() {}
    @MainActor public func entities(for identifiers: [String]) async throws -> [LedgerEntity] {
        FinchStore.shared.ledgers.filter { identifiers.contains($0.id) }
            .map { LedgerEntity(id: $0.id, name: $0.name) }
    }
    @MainActor public func suggestedEntities() async throws -> [LedgerEntity] {
        FinchStore.shared.ledgers.map { LedgerEntity(id: $0.id, name: $0.name) }
    }
}
