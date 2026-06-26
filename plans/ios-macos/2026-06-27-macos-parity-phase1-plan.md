# macOS parity — Phase 1 (interaction) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** Make every row action mouse-reachable on macOS — add `.contextMenu` parity to the 8 swipe-only rows — and fix the macOS multi-select toolbar placement.

**Architecture:** Additive `.contextMenu` blocks mirroring each row's existing `.swipeActions` buttons (same closures/labels), plus a platform-conditional toolbar placement for the Activity bulk-action bar. No engine change.

Roadmap/spec: `plans/ios-macos/2026-06-27-macos-parity-roadmap-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- Pattern: insert each `.contextMenu { … }` **immediately after** the row's existing `.swipeActions(…)` modifier(s), so the loop variable (`rule`/`ledger`/`h`/`att`/`tag`/`rate`/`c`/`g`) is in scope. `.contextMenu` is cross-platform (adds long-press on iOS too — matches AccountsTab/ScheduledTab which already have both). These files are shared/active — keep diffs to the listed rows; **re-check `gh pr list` before pushing**.

---

### Task 1: Context-menu parity for the 8 swipe-only rows

**Files:** Modify the 8 files below (each: add one `.contextMenu` after the row's `.swipeActions`).

- [ ] **Step 1 — `PowerTools/RulesManagerView.swift`** (swipe: Delete `delete(rule)` + Backfill `backfill(rule)`). After the leading `.swipeActions { … }` block, add:

```swift
                .contextMenu {
                    Button { backfill(rule) } label: { Label("Backfill", systemImage: "arrow.triangle.2.circlepath") }
                    Button(role: .destructive) { delete(rule) } label: { Label("Delete", systemImage: "trash") }
                }
```

- [ ] **Step 2 — `WriteScreens/LedgerManagementView.swift`** (swipe: Delete `delete(ledger)`). After `.swipeActions`:

```swift
                .contextMenu {
                    Button(role: .destructive) { delete(ledger) } label: { Label("Delete", systemImage: "trash") }
                }
```

- [ ] **Step 3 — `WriteScreens/HoldingsView.swift`** (swipe: Delete `delete(h)`):

```swift
                            .contextMenu {
                                Button(role: .destructive) { delete(h) } label: { Label("Delete", systemImage: "trash") }
                            }
```

- [ ] **Step 4 — `WriteScreens/EditTransactionSheet.swift`** (swipe on an attachment row: Delete `removeAttachment(att)`):

```swift
                        .contextMenu {
                            Button(role: .destructive) { removeAttachment(att) } label: { Label("Delete", systemImage: "trash") }
                        }
```

- [ ] **Step 5 — `PowerTools/TagAdminView.swift`** (swipe: Delete `delete(tag)`):

```swift
                .contextMenu {
                    Button(role: .destructive) { delete(tag) } label: { Label("Delete", systemImage: "trash") }
                }
```

- [ ] **Step 6 — `PowerTools/ExchangeRatesView.swift`** (swipe: Delete `delete(rate)`):

```swift
                .contextMenu {
                    Button(role: .destructive) { delete(rate) } label: { Label("Delete", systemImage: "trash") }
                }
```

- [ ] **Step 7 — `PowerTools/CategoryAdminView.swift`** (swipe: Delete `deleting = c`):

```swift
        .contextMenu {
            Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
        }
```

- [ ] **Step 8 — `Common/GroupAdminView.swift`** (swipe: Delete `delete(g)`):

```swift
                            .contextMenu {
                                Button(role: .destructive) { delete(g) } label: { Label("Delete", systemImage: "trash") }
                            }
```

(Match the surrounding indentation in each file; the closure variable is the one used by that file's `.swipeActions`.)

- [ ] **Step 9: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerManagementView.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/HoldingsView.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/ExchangeRatesView.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift \
        ios/FinchApp/Sources/FinchApp/Common/GroupAdminView.swift
git commit -m "feat(ios): context-menu parity for swipe-only rows (macOS reachable)"
```

---

### Task 2: macOS multi-select toolbar placement

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1:** Replace the `if isSelecting { ToolbarItemGroup(placement: .bottomBar) { … } }` block (around lines 205–216) with a platform-conditional placement (iOS keeps the bottom bar with Spacers; macOS uses a `.principal` toolbar group, no Spacers):

```swift
            if isSelecting {
                #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Confirm \(selected.count)") { bulkConfirm() }.disabled(selected.isEmpty)
                    Spacer()
                    Button("Recategorize \(selected.count)") { showingBulkCat = true }.disabled(selected.isEmpty)
                    Spacer()
                    Button("Delete \(selected.count)", role: .destructive) { confirmingBulkDelete = true }.disabled(selected.isEmpty)
                }
                #else
                ToolbarItemGroup(placement: .principal) {
                    Button("Confirm \(selected.count)") { bulkConfirm() }.disabled(selected.isEmpty)
                    Button("Recategorize \(selected.count)") { showingBulkCat = true }.disabled(selected.isEmpty)
                    Button("Delete \(selected.count)", role: .destructive) { confirmingBulkDelete = true }.disabled(selected.isEmpty)
                }
                #endif
            }
```

- [ ] **Step 2: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "fix(ios): macOS multi-select bulk-action toolbar placement (.principal, not .bottomBar)"
```

---

### Task 3: Verify on macOS

**Files:** none.

- [ ] **Step 1: Build + run FinchMac:**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project ios/FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/mp-dd >/dev/null 2>&1
open /tmp/mp-dd/Build/Products/Debug/FinchMac.app
```

- [ ] **Step 2: Verify** (mouse): right-click rows in a Power Tool (Tags / Categories / Exchange rates / Rules) and on the Holdings / Ledger management / attachment lists → a **context menu with Delete (and Backfill for Rules)** appears and works. In Activity, enter multi-select → the **bulk-action buttons appear in the window toolbar** (not scattered). Screenshot evidence to `/tmp/mp-macos.png`. Clean up `/tmp/mp-dd` after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage (roadmap Phase 1): context-menu parity for all swipe-only rows (T1, the 8 verified files — AccountsTab/BudgetsTab/ActivityTab/ScheduledTab/AccountDetailView already mirror swipe↔context, excluded); multi-select toolbar fix (T2); macOS build + manual (T3). ✓
- Consistency: each context menu mirrors that file's swipe Button closures/labels exactly; destructive role on Delete. No engine change; additive. ✓
