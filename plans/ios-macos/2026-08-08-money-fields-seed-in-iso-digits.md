# Money Fields Seed In ISO Digits — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every money text field shows the currency's ISO 4217 digits — when the app fills it, and after you finish typing. And no field can ever seed in scientific notation.

**Architecture:** `2e6861fe` made *typing* obey ISO 4217 but left every field's *seed* on `String(format: "%g", …)`. One formatter replaces all sixteen; `moneyInput` gains the blur reformat and the four money fields that never got the clamp receive it.

**Tech Stack:** Swift 5.9 / SwiftUI (`ViewModifier`, `@FocusState`), XCTest. App target `ios/FinchApp` only.

## Global Constraints

- **Branch:** `fix/money-seeds-iso-digits`, cut from `origin/feat/frontend`.
- **PRs target `feat/frontend`.** Never `main`.
- **No `Co-Authored-By` trailer in commits.**
- **iOS + macOS app only.** No `ios/FinchCore`, no `frontend/`. `FinchAppSwiftUI` compiles into **both** targets — `project-mac.yml` includes the whole directory with no excludes — so `DecimalInput.swift` must build for macOS. `keyboardType` is already called there unguarded and FinchMac builds, so follow that precedent rather than adding `#if os(iOS)`.
- **No new catalog strings.** Nothing here is user-visible text.
- **Build:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` **and** `PATH="$DEVELOPER_DIR/usr/bin:$PATH"`.
- **The gate:** `ios/scripts/ci-local.sh` is the pre-push gate. This touches ~20 input fields across seven sheets, so it needs **`--ui`**. Do not pass `SIM_NAME`.
- **Both projects are generated and gitignored.** Use `xcodegen generate --spec project.yml,project-mac.yml` — a bare `xcodegen generate` regenerates FinchApp only, leaving FinchMac.xcodeproj referencing files a later commit deleted, which fails the Mac build for reasons unrelated to your change.
- After any `xcodebuild`, discard catalog churn:
  `git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings`

---

## Background: what `%g` actually does

`2e6861fe` gave `DecimalInput` a `zeroPlaceholder`, a `maxFractionDigits` clamp
and a `moneyInput` modifier. All three govern **typing and placeholders**. The
value the app puts *into* a field still goes through `String(format: "%g", …)`
at sixteen sites.

`%g` uses **six significant digits** and drops trailing zeros. Measured:

```
500.0        -> "500"            <- the reported bug
500.5        -> "500.5"
1234.56      -> "1234.56"
1234567.89   -> "1.23457e+06"    <- scientific notation
12345678.0   -> "1.23457e+07"
1000000.0    -> "1e+06"
```

**The second half is data corruption, not cosmetics.** `DecimalInput.parse`
tries `Double(t)` first, and `Double("1.23457e+06")` is `1234570.0` — so opening
a 1,234,567.89 transaction and pressing save writes **1,234,570.00**. Neither
`numericInput` nor `moneyInput` catches it: both filter `onChange` only, and a
seeded value never fires one.

It is most reachable in the currencies this work was about. ¥1,000,000 ≈ $6,700,
₩1,000,000 ≈ $750, ₫1,000,000 ≈ $40 — ordinary sums, all seeding as `1e+06`.

Read-only display is FINE: `Money.format` was fixed by that commit. This is
about text fields only.

### The four fields that never got clamped

Separate from seeding, four money fields still use plain `numericInput` with a
hardcoded `"0.00"` placeholder, so a 0-decimal currency invites cents it cannot
hold:

| Site | Field | Currency to use |
|---|---|---|
| `AddTransactionSheet:453` | adjust-balance "New balance" | `currency(of: accountId)` |
| `AdjustBalanceSheet:27` | the standalone twin | the sheet's account currency |
| `HoldingsView:117` | cost basis | the holding's currency |
| `HoldingsView:177` | price | the holding's currency |

Clamping a security **price** to 2 digits would truncate a finer quote — but no
price anywhere in the seeds or fixtures has more than 2 decimals, so nothing
that exists loses precision. Decided knowingly.

### Decisions (settled — do not relitigate)

1. **All sixteen seed sites**, through one helper.
2. **Seed at the currency's full digits** — `500.00`. The first keystroke is then
   swallowed until the user deletes (the clamp is already at max); accepted.
3. **Clamp all four missing fields**, each in its own currency.
4. **Zero seeds EMPTY, not `0.00`.** An empty field reads as "waiting"; that
   matters on page 2, where a zero cell now means the cell is *absent*.
5. **Reformat on blur**, so typed and seeded values agree.
6. **The filter sheet's min/max use the ledger base currency** — the only sites
   with no currency of their own; `BudgetSheet` sets that precedent.
7. **Blur does NOT reformat text ending in `.`** — that is someone mid-way
   through `5.75`, and rewriting to `5.00` would swallow their next keystroke.

---

## Task 1: One formatter, and the corruption test

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/Common/DecimalInput.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/DecimalInputTests.swift` (exists)

