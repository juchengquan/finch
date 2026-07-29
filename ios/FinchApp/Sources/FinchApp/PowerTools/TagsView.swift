import SwiftUI
import FinchCore

/// A chosen (initiating A, target B) pair for a merge; the alert picks which survives.
private struct TagMergePair: Identifiable {
    let a: TagRow   // the row the merge was started from
    let b: TagRow   // the picked other tag
    var id: String { a.id + "|" + b.id }
}

/// Tags admin — a flat, color-only list (Settings top-level). Mirrors the
/// Categories page: search, color-swatch rows with a transaction-count pill,
/// tap → the tag's transactions, swipe Edit/Delete, + to add. All through the
/// existing chokepoints (create / update / deleteTag). Tags have no hierarchy,
/// kind, icon, or order — so no tree, kind picker, or reorder here, but merge
/// (single + multi-select) mirrors Categories.
struct TagsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var selectedTagId: String?          // tapped row → transactions
    @State private var creating = false
    @State private var editing: TagRow?
    @State private var deleting: TagRow?
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var mergingFrom: TagRow?              // → target-picker sheet
    @State private var pendingMerge: TagMergePair?       // staged in the sheet, promoted on its dismiss
    @State private var mergeChoice: TagMergePair?        // → keep-which-name alert
    @State private var isSelecting = false               // ⋯ → Merge multi-select mode
    @State private var selected: Set<String> = []        // ids ticked in select mode
    @State private var mergeManySurvivorChoice: [TagRow]? // → keep-which-name dialog
    @State private var importing = false                 // ⋯ → Import-from-ledger sheet
    @State private var copyingTag: TagRow?                // row → Copy-to-ledger sheet

    private var rows: [TagRow] {
        guard !search.isEmpty else { return store.tags }
        return store.tags.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)
        return List {
            if store.tags.isEmpty {
                emptyState
            } else {
                ForEach(rows) { tag in row(tag, counts) }
            }
        }
        .modifier(SearchableModifier(text: $search))
        .navigationTitle("Tags")
        .errorAlert($errorMessage)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge (\(selected.count))") {
                        mergeManySurvivorChoice = selected.compactMap { id in store.tags.first { $0.id == id } }
                            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    }
                    .disabled(selected.count < 2)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { isSelecting = false; selected = [] } label: { Image(systemName: "xmark").toolbarTapTarget() }.toolbarCircleClip()
                        .accessibilityLabel("Cancel")
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus").toolbarTapTarget() }.toolbarCircleClip()
                        .accessibilityLabel("New tag")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { isSelecting = true; selected = [] } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                        Button { importing = true } label: { Label("Import from another ledger…", systemImage: "square.and.arrow.down.on.square") }
                    } label: { Image(systemName: "ellipsis").toolbarTapTarget() }.toolbarCircleClip()
                    .accessibilityLabel("More")
                }
            }
        }
        .navigationDestination(item: $selectedTagId) { id in
            if let t = store.tags.first(where: { $0.id == id }) { TagDetailView(tag: t) }
        }
        .sheet(isPresented: $creating) { TagEditSheet(tag: nil) }
        .sheet(item: $editing) { TagEditSheet(tag: $0) }
        .sheet(isPresented: $importing) {
            LedgerPickerSheet(title: "Import tags from…") { from in
                do { copyDone(try store.applyReturningCount(.copyTags, Args(["fromLedgerId": .string(from), "toLedgerId": .string(store.activeLedgerId)]))) }
                catch { errorMessage = i18nMessage(error) }
            }
        }
        .sheet(item: $copyingTag) { t in
            LedgerPickerSheet(title: "Copy \(t.name) to…") { to in
                do { copyDone(try store.applyReturningCount(.copyTags, Args(["fromLedgerId": .string(store.activeLedgerId), "toLedgerId": .string(to), "ids": .array([.string(t.id)])]))) }
                catch { errorMessage = i18nMessage(error) }
            }
        }
        // Centered window-level alert (matches Categories/Activity deletes).
        .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting) { t in
            Button("Delete", role: .destructive) { delete(t) }
            Button("Cancel", role: .cancel) {}
        } message: { t in
            let n = counts[t.id] ?? 0
            if n > 0 { Text("\(t.name) is removed from \(n) transactions.") }
        }
        // Single merge: pick a target, then the keep-which-name alert (staged via
        // onDismiss so chaining dismiss+present doesn't drop the alert).
        .sheet(item: $mergingFrom, onDismiss: {
            if let p = pendingMerge { mergeChoice = p; pendingMerge = nil }
        }) { a in
            NavigationStack {
                List {
                    let others = store.tags.filter { $0.id != a.id }
                    if others.isEmpty {
                        ContentUnavailableView("No other tags", systemImage: "arrow.triangle.merge",
                                               description: Text("There's nothing to merge \(a.name) with yet."))
                    } else {
                        ForEach(others) { b in
                            Button { pendingMerge = TagMergePair(a: a, b: b); mergingFrom = nil } label: {
                                HStack(spacing: 10) {
                                    TagSwatch(hex: b.color)
                                    Text(b.name).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Merge \(a.name) with…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { mergingFrom = nil } label: { Image(systemName: "xmark").toolbarTapTarget() }.accessibilityLabel("Cancel").toolbarCircleClip()
                    }
                }
            }
        }
        .alert("Keep which name after merge?", isPresented: Binding(
            get: { mergeChoice != nil }, set: { if !$0 { mergeChoice = nil } }),
            presenting: mergeChoice) { pair in
            Button("Keep \"\(pair.a.name)\"") { merge(source: pair.b, target: pair.a) }
            Button("Keep \"\(pair.b.name)\"") { merge(source: pair.a, target: pair.b) }
            Button("Cancel", role: .cancel) {}
        } message: { pair in
            if let msg = mergeImpactMessage(txCount: mergeTxCount(pair.a, pair.b)) { Text(msg) }
        }
        .alert("Keep which name?", isPresented: Binding(
            get: { mergeManySurvivorChoice != nil }, set: { if !$0 { mergeManySurvivorChoice = nil } }),
            presenting: mergeManySurvivorChoice) { picks in
            ForEach(picks) { survivor in
                Button("Keep \"\(survivor.name)\"") { mergeMany(keeping: survivor, from: picks) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { picks in
            if let msg = mergeImpactMessage(txCount: mergeManyTxCount(picks)) { Text(msg) }
        }
    }

    /// A tag row: color swatch + name + count pill. Tap opens the tag's
    /// transactions (no chevron — on the Settings lists a chevron always means
    /// "expandable parent", and only Categories has those); Edit/Delete are on
    /// the swipe (Edit is the full-swipe default) and context menu.
    @ViewBuilder private func row(_ tag: TagRow, _ counts: [String: Int]) -> some View {
        HStack(spacing: 8) {
            if isSelecting {
                Image(systemName: selected.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected.contains(tag.id) ? Color.accentColor : .secondary)
            }
            Button {
                if isSelecting {
                    if selected.contains(tag.id) { selected.remove(tag.id) } else { selected.insert(tag.id) }
                } else {
                    selectedTagId = tag.id
                }
            } label: {
                HStack(spacing: 10) {
                    TagSwatch(hex: tag.color)
                    Text(tag.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CountPill(count: counts[tag.id] ?? 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityAddTraits(isSelecting && selected.contains(tag.id) ? [.isSelected] : [])
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))   // match Categories density
        .swipeActions(edge: .trailing) {
            // Edit declared first ⇒ outer edge / full-swipe default (never delete).
            Button { editing = tag } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
            Button { mergingFrom = tag } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }.tint(.orange)
            // Not role: .destructive — the alert confirms; matches Categories.
            Button { deleting = tag } label: { Label("Delete", systemImage: "trash") }.tint(.red)
        }
        .contextMenu {
            Button { editing = tag } label: { Label("Edit", systemImage: "pencil") }
            Button { mergingFrom = tag } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
            Button { copyingTag = tag } label: { Label("Copy to another ledger…", systemImage: "square.and.arrow.up.on.square") }
            Button(role: .destructive) { deleting = tag } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag").font(.largeTitle).foregroundStyle(.secondary)
            Text("No tags yet").font(.headline)
            Text("Tap + to add one.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// Confirm a copy: these actions dedup against the target, so a bare "done"
    /// would look identical whether 12 rows landed or none did. Also the ONLY
    /// feedback for the copy-OUT direction, where the target isn't the ledger on
    /// screen and nothing visibly changes.
    private func copyDone(_ added: Int) {
        Haptics.success()
        ToastCenter.shared.show(added > 0 ? "\(added) added" : "Nothing new to copy")
    }

    private func delete(_ t: TagRow) {
        errorMessage = nil
        do { try store.apply(.deleteTag, Args(["id": .string(t.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    /// Choice-independent union of transactions referencing either tag.
    private func mergeTxCount(_ a: TagRow, _ b: TagRow) -> Int {
        let ledger = store.activeLedgerId
        let ids = Set(Selectors.tagTransactions(store.txns, a.id, ledger).map(\.id))
            .union(Selectors.tagTransactions(store.txns, b.id, ledger).map(\.id))
        return ids.count
    }

    private func merge(source: TagRow, target: TagRow) {
        errorMessage = nil; mergeChoice = nil
        do { try store.apply(.mergeTag, Args(["sourceId": .string(source.id), "targetId": .string(target.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    private func mergeManyTxCount(_ tagRows: [TagRow]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for t in tagRows { ids.formUnion(Selectors.tagTransactions(store.txns, t.id, ledger).map(\.id)) }
        return ids.count
    }

    /// Merge every selected tag except the survivor into it, atomically.
    private func mergeMany(keeping survivor: TagRow, from all: [TagRow]) {
        errorMessage = nil; mergeManySurvivorChoice = nil
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        do {
            try store.apply(.mergeTags, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false; selected = []
        } catch { errorMessage = i18nMessage(error) }
    }
}

struct TagEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let tag: TagRow?
    /// Called with the new tag's id after a successful create (nil on edit).
    let onCreated: ((String) -> Void)?
    @State private var name: String
    @State private var color: String     // "" = none
    @State private var errorMessage: String?

    /// `tag` = edit an existing tag; nil = create. `prefillName` seeds the name
    /// field on create (e.g. the text typed in the transaction tag picker), and
    /// `onCreated` reports the new id so the caller can select it.
    init(tag: TagRow?, prefillName: String? = nil, onCreated: ((String) -> Void)? = nil) {
        self.tag = tag
        self.onCreated = onCreated
        _name = State(initialValue: tag?.name ?? prefillName ?? "")
        _color = State(initialValue: tag?.color ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(TagPalette.hexes, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == hex ? 2.5 : 0))
                                .contentShape(Circle())
                                .onTapGesture { color = (color == hex ? "" : hex) }
                                .accessibilityLabel("Color \(hex)")
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").toolbarTapTarget() }.toolbarCircleClip()
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let t = tag {
                let patch: [String: JSONValue] = [
                    "name": .string(trimmed),
                    "color": color.isEmpty ? .null : .string(color),
                ]
                try store.apply(.updateTag, Args(["id": .string(t.id), "patch": .object(patch)]))
            } else {
                // Client-generated id so callers (e.g. the tag picker) can select
                // the tag the moment it's created — createTag doesn't return one.
                let id = "tag-\(UUID().uuidString.prefix(8).lowercased())"
                var args: [String: JSONValue] = [
                    "id": .string(id),
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                ]
                if !color.isEmpty { args["color"] = .string(color) }
                try store.apply(.createTag, Args(args))
                onCreated?(id)
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
