# "Add to Scheduled" from a detected recurring charge

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** Tap a detected recurring charge (#359) to open a pre-filled `ScheduledSheet` and create a scheduled template; the row clears once added. Additive engine fields + a prefill init + a tappable row.

## Problem

The recurring-charge detector (#359) lists untracked subscriptions read-only. The
natural next step — "yes, schedule this" — isn't wired. And `RecurringCharge` doesn't
carry the account/category needed to pre-fill the sheet, and "scheduled" is judged only
by historical `sourceTemplateId`, so a freshly-created template wouldn't clear the row.

## Design

### 1. Engine (`Selectors.detectRecurring` + `RecurringCharge`)

`RecurringCharge` gains the data a prefill needs (additive):

```swift
    public let accountId: String?      // modal account across the group
    public let categoryId: String?     // modal category across the group
```
(Add to the struct + memberwise init.)

`detectRecurring` gains a `scheduled` param so "already scheduled" also matches by
**merchant name**, and computes the modal account/category per group:

```swift
public static func detectRecurring(_ txns: [Tx], _ ledgerId: String, _ today: String,
                                   _ scheduled: [ScheduledTemplate] = [],
                                   minOccurrences: Int = 3) -> [RecurringCharge]
```
- Precompute `scheduledNames = Set(scheduled.map { normalized($0.name) })`.
- Per group: `accountId` = most-frequent `tx.account`; `categoryId` = most-frequent
  non-nil `tx.category` (a small `mode(_:)` helper).
- `isScheduled = items.contains { sourceTemplateId set } || scheduledNames.contains(normalized(merchantName))`.

Pure/additive; the only caller (the ScheduledTab from #359) is updated to pass
`store.scheduled`. `ParityTests` unaffected.

### 2. `ScheduledSheet` — prefill init

Add an init alongside `init(template:prefillStart:)`:

```swift
    init(fromCharge c: RecurringCharge) {
        self.template = nil
        _name = State(initialValue: c.merchantName)
        _kind = State(initialValue: .expense)
        _amount = State(initialValue: String(format: "%g", c.averageAmount))
        _accountId = State(initialValue: c.accountId ?? "")
        _fromAccountId = State(initialValue: "")
        _categoryId = State(initialValue: c.categoryId ?? "")
        _frequency = State(initialValue: c.cadence)            // cadence values == ScheduledSheet frequencies
        _dayOfMonth = State(initialValue: Int(c.nextEstimatedDate.split(separator: "-").last ?? "1") ?? 1)
        _startDate = State(initialValue: AppDate.isoDay.date(from: c.nextEstimatedDate) ?? Date())
        _installmentEnabled = State(initialValue: false)
        _installmentTotal = State(initialValue: "")
    }
```
Everything else (the form, `createScheduled` on save) is unchanged — the user reviews
and taps save. If `accountId`/`category` came back empty, the user just picks them.

### 3. Scheduled-tab — tappable detected rows

- `detected` now passes templates: `Selectors.detectRecurring(store.txns, store.activeLedgerId, store.today, store.scheduled).filter { !$0.isScheduled }`.
- Wrap each detected row in a `Button { addFromCharge = r }` (`.buttonStyle(.plain)`,
  `.contentShape(Rectangle())`); add `@State private var addFromCharge: RecurringCharge?`
  + `.sheet(item: $addFromCharge) { ScheduledSheet(fromCharge: $0) }`.
- After save, a template named after the merchant exists → the name-match flips
  `isScheduled` → the row drops off and the new template appears in the list above.

## Out of scope
- Editing the detected charge before scheduling beyond what the sheet already allows;
  recurring income; an "ignore/dismiss" action. Any change to `createScheduled`.

## Testing
- **Engine:** extend `DetectRecurringTests` — modal `accountId`/`categoryId` populated;
  `isScheduled` true when a template's name matches the merchant. Full suite + ParityTests green.
- **App:** build iOS + macOS.
- **Manual (sim):** seed a monthly merchant → Scheduled tab "Detected" row → **tap** →
  `ScheduledSheet` opens pre-filled (name/amount/frequency/account) → **save** → the row
  disappears and the template shows in the scheduled list.

## Notes
- `RecurringCharge` is `Identifiable` (id = merchantKey) → works with `.sheet(item:)`.
- PR targets `feat/frontend`.