**Interfaces:**
- Produces: `DecimalInput.text(_ value: Double, currency: String) -> String` and
  `DecimalInput.text(_ value: Double, fractionDigits: Int) -> String`.
- Consumes: `Currencies.minorUnits(for:)`.

- [ ] **Step 1: Write the failing tests.** Append to `DecimalInputTests`:

```swift
    // MARK: seeding a field from a value

    /// The reported bug: a whole amount lost its minor units.
    func test_seedsAtTheCurrencysDigits() {
        XCTAssertEqual(DecimalInput.text(500, currency: "USD"), "500.00")
        XCTAssertEqual(DecimalInput.text(500, currency: "JPY"), "500")
        XCTAssertEqual(DecimalInput.text(500, currency: "BHD"), "500.000")
        XCTAssertEqual(DecimalInput.text(1234.5, currency: "USD"), "1234.50")
    }

    /// The half nobody would notice by eye, and the reason this is not cosmetic.
    ///
    /// `%g` carries six significant digits, so it rendered any large amount in
    /// SCIENTIFIC NOTATION — and `parse` accepts that as a different number.
    /// Seeding 1234567.89 gave "1.23457e+06", which parses back as 1234570.0, so
    /// opening a transaction and pressing save rewrote the amount. Neither input
    /// filter catches it: both run `onChange`, and a seeded value never fires one.
    func test_neverSeedsInScientificNotation() {
        for value in [1_000_000.0, 1_234_567.89, 12_345_678.0, 999_999_999.99] {
            let seeded = DecimalInput.text(value, currency: "USD")
            XCTAssertFalse(seeded.contains("e"), "\(value) seeded as \(seeded)")
            XCTAssertEqual(DecimalInput.parse(seeded) ?? 0, value, accuracy: 0.005,
                           "\(value) did not survive a seed/parse round trip")
        }
    }

    /// A 0-decimal currency must not gain a separator it cannot use.
    func test_aZeroDecimalCurrencySeedsWithNoSeparator() {
        XCTAssertEqual(DecimalInput.text(1_000_000, currency: "JPY"), "1000000")
        XCTAssertFalse(DecimalInput.text(1_000_000, currency: "JPY").contains("."))
    }

    /// An unknown code falls back to the ISO default of 2, matching
    /// `Currencies.minorUnits`.
    func test_anUnknownCurrencyGetsTwoDigits() {
        XCTAssertEqual(DecimalInput.text(5, currency: "ZZZ"), "5.00")
    }
```

- [ ] **Step 2: Run and record the failure.**

```bash
cd ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" && \
  xcodegen generate --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' \
  -only-testing:FinchAppTests/DecimalInputTests test 2>&1 | grep -E "error:|Executed"
```
Expected: does not compile — `DecimalInput.text` does not exist.

- [ ] **Step 3: Add the formatter.** In `DecimalInput`, beside `zeroPlaceholder`:

```swift
    /// The text to SEED an amount field with — the counterpart to `filter`, which
    /// governs typing.
    ///
    /// Every seed site used `String(format: "%g", …)`, which carries six
    /// significant digits and drops trailing zeros: 500 became "500", and — the
    /// half that mattered — 1234567.89 became "1.23457e+06", which `parse`
    /// accepts as 1234570.0. Opening a large transaction and pressing save
    /// rewrote the amount. Neither input filter catches it: both run
    /// `onChange`, and a seeded value never fires one.
    static func text(_ value: Double, currency: String) -> String {
        text(value, fractionDigits: Currencies.minorUnits(for: currency))
    }

    /// For the rare caller that knows its digits without a currency code.
    static func text(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", value)
    }
```

- [ ] **Step 4: Run — the whole class green.** Same command as Step 2.

- [ ] **Step 5: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: one formatter for seeding money fields

