import SwiftUI
import FinchCore

/// A split row's value when 2+ legs are ticked: their names joined for display, or
/// nil for a single leg (fewer than 2 names). Shared by the category picker AND the
/// account picker's split summary — axis-agnostic, so it lives here rather than
/// being copied. E.g. ["Groceries", "Household"] → "Groceries, Household".
func splitSummaryText(names: [String]) -> String? {
    names.count >= 2 ? names.joined(separator: ", ") : nil
}

/// The Category field as a tap-to-open row + bottom sheet that renders the
/// category HIERARCHY — an indented tree with expand/collapse, matching the
/// Settings › Categories page — instead of a flat list. Same staged-then-Confirm
/// contract as `SearchablePickerRow`, so it's a drop-in for the Category row.
/// Any node (parent or leaf) is selectable; a transaction can sit on a parent.
struct CategoryPickerRow: View {
    let title: String
    let glyph: FieldGlyph
    let categories: [CategoryRow]         // kind-filtered rows (sort_order order)
    @Binding var selection: String
    /// Non-nil ⇒ an empty selection ("") is a legal choice shown under this label
    /// (e.g. "None (top level)" for a category's Parent field), offered as the
    /// first row of the sheet. nil ⇒ empty renders as the "—" placeholder.
    var noneLabel: String? = nil
    /// Non-nil ⇒ the transaction is split: the row shows this summary instead of the
    /// picked category name.
    var splitSummary: String? = nil
    /// Non-nil ⇒ the subpage offers the split toggle. nil ⇒ plain single-select
    /// (refunds, the Parent field, scheduled templates).
    var splitting: Binding<SplitAllocation>? = nil
    /// Currency for the subpage's amount fields.
    var currency: String = ""
    /// True while the OTHER split (account) already has 2+ funded rows — the
    /// engine refuses an entry split both ways at once
    /// (`error.split.multiAccount`, Task 4b). Disables the toggle; ignored when
    /// `splitting` is nil.
    var splitLocked = false
    @State private var presented = false

    private var selectedName: String {
        categories.first { $0.id == selection }?.name ?? (selection.isEmpty ? noneLabel : nil) ?? "—"
    }

