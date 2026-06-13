# Phase 1.0 buildability dry-run — consolidated gap report (working doc)

> **Transient working artifact** — delete once Phase 1.0 is hardened. Produced by 8 simulated-build
> agents (7 skeptical builders, one per task-group + 1 coverage critic) on 2026-06-13, each attempting
> to build Phase 1.0 from `IOS_MACOS_PHASE_1_0_PLAN.md` + `IOS_MACOS_PHASE_1_DESIGN.md` + the live web
> code at commit `22c9896`, logging every point a builder would have to stop and guess.

## Headline verdict
**Phase 1.0 is NOT buildable as written.** As-is, an agent would compile a *shell* and then fail the
parity gate that DESIGN §1 calls the headline quality bar. ~25–30 BLOCKERs cluster into **10 root
causes**. Encouragingly, the *web-fact citations are now accurate* (the drift pass worked) — almost
every blocker is a **plan-internal** problem: fabricated illustrative code, undefined types,
DESIGN↔PLAN contradictions, missing web-side prerequisites, and unspecified tooling.

## Per-task readiness (builder verdicts)
| Task | Verdict |
|---|---|
| 1 + 12 bootstrap/CI | blocked — 6 blockers (all plan-internal/tooling) |
| 2 schema | blocked — fabricated `entries` DDL + wrong migration model |
| 3 audit | blocked — 9 of 10 checks stubbed, fabricated seed |
| 4 + 5 pack/fixtures | blocked — missing web fixture infra + impossible pre-DE fixture |
| 6 + 7 selectors/projection | blocked — wrong-table projection, signature drift |
| 8 four-tab UI | blocked — undefined types, no FX conversion, skeleton tabs |
| 9–11 store/import/export | blocked — no atomic swap, no audit gate |
| coverage (vs DESIGN) | NOT fully covered — ~22 gaps + 1 hard contradiction |

---

## The 10 root causes
Each tagged **[DECISION]** (needs your call) or **[MECHANICAL]** (clear fix, just do it).

### R1 — Fabricated single-entry / `transactions`-shaped DDL & SQL · BLOCKER · [MECHANICAL]
*Tasks 2, 3, 6, 7, 9.* The plans embed illustrative `entries` DDL and projection/audit SQL using
columns from the **old single-entry model** (`merchant`, `amount_base`, `account_id`, `currency`,
`cleared_at`, `transfer_group_id`, `side`). In the real double-entry schema those live on **`postings`**;
`entries` is the DE shape (`kind` incl. `opening`, `dedup_hash`, `sealed`, `refunded_entry_id`…). A
builder copying any literal "verbatim" produces a schema/projection/audit that **can't open a web-built
`.finch`** or throws "no such column."
**Fix:** delete every embedded DDL/SQL literal; instruct "copy `SCHEMA` + `ENTRIES_SCHEMA` + the two
split constants byte-for-byte" (Task 2) and "port `projectState`'s `BASE_SELECT` + the two-pass
`enrichLegTxs`" (Tasks 6/7). Projection grain: **one Tx per account-leg posting**, `e.kind != 'opening'`,
`Tx.account = posting.account_id`, `Tx.amount = posting.amount_base`.

### R2 — The pre-DE migration contradiction · BLOCKER · [DECISION]
*Tasks 2, 4+5, coverage critic.* DESIGN §4-step-3 + §8.3 call a pre-DE→DE migration "the largest single
piece of ported logic, required for cross-app interop," and Task 5 builds a `pre-de.finch` fixture that
§8.3 tests. **But Task 2 says that migration is "intentionally absent, no `cutover.ts` to port," and the
web genuinely has no pre-DE codepath** (`assertCarryForwardable` throws; `seedDatabase` takes no version;
the cutover lives only in git history). So a headline parity test exercises logic that doesn't exist.
**Decision:** (a) **DROP** the pre-DE migration + `pre-de.finch` from Phase 1.0 and delete the §4-step-3/§8.3
claims (recommended — matches web reality; Phase 1.0 is fresh-DB-only), or (b) reinstate the DE cutover
as a versioned web `MIGRATIONS` entry + a seed-at-version hook *first*, then port it.

