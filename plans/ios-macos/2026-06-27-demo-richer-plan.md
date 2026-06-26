# Richer demo data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** Seed tags, pending, a refund, a transfer, an installment plan, and an FX rate into the simulator demo.

**Architecture:** All in `SimulatorDemoSeed.swift` via existing actions (`createTag`, `addTransaction` kind/status/tagIds, `createTransfer`, `createScheduled` installmentTotal, `setExchangeRate`). No engine change.

Spec: `plans/ios-macos/2026-06-27-demo-richer-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Build: FinchApp (iOS) must `** BUILD SUCCEEDED **`. (No macOS-specific paths touched.) No `Co-Authored-By`. No engine change — demo-seed data only. PR → `feat/frontend`.
- All edits are inside `seed(_:)` in `ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift`.

---

### Task 1: Tags + enriched transactions (tags, pending, refund)

**Files:** Modify `ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift`

- [ ] **Step 1: Create the 4 tags.** Immediately **before** the `// ~3 months of transactions.` comment (i.e. before `let txns:`), insert:

```swift
        // Tags (parity palette) applied to several transactions below.
        let tags: [(id: String, name: String, color: String)] = [
            ("tag-reimbursable", "reimbursable", "#00a5da"),
            ("tag-subscription", "subscription", "#7d7df9"),
            ("tag-business",     "business",     "#00af67"),
            ("tag-vacation",     "vacation",     "#ba8600"),
        ]
        for t in tags {
            try apply("createTag", ["id": .string(t.id), "ledgerId": .string("personal"),
                                    "name": .string(t.name), "color": .string(t.color)])
        }

```

- [ ] **Step 2: Replace the `txns` tuple + loop** (the `let txns: [(d: Int, …)] = [ … ]` array AND the `for t in txns { … }` loop) with this exact block (adds `kind`/`status`/`tags` fields, a refund row at d11, 2 pending, ~10 tagged):

```swift
        // ~3 months of transactions. Expenses negative, income positive.
        let txns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String,
                    kind: String?, status: String?, tags: [String]?)] = [
            (2,  "credit",   -42.18, "Whole Foods",        "cat-groceries",     nil,      "pending", ["tag-reimbursable"]),
            (3,  "credit",   -16.40, "Blue Bottle Coffee", "cat-dining",        nil,      "pending", nil),
            (4,  "everyday", -1_850, "Apartment Rent",     "cat-rent",          nil,      nil,       nil),
            (5,  "everyday",  4_200, "Acme Corp Payroll",  "cat-salary",        nil,      nil,       nil),
            (6,  "credit",   -28.75, "Shell Gas",          "cat-transport",     nil,      nil,       nil),
            (7,  "cash",     -12.00, "Food Truck",         "cat-dining",        nil,      nil,       nil),
            (8,  "credit",   -64.99, "Uniqlo",             "cat-shopping",      nil,      nil,       nil),
            (9,  "credit",    -9.99, "Netflix",            "cat-entertainment", nil,      nil,       ["tag-subscription"]),
            (10, "everyday",  -88.30, "PG&E Utilities",    "cat-utilities",     nil,      nil,       nil),
            (11, "credit",    64.99, "Nordstrom Refund",   "cat-shopping",      "refund", nil,       ["tag-vacation"]),
            (12, "credit",   -53.20, "Trader Joe's",       "cat-groceries",     nil,      nil,       nil),
            (13, "credit",   -22.50, "Chipotle",           "cat-dining",        nil,      nil,       nil),
            (14, "credit",   -31.00, "Uber",               "cat-transport",     nil,      nil,       ["tag-business"]),
            (16, "credit",  -120.00, "Nordstrom",          "cat-shopping",      nil,      nil,       ["tag-vacation"]),
            (17, "cash",     -18.00, "Farmers Market",     "cat-groceries",     nil,      nil,       nil),
            (19, "credit",   -45.60, "CVS Pharmacy",       "cat-health",        nil,      nil,       ["tag-reimbursable"]),
            (20, "everyday",  4_200, "Acme Corp Payroll",  "cat-salary",        nil,      nil,       nil),
            (21, "credit",   -38.40, "Safeway",            "cat-groceries",     nil,      nil,       nil),
            (23, "credit",   -14.25, "Starbucks",          "cat-dining",        nil,      nil,       nil),
            (25, "credit",   -19.99, "Spotify",            "cat-entertainment", nil,      nil,       ["tag-subscription"]),
            (27, "credit",   -27.80, "Lyft",               "cat-transport",     nil,      nil,       ["tag-business", "tag-reimbursable"]),
            (30, "credit",   -58.10, "Whole Foods",        "cat-groceries",     nil,      nil,       nil),
            (33, "credit",   -72.00, "AMC Theatres",       "cat-entertainment", nil,      nil,       nil),
            (35, "everyday",  4_200, "Acme Corp Payroll",  "cat-salary",        nil,      nil,       nil),
            (38, "credit",   -41.30, "Trader Joe's",       "cat-groceries",     nil,      nil,       nil),
            (42, "credit",   -33.50, "Olive Garden",       "cat-dining",        nil,      nil,       nil),
            (46, "credit",   -95.00, "Best Buy",           "cat-shopping",      nil,      nil,       ["tag-business"]),
            (50, "everyday", -1_850, "Apartment Rent",     "cat-rent",          nil,      nil,       nil),
            (55, "credit",   -49.90, "Costco",             "cat-groceries",     nil,      nil,       ["tag-reimbursable"]),
            (60, "credit",   -24.00, "Shell Gas",          "cat-transport",     nil,      nil,       nil),
            (68, "credit",   -61.40, "REI",                "cat-shopping",      nil,      nil,       ["tag-vacation"]),
        ]
        for t in txns {
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")]
            if let k = t.kind { args["kind"] = .string(k) }
            if let s = t.status { args["status"] = .string(s) }
            if let tg = t.tags { args["tagIds"] = .array(tg.map { .string($0) }) }
            try apply("addTransaction", args)
        }
```

