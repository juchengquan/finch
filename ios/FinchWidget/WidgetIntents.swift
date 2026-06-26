import AppIntents
import FinchCore

struct WidgetAccountEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Account" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = WidgetAccountQuery()
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        items().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetAccountEntity] { items() }
    private func items() -> [WidgetAccountEntity] {
        (AppGroup.readWidgetSnapshot()?.accounts ?? []).map { WidgetAccountEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectAccountIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Account" }
    static var description: IntentDescription { IntentDescription("Choose which account this widget shows.") }
    @Parameter(title: "Account") var account: WidgetAccountEntity?
    init() {}
}
