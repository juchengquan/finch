# Write-Sheet Icon Rows — Design

**Status:** approved design, ready for planning
**Date:** 2026-07-23
**Scope:** the native add/edit write-sheet family (`ios/FinchApp`) — iOS · macOS

## Goal

Restyle every editable row in the add/edit write sheets from the current
`[name] … [value]` (label left, value right) into an icon-led, placeholder-driven
row: `[colored field icon]  value-or-grey-placeholder  ……  [one disclosure]`.
The field name shows in grey **only while the row is empty**; once a value is
present it takes the full row width. This frees horizontal space for values
(long account names, merchants, categories, multi-currency amounts) that today
get squeezed into the right half of the row.

## Motivation

Today a row spends ~40% of its width on a static label that never changes. The
value — the part the user actually reads and scans — is crammed into the
remaining right half and truncates. Moving the label into the empty-state
placeholder and giving the value the full width (minus a small leading icon)
roughly doubles the room for values, and the leading icon carries the field's
identity so nothing is lost from a scanning standpoint.

This mirrors Apple's own Calendar / Reminders event editors: a colored leading
glyph per field, the value filling the row, a trailing disclosure.

## The model (one rule for every row)

```
[colored field glyph]   value  ·or·  grey field-name placeholder   ……   [one trailing disclosure]
```

- **Placeholder → value.** Empty row shows the field name in grey (secondary).
  A filled row replaces it with the value, left-aligned right after the icon.
  The text label never persists alongside a value.
- **Fixed per-field icon.** Each field always shows the same glyph regardless of
  the selected value (the wallet row is *always* Account). The icon — not text —
  is the row's persistent identity, so it must be stable.
- **Per-field color, no tile.** The glyph carries its own color from a fixed
  palette (Account blue, Amount green, …). Color lives on the symbol itself; no
  filled rounded-square background. Colorful but light — friendly to finch's
  restrained "warm editorial / noir" aesthetic.
