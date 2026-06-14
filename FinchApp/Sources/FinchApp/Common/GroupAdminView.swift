import SwiftUI
import FinchCore

/// Reusable create / rename / delete UI for a named-group list (account groups,
/// budget groups). The owner supplies the groups + the three chokepoint actions.
struct GroupAdminView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let groups: [GroupRow]
    let onCreate: (String) throws -> Void
    let onRename: (String, String) throws -> Void   // (id, newName)
    let onDelete: (String) throws -> Void

    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Add group") {
                HStack {
                    TextField("Group name", text: $newName)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Groups") {
                if groups.isEmpty {
                    Text("No groups yet").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(groups) { g in
                        GroupRowEditor(group: g, onRename: onRename, onError: { errorMessage = $0 })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(g) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do { try onCreate(name); newName = "" }
        catch { errorMessage = i18nMessage(error) }
    }

    private func delete(_ g: GroupRow) {
        do { try onDelete(g.id) } catch { errorMessage = i18nMessage(error) }
    }
}

/// One group row: rename in place (commits on submit).
private struct GroupRowEditor: View {
    let group: GroupRow
    let onRename: (String, String) throws -> Void
    let onError: (String) -> Void
    @State private var name: String

    init(group: GroupRow, onRename: @escaping (String, String) throws -> Void, onError: @escaping (String) -> Void) {
        self.group = group; self.onRename = onRename; self.onError = onError
        _name = State(initialValue: group.name)
    }

    var body: some View { TextField("Name", text: $name).onSubmit(rename) }

    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != group.name else { name = group.name; return }
        do { try onRename(group.id, trimmed) }
        catch { onError(i18nMessage(error)); name = group.name }
    }
}