- [ ] **Step 3: Add the transfer.** Immediately **after** that `for t in txns { … }` loop, insert:

```swift
        // A real posted transfer (Everyday → Savings) so the transfer kind shows in the feed.
        try apply("createTransfer", [
            "fromAccountId": .string("everyday"), "toAccountId": .string("savings"),
            "fromAmount": .double(500), "date": .string(ymd(15)), "time": .string("12:00")])
```

- [ ] **Step 4: Build iOS** (see Task 2 Step 3) — or after Task 2.

---

### Task 2: Installment plan + FX rate

**Files:** Modify `ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift`

- [ ] **Step 1: Installment plan.** Immediately **after** the existing `for s in scheduled { … }` loop, insert:

```swift
        // An installment plan so the Scheduled tab shows installment progress.
        try apply("createScheduled", [
            "ledgerId": .string("personal"), "name": .string("Furniture Plan"),
            "type": .string("expense"), "amount": .double(120), "frequency": .string("monthly"),
            "accountId": .string("credit"), "dayOfMonth": .double(12),
            "startDate": .string(monthStart(2)), "category": .string("cat-shopping"),
            "installmentTotal": .double(12)])
```

- [ ] **Step 2: FX rate.** Immediately **after** the `createLedger … "travel" … "EUR"` line, insert:

```swift
        // EUR↔USD rate (USD is the hub; only non-USD stored) so the Travel ledger converts.
        try apply("setExchangeRate", ["date": .string(ymd(1)), "currency": .string("EUR"), "rate": .double(1.08)])
```

- [ ] **Step 3: Build iOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit** (Tasks 1 + 2 together)

```bash
git add ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift
git commit -m "feat(ios): richer demo data — tags, pending, refund, transfer, installment, FX"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Fresh re-seed + install:**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/dr-dd >/dev/null 2>&1
xcrun simctl list devices booted | grep -q "$SIM" || { xcrun simctl boot "$SIM"; open -a Simulator; sleep 5; }
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl uninstall "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl install "$SIM" /tmp/dr-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab ledger
```

- [ ] **Step 2: DB spot-check** (authoritative — UI screenshots are secondary):

```bash
C=$(xcrun simctl get_app_container "$SIM" com.juchengquan.finch data); DB="$C/Library/Application Support/finch.sqlite3"
echo "tags: $(sqlite3 "$DB" "SELECT count(*) FROM tags;")"                                  # 4
echo "tagged entries: $(sqlite3 "$DB" "SELECT count(DISTINCT entry_id) FROM entry_tags;")"  # ~11
echo "pending: $(sqlite3 "$DB" "SELECT count(*) FROM entries WHERE status='pending';")"      # 2
echo "refund: $(sqlite3 "$DB" "SELECT count(*) FROM entries WHERE kind='refund';")"          # 1
echo "transfer entries: $(sqlite3 "$DB" "SELECT count(*) FROM entries WHERE kind='transfer';")"  # >=1
echo "EUR rate: $(sqlite3 "$DB" "SELECT rate FROM exchange_rates WHERE currency='EUR';")"    # 1.08
echo "installment: $(sqlite3 "$DB" "SELECT name||' '||installment_total FROM scheduled_templates WHERE installment_total IS NOT NULL;")"  # Furniture Plan 12
```

- [ ] **Step 3: UI screenshots** — Ledger feed shows colored **tag chips**, a **pending clock** (Whole Foods/Blue Bottle), the **Nordstrom Refund** badge, and a **Transfer** row → `/tmp/dr-ledger.png`. Scheduled shows **Furniture Plan** installment line → `/tmp/dr-scheduled.png`. Clean up `/tmp/dr-dd` after.

- [ ] **Step 4 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: tags + apply (T1 S1-2), pending/refund (T1 S2), transfer (T1 S3), installment (T2 S1), FX (T2 S2), build (T2 S3), manual incl. DB checks (T3). ✓
- Type/action consistency: `addTransaction` accepts `kind`/`status`/`tagIds`; `createTransfer` `fromAccountId`/`toAccountId`/`fromAmount`; `createScheduled` `installmentTotal`; `setExchangeRate` `date`/`currency`/`rate`. Account/category/tag ids all exist in the seed. ✓
- No engine change; demo seed only. ✓