2e6861fe made typing obey ISO 4217 and left every field's SEED on
String(format: \"%g\"). %g carries six significant digits and drops trailing
zeros, so 500 seeded as \"500\" — the reported bug — and 1234567.89 seeded as
\"1.23457e+06\".

The second half is not cosmetic. parse() tries Double() first, and
Double(\"1.23457e+06\") is 1234570.0, so opening a large transaction and pressing
save rewrote the amount. Neither input filter catches it: both run onChange, and
a seeded value never fires one. Most reachable in JPY/KRW/VND, where a million
is an everyday sum — the currencies this work was for."
```

---

## Task 2: Blur reformats, so typed and seeded agree

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/Common/DecimalInput.swift` — `moneyInput`
- Test: `ios/FinchApp/Tests/FinchAppTests/DecimalInputTests.swift`

**Interfaces:**
- Consumes: `DecimalInput.text(_:currency:)` from Task 1.
- Produces: `moneyInput(_:currency:)` keeps its signature; behaviour gains the blur pass. **Every existing call site inherits it with no edit** — that is why this goes in the modifier and not in twenty sheets.

**No existing focus handling anywhere in the app** (`grep FocusState` is empty), so `@FocusState` here collides with nothing.

- [ ] **Step 1: Write the failing test** for the decision logic, kept separate from SwiftUI so it can be tested at all:

```swift
    // MARK: what blur does

    /// Typed and seeded values must agree, so leaving a field settles it to the
    /// currency's digits.
    func test_blurSettlesATypedValueToTheCurrencysDigits() {
        XCTAssertEqual(DecimalInput.settled("500", currency: "USD"), "500.00")
        XCTAssertEqual(DecimalInput.settled("500.5", currency: "USD"), "500.50")
        XCTAssertEqual(DecimalInput.settled("500.50", currency: "JPY"), "500")
    }

    /// Empty stays empty — an unset optional (rollover cap, last price, max
    /// filter) is not the same as zero, and a grid cell with nothing in it reads
    /// as "waiting" rather than "typed 0".
    func test_blurLeavesAnEmptyFieldEmpty() {
        XCTAssertEqual(DecimalInput.settled("", currency: "USD"), "")
        XCTAssertEqual(DecimalInput.settled("   ", currency: "USD"), "   ")
    }

    /// Mid-entry is left alone. "5." is someone on their way to 5.75; settling it
    /// to "5.00" would put the field at max digits and swallow their next
    /// keystroke — the exact trap this whole change has to avoid making worse.
    func test_blurLeavesMidEntryAlone() {
        XCTAssertEqual(DecimalInput.settled("5.", currency: "USD"), "5.")
        XCTAssertEqual(DecimalInput.settled("-", currency: "USD"), "-")
    }
```

- [ ] **Step 2: Run and record the failure.** Same command as Task 1 Step 2. Expected: `settled` does not exist.

- [ ] **Step 3: Add `settled`, then wire it to blur.** In `DecimalInput`:

```swift
    /// What a field should read once the user leaves it.
    ///
    /// Pure, and separate from the modifier, so the rules are testable without a
    /// view. Returns the input unchanged when there is nothing to settle.
    static func settled(_ s: String, currency: String) -> String {
        // Empty is UNSET, not zero — an optional field (rollover cap, last
        // price, max filter) and an untouched grid cell both rely on that.
        guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return s }
        // Mid-entry: "5." is on its way to 5.75. Settling it to "5.00" would sit
        // the field at max digits and swallow the next keystroke.
        guard !s.hasSuffix(".") else { return s }
        guard let value = parse(s) else { return s }
        return text(value, currency: currency)
    }
```

Then convert `moneyInput` to a `ViewModifier`, because `@FocusState` cannot live
in a `View` extension:

```swift
    func moneyInput(_ text: Binding<String>, currency: String) -> some View {
        modifier(MoneyInputModifier(text: text, currency: currency))
    }
}

/// A currency-denominated amount field: clamps typing to the currency's ISO 4217
/// minor units, hides the decimal key for 0-decimal currencies, re-trims when the
/// currency changes mid-entry, and — on blur — settles what was typed to the
/// currency's digits so a typed value reads the same as a seeded one.
///
/// A `ViewModifier` rather than a chain of `.onChange` because `@FocusState` has
/// to be owned by a view. Every existing caller gains the blur pass for free.
private struct MoneyInputModifier: ViewModifier {
    @Binding var text: String
    let currency: String
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        let digits = Currencies.minorUnits(for: currency)
        // allowsDecimal stays true even for 0-digit currencies: the max-0 clamp
        // CUTS at the separator (trim), where allowsDecimal:false would strip it
        // and glue the fraction onto the integer ("12.34" → "1234").
        content
            .keyboardType(digits == 0 ? .numberPad : .decimalPad)
            .focused($focused)
            .onChange(of: text) { _, newValue in
                let filtered = DecimalInput.filter(newValue, allowsDecimal: true, maxFractionDigits: digits)
                if filtered != newValue { text = filtered }
            }
            .onChange(of: currency) { _, newCurrency in
                let d = Currencies.minorUnits(for: newCurrency)
                let filtered = DecimalInput.filter(text, allowsDecimal: true, maxFractionDigits: d)
                if filtered != text { text = filtered }
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                let settled = DecimalInput.settled(text, currency: currency)
                if settled != text { text = settled }
            }
    }
}
```

- [ ] **Step 4: Build BOTH targets.** `DecimalInput.swift` compiles into FinchMac too — `project-mac.yml` includes the whole `FinchAppSwiftUI` directory.

```bash
cd ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH"
xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-splits' build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project FinchMac.xcodeproj -scheme FinchMac -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: both `BUILD SUCCEEDED`. If macOS objects to `keyboardType` or
`@FocusState`, stop — the existing `moneyInput` already calls `keyboardType`
unguarded and FinchMac builds today, so a failure means the `ViewModifier`
conversion changed something else.

- [ ] **Step 5: Run the unit suite, then commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "feat: leaving a money field settles it to the currency's digits

Seeded fields will read \"500.00\"; a field the user typed \"500\" into would have
stayed \"500\" — the same field with two appearances. Blur settles it.

moneyInput becomes a ViewModifier because @FocusState has to be owned by a view.
Every existing caller gains the blur pass with no edit, which is the point of
putting it here rather than in twenty sheets.

Empty stays empty: an unset optional and an untouched grid cell both depend on
that being distinct from zero. Text ending in \".\" is left alone — it is someone
on their way to 5.75, and settling it to 5.00 would sit the field at max digits
and swallow the next keystroke."
```

---

## Task 3: Every seed goes through the formatter

**Files (16 sites):**

| File | Lines | Currency |
|---|---|---|
| `AddTransactionSheet.swift` | 547, 582, 585, 619 | `amountCurrency`; transfer legs use `currency(of: fromAccountId)` / `currency(of: toAccountId)`; 619 is `currency(of: accountId)` |
| `EditTransactionSheet.swift` | 120, 502, 519, 520 | `txn.currency ?? accountCurrency`; 519/520 are the transfer legs' OWN currencies |
| `BudgetSheet.swift` | 50, 65, 68 | `store.baseCurrency` |
| `ScheduledSheet.swift` | 50, 71 | `templateCurrency` |
| `AccountSheet.swift` | 48 | the account's currency |
| `TransactionFilterSheet.swift` | 65, 66 | `store.baseCurrency` (decision 6) |
| `PurchaseListSection.swift` | 67 | `currency` (already a property) |

**A transfer's two legs have DIFFERENT currencies.** `EditTransactionSheet:519`
and `:520` seed the from/to amounts; each must use its own leg's currency, the
same way `transferAmountRow` already passes `currency(of: fromAccountId)` and
`currency(of: toAccountId)` for typing. Seeding both from one currency is the
bug this table exists to prevent.

- [ ] **Step 1: Replace each site.** The shape is always the same:

```swift
// before
String(format: "%g", someValue)
// after
DecimalInput.text(someValue, currency: <the currency from the table>)
```

**Keep every existing zero/nil guard.** `PurchaseListSection:67` stays
`row.amount == 0 ? "" : DecimalInput.text(row.amount, currency: currency)`
(decision 4), and the `.map { }` on optionals stays as it is — `nil` must remain
an empty field, not `"0.00"`.

- [ ] **Step 2: Confirm none are left.**

```bash
grep -rn '%g' --include="*.swift" ios/FinchApp/Sources/
```
Expected: **no output.** Any survivor is either a money field that was missed or
a genuinely non-money value — if the latter, leave it and say which in the commit.

- [ ] **Step 3: Build both targets** (Task 2 Step 4's commands) and run the unit suite.

- [ ] **Step 4: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "fix: money fields seed in the currency's digits, not %g

Sixteen sites across seven sheets. 500 USD now seeds \"500.00\", 500 JPY seeds
\"500\", and no amount can seed in scientific notation — which was silently
rewriting large amounts on save.

A transfer's two legs seed from their OWN currencies, matching what
transferAmountRow already does for typing; one currency for both would be the
same class of bug one level down.

Zero and nil still seed EMPTY. An unset optional is not zero, and an untouched
grid cell reads as waiting rather than as a typed 0."
```

---

## Task 4: The four fields that were never clamped

**Files:**
- Modify: `AddTransactionSheet.swift:453`, `AdjustBalanceSheet.swift:27`, `HoldingsView.swift:117`, `HoldingsView.swift:177`

Each currently hardcodes `TextField("0.00", …)` with `numericInput` (or nothing).
Give each the placeholder and the clamp:

```swift
TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: <currency>)),
          text: $field)
    .moneyInput($field, currency: <currency>)