    var body: some View {
        HStack(spacing: 0) {
            // One tap target, one destination. Splitting used to hang off a separate
            // trailing branch icon here; it now lives inside the subpage as a toggle,
            // where there is room to label it and to say why it is unavailable.
            Button { presented = true } label: {
                FieldRow(glyph: glyph, title: LocalizedStringKey(title),
                         isEmpty: (splitSummary ?? (selection.isEmpty ? nil : selectedName)) == nil,
                         trailing: { FieldRowChevron() }) {
                    Text(splitSummary ?? selectedName).foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $presented) {
            CategoryPickerSheet(title: title, categories: categories, selection: $selection,
                                noneLabel: noneLabel, splitting: splitting, currency: currency,
                                splitLocked: splitLocked)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: a searchable tree, single-select. Tapping a row stages the
/// category (checkmark); the trailing chevron on parents expands/collapses.
/// Starts collapsed (top level only); typing force-expands to reveal matches.
/// Confirm applies the staged id to the binding; Cancel discards.
struct CategoryPickerSheet: View {
    let title: String
    let categories: [CategoryRow]
    @Binding var selection: String
    /// Non-nil ⇒ offer "" as a first, icon-less choice under this label
    /// (used by the Parent field's "None (top level)").
    let noneLabel: String?
    /// Non-nil ⇒ this sheet can also split: a toggle turns the tree multi-select and
    /// the ticked categories collect into an amounts section above it. nil ⇒ the
    /// plain single-select picker (Settings › Categories, ScheduledSheet).
    var splitting: Binding<SplitAllocation>? = nil
    /// Currency for the amount fields; only read in split mode.
    var currency: String = ""
    /// See `CategoryPickerRow.splitLocked`.
    var splitLocked = false
    /// Needed for `displayNative`, which is also what makes these amounts honour
    /// privacy mode rather than printing figures the rest of the app is hiding.
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var staged: String
    @State private var splitOn = false
    /// Per-row text while the user is typing. Rows that are not pinned have theirs
    /// dropped after every mutation so they redisplay the recomputed share.
    @State private var amountText: [String: String] = [:]

    init(title: String, categories: [CategoryRow], selection: Binding<String>, noneLabel: String? = nil,
         splitting: Binding<SplitAllocation>? = nil, currency: String = "", splitLocked: Bool = false) {
        self.title = title
        self.categories = categories
        self._selection = selection
        self.noneLabel = noneLabel
        self.splitting = splitting
        self.currency = currency
        self.splitLocked = splitLocked
        self._staged = State(initialValue: selection.wrappedValue)
    }

    private var byId: [String: CategoryRow] { Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }) }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(categories), expanded: expanded, search: query)
    }

    var body: some View {
        NavigationStack {
            List {
                if splitting != nil { splitSection }
                // The "none" choice isn't a searchable category — hide it while
                // a query filters the tree.
                //
                // Offered wherever the caller names it — the transaction sheets pass
                // "Uncategorized", so a plain transaction and a split leg can both be
                // left uncategorised, which the engine has always accepted (a nil
                // category leg). The Parent field names it differently ("None (top
                // level)"), which is why the label belongs to the caller.
                if query.isEmpty, let noneLabel { noneRow(noneLabel) }
                ForEach(visible) { item in row(item) }
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                // Reopening an already-split transaction lands straight in split mode.
                splitOn = (splitting?.wrappedValue.rows.count ?? 0) >= 2
            }
            .onChange(of: splitOn) { _, on in
                guard let splitting else { return }
                if on {
                    // Seed from the single selection, so the category already picked
                    // becomes row one and holds the whole total.
                    if !staged.isEmpty { splitting.wrappedValue.tick(staged) }
                } else {
                    // Collapse to the largest leg — the same category the row was
                    // already displaying, per the projection's dominant-leg rule.
                    if let dominant = splitting.wrappedValue.dominantId { staged = dominant }
                    splitting.wrappedValue = SplitAllocation(total: splitting.wrappedValue.total)
                }
                amountText.removeAll()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        // Splitting still names a single category — the dominant leg —
                        // so the transaction's own category field stays meaningful and
                        // agrees with what the projection will derive from the legs.
                        selection = splitOn ? (splitting?.wrappedValue.dominantId ?? staged) : staged
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Confirm")
                        .confirmCheckmarkStyle()
                        .disabled(splitOn && splitting?.wrappedValue.problem != nil)
                }
            }
        }
    }

