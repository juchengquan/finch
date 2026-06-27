# macOS keyboard ↵-open — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** On macOS, arrow-select a row in the Scheduled (list) / Activity lists and press ↵ to open its edit sheet.

**Architecture:** Each list gains `List(selection: $kbSel)` + per-row `.tag(id)` + a `#if os(macOS) .onKeyPress(.return)` that opens `editing`. No engine change.

Spec: `plans/ios-macos/2026-06-27-macos-kbopen-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `ScheduledTab`/`ActivityTab` are actively edited — keep edits to the listed spots; **re-check `gh pr list` + rebase before pushing**.

---

### Task 1: ScheduledTab — keyboard ↵-open (list mode)

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift`

- [ ] **Step 1:** Add state near the other `@State` (around lines 11–17):

```swift
    @State private var kbSel: String?            // macOS keyboard-open selection
```

- [ ] **Step 2:** Change the list-mode `List {` (line ~62) to:

```swift
                            List(selection: $kbSel) {
```

- [ ] **Step 3:** Tag the template row — the `Button { editing = t } label: { ScheduledRow… }` with its swipe/context modifiers (lines ~64–77). Add `.tag(t.id)` as its **final** modifier (right after the `.contextMenu { … }` block, before the `ForEach` closure's closing `}`):

```swift
                                        .tag(t.id)
```

- [ ] **Step 4:** Attach the Return handler to the List — **after** the List's `.overlay { … }` block (around line ~110), before the `} else {` of the Calendar/List toggle:

```swift
                            #if os(macOS)
                            .onKeyPress(.return) {
                                if let id = kbSel, let t = filteredScheduled.first(where: { $0.id == id }) { editing = t; return .handled }
                                return .ignored
                            }
                            #endif
```

---

### Task 2: ActivityTab — keyboard ↵-open (feed)

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1:** Add state near `isSelecting`/`selected` (lines ~69–70):

```swift
    @State private var kbSel: String?            // macOS keyboard-open selection
```

- [ ] **Step 2:** Change `List {` (line 89) to:

```swift
                List(selection: $kbSel) {
```

- [ ] **Step 3:** In `row(_ txn:)` (starts line 306), add `.tag(txn.id)` as the **final** modifier of the returned view — after the `.contextMenu { … }` block that ends the row's chain:

```swift
        .tag(txn.id)
```

- [ ] **Step 4:** Attach the Return handler to the List — after the List's closing `}` (line 131), before the `}` that closes the `else` branch (line 132):

```swift
                #if os(macOS)
                .onKeyPress(.return) {
                    if !isSelecting, let id = kbSel, let txn = sections.flatMap({ $0.txns }).first(where: { $0.id == id }) { editing = txn; return .handled }
                    return .ignored
                }
                #endif
```

- [ ] **Step 5: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
```
Expected: both `** BUILD SUCCEEDED **`. (If `.onKeyPress(.return)` errors on the List, attach it to the enclosing container instead — it just needs to be on a view in the focused list's ancestry; keep it `#if os(macOS)`.)

- [ ] **Step 6: Commit** (both files)

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): macOS keyboard ↵-open on Scheduled & Activity lists"
```

---

### Task 3: Verify

**Files:** none.

- [ ] **Step 1: Builds** — confirm Task 2 Step 5 shows both `** BUILD SUCCEEDED **`.

- [ ] **Step 2: macOS run (best-effort):**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project ios/FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/kb-dd >/dev/null 2>&1
open /tmp/kb-dd/Build/Products/Debug/finch.app
```
Confirm FinchMac launches; if reachable, focus the Scheduled list (List mode) or Activity feed,
arrow to a row, press ↵ → its edit sheet opens. *Note:* the live keypress isn't reliably
scriptable; build + code review is the primary gate. Clean up `/tmp/kb-dd` after.

- [ ] **Step 3 (no commit):** report.

---

## Self-review notes
- Spec coverage: ScheduledTab state/selection/tag/onKeyPress (T1); ActivityTab same (T2); build + macOS run (T3). ✓
- Consistency: `kbSel: String?` per file; `.tag(id)` matches the row id type; `onKeyPress` resolves the id against `filteredScheduled` / `sections.flatMap{$0.txns}` → sets `editing`. `#if os(macOS)` on every onKeyPress. ✓
- No engine change; iOS inert (selection binding outside EditMode; onKeyPress compiled out). ✓
