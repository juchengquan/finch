# Localize the tab titles (zh-Hans coverage — focused fix)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** Make `AppTab.title` return the localized string so the tab bar / sidebar / palette show Chinese under zh-Hans. One-line-per-case code change, no catalog/engine change.

## Problem

After the language picker (#338), some chrome stayed English under zh-Hans — most
visibly the **bottom tab labels**. Diagnosis: `AppTab.title` returns a plain `String`
("Ledger", "Accounts", …), and `Text(stringVariable)` does **not** localize a `String`
value (only literals / `LocalizedStringKey` do). The translations already exist in the
catalog (`Ledger`=账本, `Accounts`=账户, `Activity`=动态, `Budgets`=预算, `Insights`=洞察,
`Scheduled`=计划, `Settings`=设置) — they just aren't being looked up.

## Design

In `DeepLink/DeepLinkRouter.swift`, change `AppTab.title` to resolve each case through
the catalog with `String(localized:)`:

```swift
    public var title: String {
        switch self {
        case .ledger: return String(localized: "Ledger")
        case .accounts: return String(localized: "Accounts")
        case .activity: return String(localized: "Activity")
        case .budgets: return String(localized: "Budgets")
        case .insights: return String(localized: "Insights")
        case .scheduled: return String(localized: "Scheduled")
        case .settings: return String(localized: "Settings")
        }
    }
```
`String(localized:)` looks the key up in `Localizable.xcstrings` against the app's active
localization (the `AppleLanguages` override from #338), so `title` returns 账本/账户/…
under zh-Hans and the English source otherwise. Because the change is at the source, **all
consumers** localize with no render-site edits: the compact tab bar, the regular-width
sidebar, the command palette ("Go to …"), the ⌘1–6 shortcut titles, and any nav title.

`title` is **display-only** — identifiers use `AppTab.rawValue` (e.g. `-initialTab`,
`route(to:)`, notification `userInfo`), so localizing the human label is safe.

## Out of scope / logged follow-up

This fixes the tab labels only. A broader **localization-bypass audit** remains and is
logged for later (not this PR):
- Other `Text(stringVariable)` / `String`-valued labels that bypass localization the same
  way (audit `Text(...)` call sites for non-literal arguments).
- Strings that aren't catalog keys at all — e.g. **"This month"**, **"No transactions in
  this ledger yet."** — which need adding to the `build-xcstrings.ts` source (the catalog
  is generated, so additions go through the build, not hand-edits).
- Tracked in the parity inventory's *zh-Hans translation coverage* backlog item.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** set the language override (`defaults write com.juchengquan.finch
  AppleLanguages -array zh-Hans`) + relaunch → the **bottom tab bar** now reads
  账本 / 账户 / 预算 / 计划 / 洞察 (was English in #338); clearing the override → English.

No engine test — display-string change; the catalog already holds the values.

## Notes
- No catalog edit (the 7 keys already have zh-Hans), so the `build-xcstrings.ts` pipeline
  is untouched. PR targets `feat/frontend`.