### R3 — Missing web-side fixture infrastructure · BLOCKER · [DECISION]
*Tasks 4+5, 6.* `scripts/export-fixtures.ts`, `lib/select.fixtures.ts`, and the `CASES` array **do not
exist** — they must be *authored on the web side first*, not ported. Worse, **3 of the 7 selectors**
(`accountBalance`, `budgetProgress`, `cycleWindow`) have **zero** tests in `select.test.ts`, so the
"7 selectors × 3 = 21 fixtures" math is impossible. The `SelectorFixture.input` shape also disagrees
across three docs (`unknown` vs positional array vs named object), and fixture paths are inconsistent.
**Decision:** approve a **web-side prerequisite task** — create `lib/select.fixtures.ts` with a curated
`CASES` array (incl. the 3 uncovered selectors), the `export-fixtures.ts` generator, pin the `input`
shape in WIRE_FORMAT §5.1, and standardize the fixture path. (This is the parity oracle the whole port
leans on — it has to exist before Tasks 5/6/8 can be verified.)

### R4 — Import pipeline: no atomic swap, no audit gate · BLOCKER · [MECHANICAL]
*Tasks 9–11, critic.* `loadPack` opens the extracted **temp** DB and projects from it — **no persistent
swap** (so an import vanishes on next launch) — and **runs the audit without gating on it** (imports
dirty data unconditionally, which makes the "Force import" hatch meaningless). Contradicts DESIGN §4 and
the web's `importPackBytesLocked` + `assertImportAuditClean` (which throws on any problem, pre-swap).
**Fix:** rewrite `loadPack` to mirror DESIGN §4: extract → migrate → **audit-gate (throw `auditFailed`)**
→ atomic swap into Application Support (+ `.bak.<ts>`, move attachments) → re-open → project. Reserve
unconditional projection for `forceImportCurrentPack`. Add the 5 pipeline `PackError` cases.

### R5 — Undefined types & incomplete projection surface · BLOCKER · [MECHANICAL]
*Tasks 6, 7, 8, 9.* Referenced-but-never-defined: `Budget`/`BudgetRow`, `Ledger`, `Category`,
`Counterparty`, `ListOptions`, `MerchantStats` (plan calls it `MerchantStat`), `AnomalyScore`,
`CycleWindow`, `BudgetProgress`. `Projection` defines only `.run`, but Task 9 calls
`.ledgers/.accounts/.budgets/.rowCounts`. Signature drift: `budgetProgress` has wrong params (missing
`today`, invents `spendByCategory`), `Tx.amountNative` should be `nativeAmount`, `TxSplit` drops
`amountBase`, `cycleWindow` default `isRecurring=0` should be `1`. **Several of these contradict the
plan's own design §7.**
**Fix:** add a types/projection task defining all row types + the full `Projection` surface; correct every
signature to match `select.ts` + design §7; inline the small structs so tasks are self-contained.

### R6 — Money / display-currency conversion missing · BLOCKER · [MECHANICAL]
*Task 8.* `Money.format` does **no FX conversion** — it formats a raw `Decimal` in the row's native
currency. The web converts **ledger-base → display currency** (`useMoney`) before formatting, and DESIGN
§5 demands `Money.formatted(in: displayCurrency)`. As written, balances/net-worth render in mixed native
currencies with wrong totals; the `Money.format` doc-comment even contradicts its own signature.
**Fix:** port the conversion path (rate map + convert), format all three tabs through it.

### R7 — UI tabs are skeleton-only; mandated structure dropped · FRICTION→BLOCKER · [DECISION+MECHANICAL]
*Task 8, critic.* Accounts (no grouping/subtotals/net-worth footer), Activity (no date-grouping,
pagination, category badge; hardcoded `"USD"`), Budgets (no grouping/period-header/threshold-colors/
totals). Two contradictions/decisions: **(a) Activity search** — the plan cites FTS5, but the **web
Activity page uses client-side `merchant.includes`**, not FTS5 → mirror-web vs upgrade is a **[DECISION]**.
**(b) Detail views** (`AccountDetailView`, `TransactionDetailView`) are `// (...)` stubs — DESIGN puts
Transaction Detail *in* Phase 1.0, the plan leaves it unbuilt: **in-scope or defer? [DECISION]**.
Mechanical: specify per-tab structure; define the `AccountTypeIcon`/`TxnKindIcon` helpers; add empty
states.

