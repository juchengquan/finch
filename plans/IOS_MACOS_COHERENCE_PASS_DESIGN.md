# iOS/macOS Plans Coherence Pass — Design

> - This is a **design doc** for a coherence pass on the 16 iOS/macOS plan files
> - The pass produces: a new `IOS_MACOS_INDEX.md` + an 8-section template applied to 15 specs + cross-reference backfill + stale-pointer fixes
> - Single commit; everything lands together
>
> _User's preferences for spec location override the brainstorming skill's default of `docs/superpowers/specs/`. All 16 iOS/macOS plans live in `plans/`, so the new index file lands there too._

## §1. Goal & non-goals

**Goal** — Improve the **navigability and consistency** of the 16 iOS/macOS design specs (`plans/IOS_MACOS_*.md`, ~13,000 lines after 3 grill passes + the wire-format annex). The 16 specs cover Phases 1.0-8 + Roadmap + Plan + Wire-format annex, with cross-references throughout. After this pass:

- A reader can find any recurring term in **1 place** (the new index)
- A reader can find the canonical location of any topic + 5-6 cross-references (the location index)
- Every "see §X" pointer in any spec names its target file (no bare "see §X" without a file name)
- Every spec has the same 8-section structure (fill or mark "Not applicable")
- Stale cross-references (e.g., "see §5" pointing to a §-number that doesn't exist in the target) are fixed

**Non-goals (firm)**:

- **No content changes** — the design decisions in the 15 phase specs are correct after 3 grill passes; this pass only adds navigation + structure
- **No new design content** — the wire-format annex (1,420 lines) and the 15 phase specs are the source of truth; we only add cross-references
- **No implementation planning** — this is documentation-only; no writing-plans skill invoked
- **No grill pass #4** — the previous 3 grill passes found and fixed 100+ issues; this pass is structural, not analytical
- **No visual companion** — these are design docs, not UI work
- **No AI-tooled cross-ref check** — the backfill is hand-done based on the 3 grill pass reports; not a separate "audit and fix" pass

## §2. Architecture — the 3 deliverables

### §2.1 — `plans/IOS_MACOS_INDEX.md` (new file, ~400 lines)

A new index file with 4 sections:

**§1. Glossary** (~120 lines) — recurring terms + their canonical numbers, each in 1-2 lines. The glossary is **alphabetical**, not topical. Example entries:
- `74 unique chokepoint actions` (75 with Phase 6.5's `setEntryAttachment`)
- `32 selectors` (7 in 1.0, 25 in 1.5; 8 selector groups)
- `13 per-domain mutations.ts files` (out of 14 first-class domains; `attachments/` is queries-only)
- `8 audit-corruption fixtures` (the web's 8 audit problem classes)
- `4 tabs → 5 tabs → 6 tabs` (post-Phase 1.0 / 1.5 / 2)
- `7 write screens` (Phase 2 + Holdings tab; 6 without)
- `App Group container: group.com.juchengquan.finch` (added in Phase 6.5 §2.2, not Phase 5)
- `Anomaly threshold: 2.5` (per `lib/select.ts`)
- `Force import: in Settings › Advanced` (not behind `?debug=1`)
- `Passcode fallback: iOS-device-passcode via LAContext` (not app-implemented)
- `MIGRATIONS array: lib/db/core/schema.ts` (not `entries.ts`)
- `FTS5 indexes: description + notes` (not counterparties or merchants)
- ... ~20-30 more entries

**§2. Location index** (~200 lines) — for each recurring topic, 1 canonical location + 5-6 cross-references. Topics covered:
- 74 actions, 32 selectors, 7 iPhone tabs
- App Group, Force import, 75th action
- Pack format, fixture format, I18nError
- Parity test harness, audit gate, audit problem classes
- Settings › Advanced, biometric, passcode fallback
- Conflict resolution, anomaly threshold, FTS5
- MIGRATIONS, schemaversion, package format
- Argvs enum, chokepoint dispatcher
- Tab order post-Phase 1.0 / 1.5 / 2

**§3. Master iPhone tab list** (~80 lines) — the canonical tab list:
- **Phase 1.0**: 4 tabs (Accounts / Activity / Budgets / Settings)
- **Phase 1.5**: 5 tabs (adds Insights)
- **Phase 2**: 6 tabs (adds writable Scheduled; Reports is the 5th by display order)
- The mobile-tab ordering, the iPad sidebar ordering, the Mac sidebar ordering

**§4. Cross-spec impact** (the new file's own meta) — a table of all 16 specs + which §-changes they need to make.

### §2.2 — 8-section structural template

Every phase spec (15 of them, all except the wire-format annex) gets the same 8 sections in the same order:

1. **§1. Goal & non-goals** — the one-liner; what this phase ships; what it explicitly doesn't
2. **§2. Architecture / data model** — Swift modules, GRDB tables, selectors, the chokepoint surface
3. **§3. iOS UI surfaces** — SwiftUI views, screen-by-screen, with the wire shape
4. **§4. Cross-cutting concerns** — error handling, performance, a11y, security, privacy, iCloud
5. **§5. Wire contracts** — what this phase reads from / writes to the chokepoint, the pack, the App Group, the deep-link router
6. **§6. CI / test infrastructure** — what the macos job does; what new fixtures land; what parity tests run
7. **§7. Out of scope (firm)** — explicit non-goals
8. **§8. Spec self-review + open questions** — what was just checked; what's still unresolved

Sections are **filled with content** if applicable, **marked "Not applicable to this phase — see `IOS_MACOS_<OTHER>.md` §X"** otherwise. The §-numbering stays consistent so cross-refs work.

For specs that already have 8 sections, the template is a **map** (renaming or regrouping existing content to fit). For specs that have 4-6 sections, the template is a **refactor** (filling in the missing sections with the current content, possibly under a slightly different name).

**Per-spec template application**:
- **Phase 1.0** (876 lines, well-structured): rename existing sections to match; minor regrouping
- **Phase 1.5** (786 lines, well-structured): same
- **Phase 2** (1,189 lines, dense): same
- **Phase 3** (687 lines, well-structured): same
- **Phase 4** (834 lines, dense): same
- **Phase 5** (679 lines, well-structured): same
- **Phase 6.1** (493 lines, thinnest): may need a few sections filled with "Not applicable" stubs
- **Phase 6.2-6.5** (568-826 lines, mixed): same
- **Phase 7** (659 lines, well-structured): same
- **Phase 8** (568 lines, well-structured): same
- **PLAN** (1,332 lines, the brief): a different template (it's a brief, not a phase)
- **ROADMAP** (702 lines, the 8-phase arc): a different template (it's a roadmap, not a phase)

For PLAN + ROADMAP, the template is **optional** — the user said "all 16 specs" but PLAN + ROADMAP have different shapes (a brief + a roadmap are not phase specs). The 15 phase specs get the 8-section template; PLAN + ROADMAP get minor adjustments to add the new index back-references.

### §2.3 — Cross-reference backfill + stale-pointer fixes

Every "see §X" pointer in the 15 phase specs gets a 1-line backfill that names the target file. Example:

**Before**:
> See §4 for the import pipeline.

**After**:
> See `IOS_MACOS_PHASE_1_DESIGN.md` §4 for the import pipeline.

Each spec's §1 will also gain a 1-line `## See also` block listing the 3-5 other specs it most commonly cross-references. This is the inverse of the location index.

**Stale-pointer fixes** are applied opportunistically (when a backfill lands on a §-number that's wrong, fix it in the same edit). Common stale patterns from the 3 grill passes:
- `see §5` that should be `see §3` (after a section move)
- `see §7.8` that should be `see §7.8 (Holdings tab)` (now exists)
- `see §11.4` for a §-number that doesn't exist in the target spec

**Estimated counts**:
- ~150 cross-references to backfill across the 15 specs
- ~10-20 stale pointers to fix
- ~16 `## See also` blocks to add

## §3. Data flow + implementation

### §3.1 — Implementation order (single commit, internal phases)

The single commit has 4 internal phases applied in order:

1. **Phase A**: Add `plans/IOS_MACOS_INDEX.md` (the new file, ~400 lines)
2. **Phase B**: Apply the 8-section template to the 15 phase specs (in order: 1.0, 1.5, 2, 3, 4, 5, 6.1, 6.2, 6.3, 6.4, 6.5, 7, 8)
3. **Phase C**: Backfill the cross-references across all 15 specs (a separate pass that touches each file)
4. **Phase D**: Fix any stale pointers found during Phase C

Phases B and C are interleaved in practice (when applying the template to a spec, I also backfill its cross-refs). Phases A is independent (it adds a new file). Phase D is opportunistic.

### §3.2 — Commit structure

A single commit with the message:

```
docs(plans): coherence pass — index file + 8-section template + cross-ref backfill

Adds:
- plans/IOS_MACOS_INDEX.md (~400 lines) — new glossary + location
  index + master iPhone tab list

Updates 15 phase specs:
- 8-section template applied (Goal, Architecture, UI, Cross-cutting,
  Wire, CI, Out of scope, Self-review)
- Cross-references backfilled (~150 fixes) — every "see §X" now
  names the target file
- ~16 "## See also" blocks added to each spec's §1
- ~10-20 stale §-number pointers fixed opportunistically

This is documentation-only. No design changes. The 3 prior
grill passes (commits ea7871e, 137f102, b75713b) settled the
content; this pass only adds navigation + structure.
```

### §3.3 — Validation

After the commit, run:
- `rg "see §" plans/IOS_MACOS_*.md` — should return only lines that include a file name (e.g., "see `IOS_MACOS_<FILE>.md` §X")
- `rg "^## §" plans/IOS_MACOS_PHASE_*_DESIGN.md | wc -l` — should be 15 × 8 = 120 (or close, if a section is marked "Not applicable")
- `ls plans/IOS_MACOS_INDEX.md` — should exist

## §4. Components (the 3 deliverables, isolated)

### §4.1 — `IOS_MACOS_INDEX.md`

- **One job**: be the entry point for navigation
- **Interface**: 4 sections (glossary / location index / master tab list / cross-spec impact)
- **Dependencies**: reads from the 15 phase specs (one-time at write time)
- **Can be understood without reading internals**: a reader opens the index first, finds the topic, jumps to the right spec
- **Can be changed without breaking consumers**: additions / corrections to the index are independent; downstream specs cite the index but don't import it

### §4.2 — 8-section template

- **One job**: impose a uniform structure on the 15 phase specs
- **Interface**: 8 section names, in a fixed order
- **Dependencies**: each spec's existing content
- **Can be understood without reading internals**: a reader knows that §1 is always "Goal", §2 is always "Architecture", etc.
- **Can be changed without breaking consumers**: the 8-section structure is stable; per-section renames are follow-up commits

### §4.3 — Cross-ref backfill

- **One job**: every "see §X" pointer names the target file
- **Interface**: a textual convention (`see IOS_MACOS_<FILE>.md §X`)
- **Dependencies**: the location index (§2.1) is the canonical source for which file is the target
- **Can be understood without reading internals**: a reader scanning any spec can follow "see §X" without guessing which file it's in
- **Can be changed without breaking consumers**: textual-only; no compile-time or runtime impact

## §5. Testing + verification

This is documentation-only. There are no unit tests. Verification is by inspection:

1. **Glossary test**: every term in the glossary has a canonical number/file. Sample 5 terms, verify.
2. **Location index test**: every topic in the location index has a canonical file + ≥1 cross-reference. Sample 5 topics, verify.
3. **8-section template test**: every phase spec has 8 sections. Run `rg "^## §" plans/IOS_MACOS_PHASE_*_DESIGN.md | awk -F: '{print $1}' | sort | uniq -c` — should return 15 lines, each with count=8.
4. **Cross-ref test**: `rg "see §" plans/IOS_MACOS_*.md` — should return only lines that include a file name. A "bare" `see §X` (no file name) is a missed backfill.
5. **Stale-pointer test**: spot-check 5 cross-references; verify the §-number exists in the target spec.

## §6. Error handling

This is documentation-only. No runtime errors. The only failure modes are:
- **Missed backfill** — caught by the cross-ref test (#4 above)
- **Stale pointer** — caught by the stale-pointer test (#5 above)
- **Inconsistent glossary** — caught by the glossary test (#1 above)

If any test fails, the commit can be amended or a follow-up commit can fix.

## §7. Trade-offs accepted

- **Single commit, not three** — the user chose Approach A. The 3 internal phases (index → template → cross-refs) are independent, but the user preferred shipping them together for atomic review. Trade-off: harder to bisect if anything breaks; easier to review as a unit.
- **PLAN + ROADMAP get only minor updates** — they're not phase specs; the 8-section template doesn't fit. Trade-off: PLAN + ROADMAP look slightly different from the 13 phase specs.
- **8 sections, not 4** — the 4-section template (Goal / Design / Open questions / Self-review) was an option. The 8-section template gives more structure but requires more refactoring. The user chose 8.
- **No `## See also` block in PLAN or ROADMAP** — these are meta-docs; the `## See also` block is more useful in phase specs. PLAN + ROADMAP get the cross-ref backfill but not the new `## See also` section.
- **~400-line index file** — could be longer (full cross-reference map) or shorter (just the glossary). 400 lines is the user's choice; balances "navigable" with "not bloat."

## §8. Out of scope (firm)

- **No new design content** — the wire-format annex and the 15 phase specs are the source of truth
- **No implementation planning** — no writing-plans skill invoked
- **No grill pass #4** — content is correct; this is structural
- **No visual companion** — not UI work
- **No AI-tooled cross-ref check** — hand-done from the 3 grill pass reports
- **No TEST specs in the index** — `IOS_MACOS_PLAN.md` has its own §12 testing section; the index doesn't repeat it
- **No code changes** — documentation-only

## §9. Open questions

None blocking. All design decisions are settled:
- Single commit (Approach A)
- 8-section template
- ~400-line index
- All 16 specs in scope
- Cross-ref backfill + stale-pointer fixes

Open follow-up: the next coherence pass could add a "decision log" — a per-spec changelog of which grill pass changed what. This is out of scope for this round; can be a follow-up commit.

## §10. Spec self-review

**Placeholder scan**: none. Every section is concrete.
**Internal consistency**: the 3 deliverables (§2.1 / §2.2 / §2.3) are independent; each has its own §-references.
**Scope check**: focused on documentation; no implementation.
**Ambiguity check**: the 8-section names are explicit; the backfill convention is explicit ("see `IOS_MACOS_<FILE>.md` §X").

Spec is ready for user review.
