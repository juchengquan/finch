# Repo structure: one tree, one branch, components by directory (2026-08-08)

**Decision:** finch stays a single-branch monorepo. A proposal to split web,
iOS/macOS, and docs onto separate branches (or repos) was examined and declined.
The four pains behind it were addressed in-tree instead. This note records the
evidence so the question inherits an analysis, not a relitigation.

## Why branches cannot do what was asked

Branches version ONE tree; they cannot namespace components. A working tree
cannot "reference the real content from another branch" — directories are how a
tree is namespaced, and `frontend/` · `ios/` · `plans/` already do that.

## The coupling that makes a split expensive (measured 2026-08-08)

- `frontend/scripts/export-fixtures.ts` writes the iOS engine's test fixtures
  **into `ios/`** (two streams: `ParityTests/Fixtures`, `FinchAppTests/Fixtures`).
  The four parity gates assume fixture and engine share a commit.
- `ios/scripts/build-xcstrings.ts` reads `frontend/messages/{en,zh-CN}.json`
  at build time — the zh-Hans catalog derives from the web's translations.
- `FinchCore/Storage/Schema.swift` is byte-pinned to the web `schema.ts`
  (`Schema.version` == `SCHEMA_VERSION`).
- **15 of the last 200 commits touched both trees atomically** — e.g. the
  ISO 4217 minor-units table (2026-08-07) landed on both sides in one commit,
  pinned by a shared fixture, precisely because the sides must never drift.

A split would demote every one of these from same-commit guarantees to
versioned-artifact contracts with drift windows — the exact failure mode the
parity system was built to prevent — while the beneficiary (independent teams
or release cadences) does not exist.

## What was done instead

- **Web demoted to oracle** — the UI is frozen; the maintained surface is
  enumerated in root `CLAUDE.md` and `frontend/AGENTS.md`.
- **Navigation** — sparse-checkout recipes in root `CLAUDE.md` give a
  one-half working tree without touching history or parity.
- **Docs** — shipped dated design docs archived to `plans/ios-macos/done/`
  (mirroring the existing `plans/done/` convention); entry points
  (`MASTER_PLAN`, `IOS_MACOS_INDEX`, `database_design_en`) unmoved.
  Phase-doc archiving is available as a follow-up once phases are declared
  closed by the owner.
- **History noise** — scoped-log recipes; the `feat(ios):`-style prefixes
  remain the convention.

## The trigger that reopens this

Revisit a real split only when at least one is TRUE:

1. A second regular contributor works on exactly one side, or
2. the web front-end gains its own release cadence/deployment, or
3. the parity oracle is retired (the web `lib/db` stops being the reference).

A real split then needs, at minimum: versioned fixture artifacts with a
compatibility handshake, a schema-version negotiation, an exported-translations
artifact, per-repo CI, and a migration for the shared history. Price it against
this list, not against tidiness.

## The long-run path (added same day)

The staged separation plan — published platform mirrors → versioned FinchCore →
full multi-repo, each with triggers, mechanics, migration order and priced
costs — is detailed in `2026-08-08-long-run-platform-separation.md`. This
decision governs *now*; that doc governs *when the triggers fire*.
