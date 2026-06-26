# Flat dated feed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven). Checkbox steps.

**Goal:** Drop the per-day section headers in the transaction feed → one flat dated list.

**Architecture:** Replace the day-grouped render with a flat `ForEach` over the (already date-ordered) txns; per-row date stays. UI-only.

Spec: `plans/ios-macos/2026-06-26-flat-feed-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS). No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `ActivityTab.swift` is an actively-edited file — keep the diff to the one render block; **re-check `gh pr list --base feat/frontend --state open` before pushing**.

---

### Task 1: Flatten the feed render

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1:** Replace the day-grouped render block:

```swift
                    ForEach(sections) { section in
                        Section(section.id) {
                            ForEach(section.txns) { txn in
                                row(txn)
                            }
                        }
                    }
```
with:

```swift
                    ForEach(sections.flatMap { $0.txns }) { txn in
                        row(txn)
                    }
```
(Leave everything else — `recompute()`, `DaySection`, the result-count caption, pending-confirm section, sort/filter, "Load more", `TxRow` — unchanged.)

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
git commit -m "feat(ios): flat dated activity feed (drop redundant day-section headers)"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Build to a known path + install** (avoid stale builds):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ff-dd >/dev/null 2>&1
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl install "$SIM" /tmp/ff-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab ledger
```
(Seed a few transactions across ≥2 days if the ledger is empty — entry + 2 balanced postings each, `exchange_rate=1`.)

- [ ] **Step 2: Verify**
  - The feed is a **single continuous list** — **no "2026-06-25" day headers** — each row still shows its own date (bottom-left). Sort menu / filter / result-count / "Load more" still work.
  - Screenshot evidence to `/tmp/flat-feed.png`. Clean up `/tmp/ff-dd` + any seed after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: flatten render (T1 S1), build (T1 S2), manual (T2). ✓
- Type consistency: `sections.flatMap { $0.txns }` → `[Tx]` (Identifiable); `row(_:)` unchanged. ✓
- No engine change; per-row date + recompute untouched. ✓