### R8 — Tooling / scaffolding unspecified or contradictory · BLOCKER · [DECISION+MECHANICAL]
*Tasks 1, 12.* **Root-path contradiction** (`frontend/ios/` vs `ios/`) — every downstream path + CI
`working-directory` depends on it [MECHANICAL: pick one]. **FinchApp target undeclared** in `Package.swift`
(a SwiftUI `@main` app isn't a SwiftPM target). **`.copy("Fixtures")`** points at a dir that doesn't
exist → `swift test` errors, so Task 1's own acceptance is unmeetable. **Two conflicting CI jobs**, one
pinning **Xcode 16.0 which breaks GRDB 7** (needs 16.3+); CI **branch-trigger excludes the iOS branch**;
CI omits the export-fixtures + ParityTests steps. **No reproducible `.xcodeproj` generation** — the plan
says "Xcode wizard," which an agent can't do headlessly: **[DECISION]** XcodeGen vs Tuist vs committed
`project.pbxproj`. **ZIPFoundation vs system zip** — DESIGN §6 says "no third-party deps," the plan adds
ZIPFoundation: **[DECISION]**.

### R9 — Parity harness not wired · BLOCKER · [MECHANICAL]
*Critic, Tasks 3, 5, 6.* The `ParityTests` target DESIGN §8.5 mandates **doesn't exist** (Package.swift
declares only `FinchCoreTests` + `FinchAppTests`). §8.1 projection-parity, §8.2 audit-parity (Task 3
hand-seeds 2 inline cases instead of consuming the 10 fixtures), and §8.3 round-trip are unbuilt/unwired.
Manifest `Codable` is camelCase but the wire JSON is snake_case (decode silently fails — needs
`.convertFromSnakeCase`). The "byte-identical pack" claim is untestable (JSZip ≠ ZIPFoundation DEFLATE).
**Fix:** add the `ParityTests` macOS target + wire all three parity test types against the fixtures; fix
the Codable key strategy; state byte-identity is a **non-goal** and replace with a "round-trip a web-built
`.finch` and compare sha256s" test.

### R10 — Coverage gaps & naming inconsistencies · FRICTION/NIT · [MECHANICAL]
*Critic, Tasks 3, 8.* iCloud `Documents/finch/` folder + the `ICloud` module are **in-scope by DESIGN
(§3/§10) but built by no task** (1 blocker). Active-ledger switch doesn't re-run the projection (tabs
won't refresh). Audit `Problem` loses typed context (only `entryId`+`message`; DESIGN wants associated
values `legId/expected/actual/currency`; web field is `detail` not `message`). Naming clashes:
`AuditLedger` vs `Audit`, `ProblemKind` vs `AuditProblem`, `DatabasePool` vs `DatabaseQueue`,
`Tests/FinchCore/Fixtures` vs `Tests/Fixtures`. `DatabaseInfo` missing `formattedSize`/`lastImportedAt`/
row-counts. Empty states, theming tokens, accessibility pass, and the stubbed display-currency row all
unbuilt. Self-review's blanket "full coverage / Gaps: none" is an over-claim on essentially every row.

---

## Decisions you need to make (the [DECISION] items)
| # | Decision | Recommended |
|---|---|---|
| D1 | **Pre-DE migration** (R2): drop from Phase 1.0, or reinstate the web cutover first? | **Drop** — matches web reality; Phase 1.0 is fresh-DB-only |
| D2 | **Fixture infra** (R3): approve a web-side prerequisite task to author `select.fixtures.ts` + `CASES` + the 3 missing selector tests? | **Yes** — it's the parity oracle everything depends on |
| D3 | **Activity search** (R7): mirror the web (client-side `merchant.includes`) or upgrade to FTS5? | **Mirror web** for Phase 1.0; FTS5 later |
| D4 | **Detail views** (R7): Transaction/Account detail in Phase 1.0 or defer? | Your call — defer keeps 1.0 lean |
| D5 | **Xcode project generation** (R8): XcodeGen, Tuist, or committed `.pbxproj`? | **XcodeGen** (checked-in `project.yml`, agent-reproducible) |
| D6 | **Zip** (R8): ZIPFoundation or system `UTType.zip`? | Pin **ZIPFoundation** + update DESIGN §6 (system zip API is painful) |
| D7 | **Force-import hatch** (R4): keep as iOS-only divergence or drop? | Keep, but label as a deliberate native divergence (web has no skip path) |

## Suggested fix sequence (once decisions land)
1. **Web-side prerequisite** (D2): author `select.fixtures.ts` + `export-fixtures.ts` (+ tests for the 3 uncovered selectors). Unblocks R3/R9.
2. **R1 + R5**: replace fabricated DDL/SQL with verbatim-source instructions; define all types + the full projection surface. Unblocks 2/3/6/7/9.
3. **R4**: rewrite the import pipeline (swap + audit gate + PackError).
4. **R8**: pick root path, declare/​defer FinchApp, XcodeGen spec, one correct CI job.
5. **R6 + R7 + R9 + R10**: money conversion, per-tab structure, parity harness, remaining coverage/naming.
6. Resolve D1/D3/D4/D6/D7 inline as their sections are touched.