- **Exactly one trailing disclosure per row.** A row whose action is a *menu*
  (Amount's inline currency menu, Status) already renders the menu's own `⌵`
  chevron — that counts as the disclosure, nothing is added. A row that *opens a
  sheet* (Account, Category, Date, Merchant, Tags, Receipt, Refund source) shows
  a plain trailing chevron `›`. A pure inline **text** row that opens nothing and
  has no menu (Note, New balance) shows no trailing accessory — there is nothing
  to disclose, and a decorative chevron there would falsely imply a chooser.
- **Grouped `Form` + sections + type caption stay.** Only the rows inside change.
  The existing section grouping (main fields / status+tags / receipt / details),
  the small type caption above the first section, and the house rule that the
  first section carries no header are all preserved. This keeps the change inside
  finch's tokenized sheet layout (`finchSheetForm()`, section gaps) rather than
  fighting it, and matches how Apple's Calendar editor groups fields.

## Scope

The **whole add/edit write-sheet family** adopts the look at once, for
consistency (the Add sheet is the family's layout blueprint):

- Add Transaction (expense / income / transfer / refund)
- Adjust Balance (rides along — it lives inside the Add sheet)
- Edit Transaction
- Scheduled sheet
- Account sheet
- Budget sheet

It is delivered by restyling the **shared row components in place** —
`SearchablePickerRow`, `CategoryPickerRow`, `MerchantPickerRow`, `TagField`, and
the small inline `HStack` text/menu rows — so every sheet that consumes them
updates together. The picker *sheets* those rows present (the full-height
searchable lists) are unchanged; only the collapsed in-form row changes.

## Icon + color palette

Fixed glyph + color per field. SF Symbols, all available on the iOS 17 / macOS 14
deployment floor. Colors are drawn from a single curated palette (system colors
/ finch semantic tokens) so light + dark + macOS all render for free.

| Field | SF Symbol | Color |
|---|---|---|
| Account | `building.columns` | blue |
| From account (transfer) | `arrow.up.circle` | blue |
| To account (transfer) | `arrow.down.circle` | blue |
| Amount / New balance | `dollarsign.circle` | green |
| Category | `folder` | orange |
| Date | `calendar` | red |
| Merchant / Source | `storefront` | purple |
| Note | `note.text` | secondary (grey) |
| Status | `checkmark.circle` | teal |
| Tags | `tag` | pink |
| Receipt | `camera` (iOS) / `paperclip` (macOS) | indigo |
| Refund source | `arrow.uturn.backward.circle` | indigo |

The palette lives in **one place** (a small `FieldGlyph` enum/table) so it is
defined once and every sheet reads from it, rather than each call site passing
loose strings and colors. The exact glyphs/colors are tweakable during
implementation without changing the model.

## Row-by-row behavior

- **Pickers** (Account, From, To, Category, Merchant/Source, Refund source):
  icon + selected name, or grey field-name placeholder when unset. Trailing `›`.
  (Account/From/To/Merchant are always seeded, so their empty state is rare;
  Category and Refund source can legitimately be empty.)
- **Amount / To amount / New balance**: icon + the typed number (left-aligned
  after the icon), grey `0.00` placeholder when empty. Amount rows keep their
  inline **currency menu** pinned trailing — its `⌵` is the row's disclosure.
  The mirrored same-currency transfer "To amount" stays disabled + secondary.
- **Date**: icon + formatted date, trailing `›` (the compact date picker).
- **Status**: icon + Confirmed/Pending as a menu; the menu `⌵` is the disclosure.
- **Tags**: `tag` glyph + grey "Tags" when none, wrapping colored chips when
  selected (row grows vertically, unchanged), trailing `›` (opens the multi-select
  sheet).
- **Receipt**: icon + grey "Add receipt" when none, thumbnail + filename/"Receipt"
  when attached, trailing `›`. Keeps the `#if os` split (PhotosPicker on iOS,
  fileImporter on macOS).
- **Note**: icon + grey "Optional" placeholder, inline multi-line text field,
  no trailing accessory.

## Accessibility

Because the visible text label disappears once a row is filled, the icon alone
is **not** a sufficient VoiceOver label. Every row gets an explicit
`accessibilityLabel` of its field name (e.g. "Account", "Amount"), with the value
as the accessibility value. This is part of the row treatment, not optional —
the icon is decorative to VoiceOver.

## macOS parity

`FinchMac` shares these sources, so every symbol and color must resolve on macOS
14. All chosen SF Symbols exist on macOS; per-field colors use system/semantic
colors that adapt to light/dark on both platforms. The Receipt row keeps its
existing `#if os(macOS)` fileImporter branch. No iOS-only API is introduced.

## Non-goals (YAGNI)

- No change to the picker **sheets** themselves (searchable lists, Confirm/Cancel).
- No change to save/validation logic, engine calls, or field semantics — this is
  purely presentational.
- No value-reflecting icons (category's own icon, account glyph). The icon is a
  fixed field identity, decided against dynamic value icons.
- No filled color tiles. No per-field colored backgrounds.
- No new fields, no reordering of existing fields.
- The consumer-side read screens (transaction detail, lists) are untouched.

## Risks & mitigations

- **Uniform chevrons read as "opens a sheet."** Accepted trade-off for a
  consistent right edge, softened by the rule that inline text/menu rows use the
  menu disclosure or nothing rather than a fake chevron.
- **Placeholder-only labels reduce at-a-glance field identification** for a user
  who doesn't know the icons yet. Mitigated by fixed, conventional glyphs +
  color, and by the empty state literally spelling the field name.
- **Shared-component blast radius.** Restyling the shared rows touches every
  write sheet at once. Mitigated by keeping the change presentational and
  additive (an icon + color per call site), and by building + measuring each
  sheet (`idb ui describe-all`) rather than eyeballing.
- **Localization.** New placeholder / accessibility strings must go through the
  generated `Localizable.xcstrings` pipeline (`finchSectionHeader` +
  `String(localized:)`), not raw `String`s, or they ship English to zh-Hans.

## Testing strategy

- **Pure helpers unit-tested** where any logic is extracted (e.g. the
  `FieldGlyph` field→symbol→color mapping is a pure table and can be asserted).
- **Both builds green** (FinchApp iOS + FinchMac) at every task.
- **On-simulator visual check** per sheet with `idb ui describe-all` to confirm
  row frames/insets stay within the tokenized layout (type caption `y≈138 h≈52`,
  first content row `y≈202`), and that filled/empty states render as specified.
- **i18n guards** pass (new strings reach `extracted-keys.json` + the catalog).

## Open decisions locked during design

1. Filled label → **replaced by value** (placeholder model). ✅
2. Icon → **fixed per field**, not value-reflecting. ✅
3. Scope → **whole add/edit family**, via shared components. ✅
4. Disclosure → **one per row**; menu `⌵` counts, sheet rows get `›`, bare text
   rows get none. ✅
5. Structure → **keep grouped Form + sections + type caption**. ✅
6. Icon style → **per-field colored glyphs, no tile**. ✅
7. Placeholder copy → **bare field name** ("Category", not "Choose category"). ✅
