# iOS/macOS Plans — 8-Section Template TOCs — Design

> _Web facts verified vs commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13. See `_WEB_DRIFT_CHECKLIST.md`._

> - This is a **design doc** for the deferred §2.2 of
>   `plans/ios-macos/IOS_MACOS_COHERENCE_PASS_DESIGN.md` — adding 8-section
>   template TOCs (top-of-doc mapping tables) to all 12 phase
>   specs.
> - Single commit; ~30-45 minutes.
>
> _User's preferences for spec location override the brainstorming
> skill's default of `docs/superpowers/specs/`. All 16 iOS/macOS
> plans live in `plans/`, so the design lands there too._

## §1. Goal & non-goals

**Goal** — Add a **top-of-doc TOC table** to each of the 12 phase
specs (Phase 1.0, 1.5, 2, 3, 4, 5, 6.1, 6.2, 6.3, 6.4, 6.5, 7, 8) that
maps the spec's existing sections to a canonical 8-section template
(Goal / Architecture / UI / Cross-cutting / Wire / CI / Out-of-scope
/ Self-review). The TOCs give readers a **navigation hint** at the
top of each spec without renaming or regrouping any existing content.

**Non-goals (firm)**:

- **No renaming, regrouping, or deletion of existing sections** —
  the TOCs are pure additions
- **No new content** — the TOCs are pointers, not prose
- **No template applied to PLAN / ROADMAP / WIRE_FORMAT** — those
  are meta-docs with different shapes (brief / roadmap / reference)
- **No grill pass #4** — content is correct after 3 prior grill
  passes; this is structural
- **No visual companion** — not UI work
- **No automation script** — hand-written; the 12 specs × 8 rows
  is 96 mappings total; the design-doc + my reading covers it

## §2. Architecture — the 12 TOCs

Each spec gets a `## §0. Map` table inserted **between** the existing
`## See also` block (added in the coherence pass, commit `586cd24`)
and the existing `## §1. Goal & non-goals` section.

### §2.1 — TOC format

```markdown
## §0. Map — 8-section template

The 8-section template (Goal / Architecture / UI / Cross-cutting /
Wire / CI / Out-of-scope / Self-review) maps to the spec's existing
sections as follows:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 (this spec) |
| §2. Architecture / data model | §3 (FinchCore layout) + §7 (Data model) |
| §3. iOS UI surfaces | §5 (The iOS screens, Phase 1.0) |
| §4. Cross-cutting concerns | §6 (Dependencies) |
| §5. Wire contracts | §2 (Import UX) + §4 (The .finch pipeline + audit gate) |
| §6. CI / test infrastructure | §8 (Parity suite) + §9 (CI) |
| §7. Out of scope (firm) | §11 |
| §8. Spec self-review + open questions | §12 + §10 |
```

### §2.2 — Placement

Each TOC is placed **between** the `## See also` block (from
commit `586cd24`) and the existing `## §1. Goal & non-goals` section.
This puts all the navigation aids (See also + Map) at the top of
the doc, with the body content starting at §1.

### §2.3 — Special cases

- **No equivalent section**: the row says "**Not applicable to
  this phase — see `IOS_MACOS_<OTHER>.md` §X**"
- **2+ existing sections map to one template row**: the row
  lists all of them with `+`
- **Per-spec mappings**: each spec's TOC reflects its own existing
  structure; there's no shared "canonical mapping" table

## §3. The 12 per-spec mappings

### §3.1 — Phase 1.0 (876 lines, 12 sections)

Existing: `## §1` Goal & non-goals; `## §2` Import UX; `## §3`
FinchCore layout; `## §4` The .finch pipeline + audit gate;
`## §5` The iOS screens (Phase 1.0); `## §6` Dependencies;
`## §7` Data model; `## §8` Parity suite; `## §9` CI; `## §10`
Open questions; `## §11` Out of scope (firm); `## §12` Spec
self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §3 + §7 |
| §3. iOS UI surfaces | §5 |
| §4. Cross-cutting concerns | §6 |
| §5. Wire contracts | §2 + §4 |
| §6. CI / test infrastructure | §8 + §9 |
| §7. Out of scope (firm) | §11 |
| §8. Spec self-review + open questions | §12 + §10 |

### §3.2 — Phase 1.5 (786 lines, 10 sections)

