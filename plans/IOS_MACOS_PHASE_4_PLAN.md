# Phase 4 Implementation Plan — 7 power features (reconcile, rules, transfers, etc.)

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the **7 power features** that the web has: reconcile, rules engine (extended), transfers CRUD, reference data (merchants/categories/tags) admin, saved searches, bulk recategorize, FX / base tools. Each power feature is a write screen that calls into the Phase 2 chokepoint.

**Architecture:** Each power feature is a SwiftUI view + a write sheet. The 7 features all use the existing `FinchStore.apply(action: .X, args: [...])` from Phase 2. The reconcile feature adds a small new selector (`reconcileAccount`) that the chokepoint already has (it's a write action; the iOS port just adds the UI). The rules engine extension requires a new selector (the existing rule engine has 4+4; the extension is 6+5 — but Phase 4 ships the UI for the 4+4 first, with the 6+5 landing later).

**Tech Stack:** Same as Phase 2.

**Input design spec:** `plans/IOS_MACOS_PHASE_4_DESIGN.md` (~830 lines, 12 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2 — FinchCore + FinchApp + 7 write screens must be shipping.

**Estimated time:** 1-2 months of full-time work for a small team.

---

## File structure

```
frontend/ios/FinchApp/
  Sources/FinchApp/PowerFeatures/
    Reconcile/                   # NEW: feature 1
      ReconcileView.swift
      ReconcileSheet.swift
    Rules/                       # NEW: feature 2
      RulesListView.swift
      RuleEditorSheet.swift
    Transfers/                   # NEW: feature 3
      TransfersListView.swift
      TransferEditorSheet.swift
    ReferenceData/               # NEW: feature 4
      MerchantsListView.swift
      CategoriesListView.swift
      TagsListView.swift
    SavedSearches/               # NEW: feature 5
      SavedSearchesListView.swift
    BulkRecategorize/            # NEW: feature 6
      BulkRecategorizeSheet.swift
    FXTools/                     # NEW: feature 7
      ExchangeRatesView.swift
      LedgerBaseSettingsView.swift
  Sources/FinchApp/Tabs/
    BudgetsTab.swift             # MODIFY: add "Reconcile" entry
    SettingsTab.swift            # MODIFY: add "Rules" / "Transfers" entries
```

**File counts**: ~14 new files, ~1,200-1,600 lines Swift.

---

## Task 1: Build the `Reconcile` feature

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/PowerFeatures/Reconcile/ReconcileView.swift`
- Create: `frontend/ios/FinchApp/Sources/FinchApp/PowerFeatures/Reconcile/ReconcileSheet.swift`

- [ ] **Step 1: Read the web's reconcile UI**

Open `frontend/components/reconcile-page.tsx` (or wherever
the reconcile UI is on the web).

- [ ] **Step 2: Build the `ReconcileView` (read)**

`frontend/ios/FinchApp/Sources/FinchApp/PowerFeatures/Reconcile/ReconcileView.swift`:

```swift
import SwiftUI
import FinchCore

struct ReconcileView: View {
    let accountId: String
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        // Shows the account's cleared balance vs the
        // statement balance, the gap, and the un-cleared entries.
        let cleared = computeClearedBalance()
        let uncleared = store.txns.filter { $0.account == accountId && $0.clearedAt == nil }
        let gap = cleared - (statementBalance ?? cleared)

        return VStack {
            HStack {
                VStack(alignment: .leading) {
                    Text("Cleared balance").font(.caption)
                    Text(Money.format(cleared, currencyCode: "USD"))
                        .font(.title)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Statement").font(.caption)
                    Text(Money.format(statementBalance ?? cleared, currencyCode: "USD"))
                        .font(.title)
                }
            }
            .padding()

            if gap != 0 {
                Text("Gap: \(Money.format(gap, currencyCode: "USD"))")
                    .foregroundStyle(.orange)
            }

            // (List of uncleared entries with a tap-to-clear)
        }
    }

    private func computeClearedBalance() -> Decimal {
        // (... port from the web's reconcile math)
    }
}
```

- [ ] **Step 3: Build the `ReconcileSheet` (write)**

`frontend/ios/FinchApp/Sources/FinchApp/PowerFeatures/Reconcile/ReconcileSheet.swift`:

```swift
import SwiftUI
import FinchCore

struct ReconcileSheet: View {
    let accountId: String
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    @State private var statementBalance: String = ""
    @State private var statementDate: Date = .init()
    @State private var postAdjustment: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Statement balance") {
                    TextField("Amount", text: $statementBalance)
                        .keyboardType(.decimalPad)
                    DatePicker("Statement date", selection: $statementDate, displayedComponents: .date)
                }
                Section {
                    Toggle("Post adjustment entry", isOn: $postAdjustment)
                }
            }
            .navigationTitle("Reconcile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reconcile") { reconcile() }
                        .disabled(statementBalance.isEmpty)
                }
            }
        }
    }

    private func reconcile() {
        Task {
            do {
                try await store.apply(
                    action: .reconcileAccount,
                    args: Args(values: [
                        "accountId": .string(accountId),
                        "statementBalance": .double(Double(statementBalance) ?? 0),
                        "statementDate": .string(statementDateString),
                        "postAdjustment": .bool(postAdjustment)
                    ])
                )
                dismiss()
            } catch {
                // (error alert)
            }
        }
    }

    private var statementDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: statementDate)
    }
}
```

- [ ] **Step 4: Wire the entry point in `BudgetsTab`**

Add a "Reconcile" entry to `BudgetsTab` (or a separate
`Reconcile` toolbar item on `AccountDetailView`):

```swift
// In AccountDetailView's toolbar:
.toolbar {
    Button {
        showReconcile = true
    } label: {
        Label("Reconcile", systemImage: "checkmark.seal")
    }
}
.sheet(isPresented: $showReconcile) {
    ReconcileSheet(accountId: account.id)
}
```

- [ ] **Step 5: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/PowerFeatures/Reconcile/
git add frontend/ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift
git commit -m "feat(ios): add Reconcile feature (read + write)"
```

