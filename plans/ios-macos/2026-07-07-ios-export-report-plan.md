# iOS export — monthly report PDF + Settings CSV — Implementation Plan

**Spec:** `plans/ios-macos/2026-07-07-ios-export-report-design.md`. No FinchCore changes; no schema changes.

## Task 1 — `ReportPdf.swift` (model + view + renderer) + test

- Create `ios/FinchApp/Sources/FinchApp/ImportExport/ReportPdf.swift`:
  - `struct MonthlyReportModel` (pre-formatted strings; `CategoryRow { name, amount, pct }`, `MerchantRow { name, amount }`).
  - `struct MonthlyReportView: View` — 612 pt fixed width, white/black print styling, header / stats / category table / merchants / footer.
  - `@MainActor enum ReportPdf { static func render<V: View>(_ view: V, width: CGFloat = 612) -> Data? }` — `ImageRenderer` + `CGDataConsumer`/`CGContext` single PDF page.
- Create `ios/FinchApp/Tests/FinchAppTests/ReportPdfTests.swift` — fixed model → `%PDF-` magic bytes.

## Task 2 — Breakdown "Export PDF" button

- `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift` (`BreakdownView`):
  - Add an "Export PDF" button beside "Export CSV"; builds `MonthlyReportModel` from the already-computed `cats`/`total` + `Selectors.monthlyCashflow(…, month, 1).last` + `Selectors.topMerchants(…, month)`; formats money via `store.displayMoneyBase`; renders via `ReportPdf.render`; writes `finch-report-<ledger>-<month>.pdf` to tmp; reuses the existing `exported` sheet (SharePreview from the filename).

## Task 3 — Settings CSV row + docs

- `ios/FinchApp/Sources/FinchApp/ImportExport/ExportButton.swift`: add `ExportCsvButton` (Face-ID gate → `store.transactionsCsv(month: nil)` → tmp → ShareLink; same error-alert pattern).
- `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`: add the row to `SettingsImportExportView`; extend the footer copy.
- Handoff: split the polish row — PDF report + Settings CSV shipped; **tax export stays open** pending the web `is_tax_relevant` schema feature.

## Verification

- CI: FinchApp tests (incl. `ReportPdfTests`) + FinchMac + FinchWatch builds. `ImageRenderer`/`ShareLink` are cross-platform at our targets — no `#if os` expected.
- Post-merge by hand: PDF layout eyeball + share-sheet flow on the simulator.