```

- [ ] **Step 1: Apply each field's own currency** — all four are known:

| Site | Currency expression |
|---|---|
| `AddTransactionSheet:453` | `currency(of: accountId)` |
| `AdjustBalanceSheet:27` | `account.currency ?? store.baseCurrency` — the sheet is locked to one `account: AccountRow` |
| `HoldingsView:117` | `holding.currency` — the same value line 85 already formats with |
| `HoldingsView:177` | `holding.currency` |

Note `AdjustBalanceSheet` takes `let account: AccountRow` and is "locked to one
account", so its currency is unambiguous; `AccountRow.currency` is optional, hence
the fallback.

- [ ] **Step 2: Drop the now-redundant modifiers.** `moneyInput` sets `keyboardType` itself, so remove any adjacent `.keyboardType(.decimalPad)` and `.numericInput(...)` on those four fields — leaving both means two filters racing on the same binding.

**`AddTransactionSheet:453` uses `.numbersAndPunctuation`** with a comment that it
allows a leading minus for a credit-card balance. `moneyInput` would replace it
with `.decimalPad`, which has **no minus key** — so a negative target balance
becomes untypeable. Keep that field's keyboard: apply the clamp via
`.numericInput` + an explicit `DecimalInput.filter(..., maxFractionDigits:)`
`onChange`, or leave the keyboard override after `moneyInput`. Verify a minus can
still be typed before committing.

- [ ] **Step 3: Build both targets, run the unit suite.**

- [ ] **Step 4: Commit.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git add ios/FinchApp
git commit -m "fix: the last four money fields obey ISO 4217 too

Both adjust-balance fields and Holdings' cost basis and price still hardcoded a
0.00 placeholder with no clamp, so a JPY account invited cents it cannot hold.

Clamping a security price to the currency's digits would truncate a finer quote,
but nothing in the seeds or fixtures carries more than two decimals, so nothing
that exists loses precision.

The adjust-balance field keeps its numbersAndPunctuation keyboard: decimalPad has
no minus key, and a credit-card balance is negative."
```