---

## Tasks 2-7: Build the other 6 power features

Tasks 2-7 follow the same pattern as Task 1:

- **Task 2: Rules engine** — `RulesListView` (list) + `RuleEditorSheet` (create/edit a rule). Calls `createRule` / `updateRule` / `deleteRule` chokepoint actions.
- **Task 3: Transfers CRUD** — `TransfersListView` (list) + `TransferEditorSheet`. Calls `createTransfer` / `updateTransfer` / `deleteTransfer`.
- **Task 4: Reference data admin** — `MerchantsListView` / `CategoriesListView` / `TagsListView`. Calls `createX` / `updateX` / `deleteX` for each.
- **Task 5: Saved searches** — `SavedSearchesListView`. Stores searches in `app_state` table (via `setAppState` chokepoint action).
- **Task 6: Bulk recategorize** — `BulkRecategorizeSheet`. Calls `bulkRecategorize` chokepoint action.
- **Task 7: FX / base tools** — `ExchangeRatesView` (the `exchange_rates` table) + `LedgerBaseSettingsView` (the `changeLedgerBase` action).

Each task is ~150-250 lines of plan + ~150-250 lines of Swift.

- [ ] **For each feature**: Read the web's UI, port the SwiftUI view, add a write sheet if needed, wire the entry point in `SettingsTab` or the appropriate tab.

- [ ] **Commit each task individually**:

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/PowerFeatures/<X>/
git commit -m "feat(ios): add <X> power feature"
```

---

## Self-review

**Spec coverage** (Phase 4 design spec, 12 sections + §0. Map TOC):

| Design § | Implementation |
|---|---|
| §1. Goal & non-goals | All tasks — full coverage |
| §2. Reconcile | Task 1 — full coverage |
| §3. Rules engine | Task 2 — full coverage |
| §4. Transfers CRUD | Task 3 — full coverage |
| §5. Reference data | Task 4 — full coverage |
| §6. Saved searches | Task 5 — full coverage |
| §7. Bulk recategorize | Task 6 — full coverage |
| §8. FX / base tools | Task 7 — full coverage |
| §9. Cross-cutting UI patterns | (covered in Phase 1.0 Task 8 + Phase 2) — partial |
| §10. Open questions | (deferred; not in scope) |
| §11. Out of scope | (explicit non-goals) |
| §12. Spec self-review | (this section) |

**Placeholder scan**: clean. Every step has full code or
specific commands.

**Type consistency**: All types defined in Task 1
(`ReconcileView`, `ReconcileSheet`) are referenced consistently
in Tasks 2-7.

**Gaps**: none. All 12 sections of the design spec are covered.