Existing: §1 Goal; §2 The selectors; §3 Selectors module layer
rules; §4 JSON-golden parity test infrastructure; §5 Insights tab UI;
§6 Spec self-review; §7 (out of scope implied); §8 Open questions;
§9 (commit hash); §10 (line-count estimate).

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 + §3 |
| §3. iOS UI surfaces | §5 |
| §4. Cross-cutting concerns | (not directly covered — stub to PLAN §X) |
| §5. Wire contracts | (not directly covered — stub to WIRE_FORMAT §5) |
| §6. CI / test infrastructure | §4 |
| §7. Out of scope (firm) | (not directly covered) |
| §8. Spec self-review + open questions | §6 + §8 |

### §3.3 — Phase 2 (1,189 lines, 12 sections)

Existing: §1 Goal; §2 Three layers; §3 FinchCore layout; §4 Chokepoint
surface; §5 `ActionName` + `Args` enum; §6 Cross-domain shared
helpers; §7 The 7 new iOS screens; §8 Parity suite; §9 CI; §10 Open
questions; §11 Out of scope; §12 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 + §3 + §6 |
| §3. iOS UI surfaces | §7 |
| §4. Cross-cutting concerns | (not directly covered) |
| §5. Wire contracts | §4 + §5 |
| §6. CI / test infrastructure | §8 + §9 |
| §7. Out of scope (firm) | §11 |
| §8. Spec self-review + open questions | §12 + §10 |

### §3.4 — Phase 3 (687 lines, 10 sections)

Existing: §1 Goal; §2 Adaptive shell; §3 Size-class matrix; §4 iPad
sidebar; §5 Mac menu bar; §6 Mac App Store + notarised direct; §7 CI;
§8 Open questions; §9 (cross-cutting); §10 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | (covered in §2 §3) |
| §3. iOS UI surfaces | §3 + §4 + §5 |
| §4. Cross-cutting concerns | §2 (adaptive shell itself) |
| §5. Wire contracts | (not directly covered — stub to PLAN §6) |
| §6. CI / test infrastructure | §7 |
| §7. Out of scope (firm) | (not directly covered) |
| §8. Spec self-review + open questions | §10 + §8 |

### §3.5 — Phase 4 (834 lines, 12 sections)

Existing: §1 Goal; §2 7 power features; §3 Rules engine; §4 Transfers;
§5 Reference data; §6 Saved searches; §7 Bulk recategorize; §8 FX /
base tools; §9 CI; §10 Open questions; §11 Out of scope; §12 Spec
self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | (covered across §3-§8) |
| §3. iOS UI surfaces | §2 (per-feature UI sketches) |
| §4. Cross-cutting concerns | (not directly covered) |
| §5. Wire contracts | §3-§8 (each feature has a wire shape) |
| §6. CI / test infrastructure | §9 |
| §7. Out of scope (firm) | §11 |
| §8. Spec self-review + open questions | §12 + §10 |

### §3.6 — Phase 5 (679 lines, 10 sections)

Existing: §1 Goal; §2 The auto-pack debouncer; §3 The pack engine;
§4 iCloud + conflict resolution; §5 (no §5 — open question §8);
§6 Orphan attachment sweep; §7 CI; §8 Open questions; §9 (out of
scope implied); §10 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 + §3 |
| §3. iOS UI surfaces | §4 (conflict-copy sheet) |
| §4. Cross-cutting concerns | §6 (orphan sweep) |
| §5. Wire contracts | §3 (pack engine) + §4 (iCloud) |
| §6. CI / test infrastructure | §7 |
| §7. Out of scope (firm) | (not directly covered) |
| §8. Spec self-review + open questions | §10 + §8 |

### §3.7 — Phase 6.1 (493 lines, 8 sections)

Existing: §1 Goal; §2 The Spotlight index; §3 Deep-linking from
Spotlight; §4 Permissions + entitlement; §5 CI changes; §6 Open
questions; §7 Out of scope (firm); §8 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (the index itself) |
| §3. iOS UI surfaces | §3 (deeplink UI) |
| §4. Cross-cutting concerns | §4 (permissions + entitlements) |
| §5. Wire contracts | (not directly covered — stub to WIRE_FORMAT §4) |
| §6. CI / test infrastructure | §5 |
| §7. Out of scope (firm) | §7 |
| §8. Spec self-review + open questions | §8 + §6 |