---

## Task 5: The gate

- [ ] **Step 1: Confirm the base.** `git fetch -q origin && git rev-list --count HEAD..origin/feat/frontend` → `0`, else rebase.

- [ ] **Step 2: Run the gate.**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" \
  ./scripts/ci-local.sh --ui --all
```
Expected: `gate passed`. The UI tests type into these fields —
`CategorySplitUITests` reads amounts back — so a seeding change that breaks
parsing shows up here.

- [ ] **Step 3: Discard churn, confirm scope.**

```bash
git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/"*.xcstrings
git status --short
git diff --stat origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/
```
Expected: `git status` silent; second diff EMPTY.

- [ ] **Step 4: Push and open the PR** against `feat/frontend`.

---

## Out of scope

- **Select-all on focus.** Considered and declined; a seeded field at max digits
  swallows the first keystroke until the user deletes.
- **Read-only display.** `Money.format` already obeys ISO 4217.
- **The web.** `frontend/lib/currency.ts` already mirrors the table.
- **Rates and quantities.** Shares, exchange rates and prices-per-unit are not
  currency-denominated and stay on `numericInput`.

## Verification checklist

- [ ] `ci-local.sh --ui --all` prints `gate passed`
- [ ] `grep -rn '%g' ios/FinchApp/Sources/` returns nothing (or only non-money values, named in the commit)
- [ ] 500 USD seeds `500.00`; 500 JPY seeds `500`; 500 BHD seeds `500.000`
- [ ] 1,000,000 seeds `1000000`, never `1e+06`, and survives a seed/parse round trip
- [ ] A cross-currency transfer seeds each leg in ITS OWN currency
- [ ] Zero and nil still seed an EMPTY field
- [ ] Typing `500` and leaving the field settles it to `500.00`; `5.` is left alone
- [ ] A negative target balance is still typeable on the adjust-balance field
- [ ] FinchMac builds
- [ ] `git diff origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/` is empty