    /// The toggle, and — once it is on — the ticked categories with their amounts.
    @ViewBuilder private var splitSection: some View {
        Section {
            Toggle("Split across categories", isOn: $splitOn)
                .accessibilityIdentifier("category.splitToggle")
                .disabled(splitLocked)
            if splitLocked {
                // The engine refuses an entry split both ways at once
                // (error.split.multiAccount) — say why the toggle won't move
                // rather than let the user find out after a half-applied save.
                Text("Turn off the account split first.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if splitOn, let splitting {
            Section {
                ForEach(Array(splitting.wrappedValue.rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(name(of: row.id))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // Symbol + field kept tight so they read as one right-aligned
                        // unit, matching the Allocated line below.
                        HStack(spacing: 2) {
                            Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                            TextField("0.00", text: amountBinding(row.id, splitting))
                                .numericInput(amountBinding(row.id, splitting))
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .fixedSize()
                                .accessibilityIdentifier("category.splitAmount.\(index)")
                        }
                    }
                }
                LabeledContent("Allocated") {
                    Text(verbatim: "\(store.displayNative(splitting.wrappedValue.allocated, currency: currency)) / \(store.displayNative(splitting.wrappedValue.total, currency: currency))")
                }
                .accessibilityIdentifier("category.allocated")
                .foregroundStyle(splitting.wrappedValue.problem == nil ? .primary : .secondary)
                if let problem = splitting.wrappedValue.problem {
                    // Say WHY Confirm is blocked. The old split affordance was a 40%
                    // opacity icon that explained neither its state nor its purpose.
                    Text(Self.message(for: problem)).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private static func message(for problem: SplitAllocation.Problem) -> LocalizedStringKey {
        switch problem {
        case .needsAmount: return "Enter an amount to split."
        case .needsTwo: return "Give at least two categories an amount."
        case .sumMismatch: return "Splits must add up to the transaction total."
        }
    }

    private func name(of id: String) -> String {
        id.isEmpty ? String(localized: "Uncategorized") : (categories.first { $0.id == id }?.name ?? "—")
    }

    /// Typing pins the row; emptying it unpins so it floats again. After every write
    /// the unpinned rows' buffers are dropped so they show the recomputed share —
    /// except the row being edited, which would otherwise fight the user's keystrokes.
    private func amountBinding(_ id: String, _ alloc: Binding<SplitAllocation>) -> Binding<String> {
        Binding(
            get: {
                if let typed = amountText[id] { return typed }
                let amount = alloc.wrappedValue.rows.first { $0.id == id }?.amount ?? 0
                return amount == 0 ? "" : String(format: "%g", amount)
            },
            set: { newValue in
                amountText[id] = newValue
                if let parsed = DecimalInput.parse(newValue), parsed > 0 {
                    alloc.wrappedValue.setAmount(id, parsed)
                } else {
                    alloc.wrappedValue.setAmount(id, nil)
                }
                for r in alloc.wrappedValue.rows where !r.pinned && r.id != id { amountText[r.id] = nil }
            })
    }

    /// The empty-selection row: same geometry as `CategoryTreeRow` (26pt glyph
    /// slot, reserved chevron column) so the list reads as one aligned tree.
    /// Ticks like any other row in split mode — an uncategorised leg is just a leg.
    @ViewBuilder private func noneRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            Button { tap("") } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 20)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                    Text(label).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isChosen("") { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Color.clear.frame(width: 22, height: 30)
        }
    }

    /// Whether a category reads as chosen — ticked in split mode, staged otherwise.
    private func isChosen(_ id: String) -> Bool {
        splitOn ? (splitting?.wrappedValue.isTicked(id) ?? false) : id == staged
    }

    @ViewBuilder private func row(_ item: FlatCategory) -> some View {
        CategoryTreeRow(
            item: item, byId: byId,
            isSelected: isChosen(item.row.id),
            expanded: expanded.contains(item.row.id),
            searchActive: !query.isEmpty,
            onTap: { tap(item.row.id) },
            onToggleExpand: {
                if expanded.contains(item.row.id) { expanded.remove(item.row.id) } else { expanded.insert(item.row.id) }
            }
        )
    }

    /// In split mode a tap toggles membership; otherwise it stages the single choice.
    /// A tick means THIS category and never its children — the expand chevron does the
    /// expanding, and a split is exactly one categoryId, so cascading would silently
    /// manufacture a split per child.
    private func tap(_ id: String) {
        guard splitOn, let splitting else { staged = id; return }
        if splitting.wrappedValue.isTicked(id) {
            splitting.wrappedValue.untick(id)
            amountText[id] = nil
        } else {
            splitting.wrappedValue.tick(id)
        }
        for r in splitting.wrappedValue.rows where !r.pinned { amountText[r.id] = nil }
    }
}

/// One category-tree row shared by the single- and multi-select picker sheets:
/// swatch + icon + indented name + a trailing selection checkmark + an
/// expand/collapse chevron for parents. Selection + expand state are caller-driven.
struct CategoryTreeRow: View {
    let item: FlatCategory
    let byId: [String: CategoryRow]
    let isSelected: Bool
    let expanded: Bool
    let searchActive: Bool
    let onTap: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        let c = item.row
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 26, height: 26)
                        Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                            .font(.system(size: 12)).foregroundStyle(.white)
                    }
                    Text(c.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: (expanded || searchActive) ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 22, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(searchActive)   // search force-expands; chevron is inert
            } else {
                // Reserve the chevron slot so checkmarks/edges line up across rows.
                Color.clear.frame(width: 22, height: 30)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 14)
        .contentShape(Rectangle())
    }
}