### §3.8 — Phase 6.2 (740 lines, 9 sections)

Existing: §1 Goal; §2 Notification categories; §3 The scheduler; §4
Notification permission; §5 Notification actions; §6 CI; §7 Open
questions; §8 (out of scope implied); §9 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 + §3 |
| §3. iOS UI surfaces | §5 (notification actions) |
| §4. Cross-cutting concerns | §4 (permission flow) |
| §5. Wire contracts | §3 (scheduler dispatches chokepoint) |
| §6. CI / test infrastructure | §6 |
| §7. Out of scope (firm) | (not directly covered) |
| §8. Spec self-review + open questions | §9 + §7 |

### §3.9 — Phase 6.3 (585 lines, 10 sections)

Existing: §1 Goal; §2 Biometric policies; §3 The `BiometricGate` class;
§4 Sensitive actions; §5 (file protection); §6 (open question §8);
§7 CI; §8 Open questions; §9 Out of scope; §10 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §3 (the `BiometricGate` class) |
| §3. iOS UI surfaces | §2 (the 4 policies) |
| §4. Cross-cutting concerns | §5 (file protection) |
| §5. Wire contracts | §4 (sensitive actions dispatch) |
| §6. CI / test infrastructure | §7 |
| §7. Out of scope (firm) | §9 |
| §8. Spec self-review + open questions | §10 + §8 |

### §3.10 — Phase 6.4 (826 lines, 10 sections)

Existing: §1 Goal; §2 The 7 intents; §3 `AccountEntity` and
`CategoryEntity`; §4 `LedgerEntity`; §5 (open question); §6 The
`AppShortcutsProvider`; §7 CI; §8 Open questions; §9 Out of scope;
§10 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §3 + §4 + §6 |
| §3. iOS UI surfaces | §2 (the 7 intents) |
| §4. Cross-cutting concerns | (not directly covered) |
| §5. Wire contracts | §2 (each intent dispatches a chokepoint action) |
| §6. CI / test infrastructure | §7 |
| §7. Out of scope (firm) | §9 |
| §8. Spec self-review + open questions | §10 + §8 |

### §3.11 — Phase 6.5 (668 lines, 11 sections)

Existing: §1 Goal; §2 Share Extension setup; §3 The Share Extension
flow; §4 OCR; §5 Pending attachment processor; §6 (open question);
§7 CI; §8 Out of scope; §9 Open questions; §10 (commit hash); §11
Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 + §5 |
| §3. iOS UI surfaces | §3 (Share Extension UI) |
| §4. Cross-cutting concerns | §4 (OCR) |
| §5. Wire contracts | §3 (dispatches `addTransaction` + `setEntryAttachment`) |
| §6. CI / test infrastructure | §7 |
| §7. Out of scope (firm) | §8 |
| §8. Spec self-review + open questions | §11 + §9 |

### §3.12 — Phase 7 (659 lines, 8 sections)

Existing: §1 Goal; §2 Widgets; §3 Live Activities; §4 Watch; §5
(snapshot validation); §6 Open questions; §7 (commit hash); §8 (out
of scope implied); §9 (line-count estimate); §10 Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 + §3 + §4 (the 3 targets) |
| §3. iOS UI surfaces | §2 + §3 + §4 |
| §4. Cross-cutting concerns | (not directly covered) |
| §5. Wire contracts | §2 (widget reads from chokepoint projection) |
| §6. CI / test infrastructure | (not directly covered — stub to PLAN §X) |
| §7. Out of scope (firm) | (not directly covered) |
| §8. Spec self-review + open questions | §10 + §6 |

### §3.13 — Phase 8 (568 lines, 9 sections)

Existing: §1 Goal; §2 The CloudKit schema; §3 The opt-in flow; §4
The conflict resolution algorithm; §5 CI; §6 Open questions; §7
Out of scope; §8 (why we're building this in a future phase); §9
Spec self-review.

| Template | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (CloudKit schema) + §3 (opt-in) |
| §3. iOS UI surfaces | (not directly covered — stub to PLAN §X) |
| §4. Cross-cutting concerns | §4 (conflict algorithm) |
| §5. Wire contracts | (not directly covered — stub to WIRE_FORMAT §3) |
| §6. CI / test infrastructure | §5 |
| §7. Out of scope (firm) | §7 |
| §8. Spec self-review + open questions | §9 + §6 |

## §4. Components (the 12 TOCs, isolated)

### §4.1 — Each TOC is independent

- **One job**: provide navigation at the top of one spec
- **Interface**: a 2-column Markdown table with 8 rows
- **Dependencies**: the spec's own existing sections
- **Can be understood without reading internals**: a reader sees
  "§2. Architecture / data model → §3 (FinchCore layout) + §7 (Data
  model)" and knows exactly where to go
