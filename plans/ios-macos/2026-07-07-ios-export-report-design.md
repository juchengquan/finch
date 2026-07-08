# iOS export — monthly report PDF + Settings CSV — Design

**Date:** 2026-07-07
**Scope:** the "PDF/CSV/tax export" polish theme from the handoff backlog. A scoping sweep found the CSV machinery already shipped — `TxExport` in FinchCore (13-column web-parity CSV, tested) and a month-scoped ShareLink export on Insights › Breakdown. What's actually missing:

1. **PDF report export** — net-new on BOTH platforms (no PDF rendering exists anywhere in `ios/` or `frontend/`). FEATURE_IDEAS §5.3 ("one-page PDF/PNG … for accountability partners or bookkeepers") is the closest prior scoping.
2. **An "export all transactions" surface** — the Core call (`store.transactionsCsv(month: nil)`) supports it; only Breakdown's month-scoped button exists. UI-only gap.
3. **Tax export** — ⊘ out of scope here: it requires the `is_tax_relevant` schema change (FEATURE_IDEAS §8.1 / MASTER_PLAN item 2) which belongs with the web feature; the iOS surface should follow that schema, not front-run it.

## Design

### 1. Monthly report PDF (Insights › Breakdown)

- **`MonthlyReportModel`** — a pure struct of pre-formatted strings (ledger name, month label, income / spent / net, category rows with name+amount+pct, top-merchant rows, generated-at stamp). The caller formats money via the store helpers; the view and renderer stay dumb and unit-testable.
- **`MonthlyReportView`** — a print-styled static SwiftUI view: fixed 612 pt width (US Letter), explicit white background / black text (independent of app theme), header (finch · ledger · month), a 3-stat row, the category table with the shared card-palette dots, top merchants, footer stamp. One page, content-sized height (§5.3's one-pager).
- **`ReportPdf.render(view)`** — `ImageRenderer` (iOS 16+/macOS 13+; targets are 17/14) → `CGContext` PDF via `CGDataConsumer`; returns `Data?`. `@MainActor` (ImageRenderer requirement).
- **UI:** an "Export PDF" button in `BreakdownView` beside the existing CSV button; same temp-file + `ShareLink` sheet pattern; filename `finch-report-<ledger>-<month>.pdf`.
- Data comes from the selectors Breakdown already uses plus `monthlyCashflow` (income/spent for the picked month) and `topMerchants` (#412).

### 2. Settings › Import & Export — "Export transactions (.csv)"

- New `ExportCsvButton` next to the `.finch` `ExportButton`: `store.transactionsCsv(month: nil)` (active ledger, all months) → temp file → `ShareLink`.
- **Face-ID gated** like the pack export — it carries the same transaction data (`gate.confirmSensitive()`).
- Scope note: the store wrapper is active-ledger-scoped by design (matches every other in-app surface); the web's all-ledgers CSV remains the cross-ledger path.

## Testing

- `ReportPdfTests` (FinchAppTests): render a fixed `MonthlyReportModel` → data is non-nil and starts with the `%PDF-` magic bytes. This is a real end-to-end render on the simulator, not a mock.
- CSV path is already covered by `TxExportTests` (Core) — the new button is wiring only.

## Acceptance

- Breakdown: "Export PDF" produces a shareable one-page PDF of the picked month; CSV button unchanged.
- Settings › Import & Export: a Face-ID-gated CSV row exports the active ledger's full history.
- FinchApp + FinchMac + FinchWatch build; `ReportPdfTests` green. Visual polish of the PDF layout is a post-merge eyeball (blind-authored layout).