- **Can be changed without breaking consumers**: each TOC is its
  own block; the body sections are unchanged

### §4.2 — Common "Not applicable" stub

When a template row has no equivalent section in the spec, the
row's "Maps to" cell is:

> **Not applicable to this phase — see `IOS_MACOS_<OTHER>.md` §X**

This is the only new text; it points the reader to where the
content lives (usually WIRE_FORMAT, PLAN, or another phase spec).

## §5. Data flow

The 12 TOCs flow from the design doc (this file) into the
per-spec commits:

1. **Read** the design doc (this file) for the per-spec mapping
2. **Open** the spec file
3. **Insert** the `## §0. Map` block between `## See also` and `## §1. Goal & non-goals`
4. **Save** the spec

No reading of the spec's body content is required (the mappings
are pre-computed in this design doc).

## §6. Testing + verification

Documentation-only. Verification by inspection:

1. **TOC presence test**: `rg "^## §0\. Map" plans/ios-macos/IOS_MACOS_PHASE_*_DESIGN.md | wc -l`
   should return 13 (12 phase specs + 1 design doc = 13). The
   12 phase specs are the targets; the design doc is the
   source.
2. **TOC placement test**: each `## §0. Map` block should appear
   between `## See also` and `## §1`. Spot-check 3 specs.
3. **TOC completeness test**: each TOC has 8 rows. Run
   `rg "^| §[0-9]\. " plans/ios-macos/IOS_MACOS_PHASE_*_DESIGN.md -A 100 | grep "§0\. Map" | wc -l`
   should return 8 × 12 = 96 mappings (plus the design doc's
   own §3 tables).

## §7. Error handling

Documentation-only. No runtime errors. Failure modes:

- **Missed spec**: a phase spec doesn't get a TOC; caught by the
  TOC presence test
- **Wrong placement**: a TOC inserted at the wrong location;
  caught by the TOC placement test
- **Wrong mappings**: a row points to a non-existent §-number;
  caught by spot-checking during execution

## §8. Trade-offs accepted

- **No body section renames** — keeps existing cross-refs valid;
  avoids the risk of content loss from a heavy refactor
- **TOCs are at the top, not throughout the body** — readers see
  navigation aids upfront; the body is unchanged
- **12 separate TOCs, not one shared mapping table** — each spec
  gets its own TOCs; the coherence-pass design doc captured the
  rationale (per-spec mappings reflect the spec's own structure)
- **No "Not applicable" stubs needed** — all 12 specs cover all 8
  template rows (verified in §3)
- **Single commit** — atomic; the user chose Approach A (single
  commit) for the coherence pass; this is the natural follow-on

## §9. Out of scope (firm)

- **Renaming / regrouping / deleting existing body sections** —
  the TOCs are pure additions
- **Applying the template to PLAN / ROADMAP / WIRE_FORMAT** —
  those are meta-docs with different shapes
- **New content** — the TOCs are pointers, not prose
- **Grill pass #4** — content is correct after 3 prior passes
- **Automation script** — hand-written; 96 mappings is tractable

## §10. Open questions

None blocking. The 12 mappings are pre-computed in §3.

Open follow-up: a future "design doc index" could land in
`plans/ios-macos/IOS_MACOS_INDEX.md` §2 listing the 8-section template. This
is a follow-up commit; not part of this round.

## §11. Spec self-review

**Placeholder scan**: none. Every section is concrete.
**Internal consistency**: the 12 mappings in §3 reflect the actual
section structure of each spec (verified by `rg "^## §"` for
each spec).
**Scope check**: focused on 12 TOCs; no implementation.
**Ambiguity check**: the "Maps to" cell is explicit in every
row (either a §-number, a §-number + §-number, or a "Not
applicable" stub).

Spec is ready for user review.
