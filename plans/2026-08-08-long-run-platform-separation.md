# Long-run platform separation — the staged path (2026-08-08)

Companion to `2026-08-08-repo-structure-decision.md`. That doc is the **why not
now**; this one is the **how, when it's time**. Three stages, each independently
useful, each with its own trigger, none of which weakens the parity system. The
stages are ordered by cost and are strictly optional — skipping straight to a
later stage without its trigger buys process for no product.

## The facts every stage is built on (measured 2026-08-08)

**The dependency graph is a one-way DAG.** `frontend/` consumes nothing from
`ios/` (grep-verified: zero references outside the fixture-export destination
path). Everything flows downstream:

```
frontend (oracle: schema, engine reference, fixtures, zh translations)
    │
    ▼
ios/FinchCore (Swift engine — parity-gated mirror of frontend/lib/db)
    │
    ▼
FinchApp · FinchMac · FinchWatch · widget · share extension
```

One-way means downstream can be separated without upstream ever knowing, and
upstream (now UI-frozen) moves slowly — which keeps every artifact-lag window
that separation introduces naturally small.

**The separable seams, and the one that is not:**

- `frontend | ios` — the clean seam (this DAG).
- `FinchCore | app layer` — clean: `ios/Package.swift` references zero
  `FinchApp/` paths; FinchCore is already an extractable SwiftPM package.
- `iOS | macOS` — **NOT a seam and never will be at source level.**
  `FinchMac.xcodeproj` compiles the *same* `FinchAppSwiftUI/` sources as the
  iOS app; the split is of the build, not the code (see `ios/project-mac.yml`).
  "Per-platform branches" therefore bottoms out at *web | apple*.

**Repo weight is not an argument.** `frontend/` 3.4G and `ios/` 5.3G on disk
are node_modules, DerivedData and `.build` — untracked build artifacts. The
tracked tree is small; sparse-checkout (root `CLAUDE.md`) already gives a
one-half working tree.

---

## Stage 1 — platform branches as PUBLISHED ARTIFACTS

**What it is:** read-only `mirror/web` and `mirror/apple` branches, regenerated
by CI after every merge, each containing ONLY that platform's tree at its root.
The monorepo stays the only working surface; the mirrors are build products —
the standard way large monorepos ship per-component views.

**Trigger:** wanting clean single-platform trees to browse, clone, or hand to
someone. No architectural precondition; can be built any time.

**What a consumer sees:**

```bash
git clone --branch mirror/apple --single-branch <repo-url> finch-apple
# → a tree whose root is Package.swift, FinchApp/, FinchCore/, scripts/ …
```

**Mechanics.** `git subtree split` is deterministic and history-preserving:

```yaml
  # .github/workflows/mirrors.yml — separate workflow, NOT ci.yml:
  # ci.yml runs with `contents: read`; this one needs write. Keeping the
  # write permission in its own file keeps the blast radius obvious.
  name: Platform mirrors
  on:
    push:
      branches: [feat/frontend, main]
  permissions:
    contents: write
  concurrency:
    group: mirrors-${{ github.ref }}   # serialize; latest wins is fine here
  jobs:
    publish:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
          with: { fetch-depth: 0 }     # subtree split needs full history
        - run: |
            git subtree split --prefix=frontend -b mirror/web
            git subtree split --prefix=ios      -b mirror/apple
            git push -f origin mirror/web mirror/apple
```

**Details that matter:**

- **Force-push semantics.** Mirror SHAs are rewrites; a rebase-merge upstream
  reshuffles them. Consumers must treat mirrors as read-only snapshots —
  `git pull` may need `--rebase` or a re-clone. Say so in each mirror's README
  (add `frontend/README.md` / `ios/README.md` headers: "this tree is also
  published read-only as `mirror/…`; PRs go to the monorepo").
- **No PRs against mirrors.** Branch protection on `mirror/*`: block pushes
  except the Action; or simply document it — a PR against a force-pushed
  branch dies on its own.
- **Runtime cost:** `subtree split` is O(history) per run — ubuntu-minutes on
  this repo's ~thousands of commits, in a post-merge job nothing waits on.
- **Docs stay with their code** (this resolves the original "docs branch"
  idea): `plans/` is cross-cutting and stays monorepo-only; `ios/docs/`,
  `frontend/*.md` travel inside their mirrors automatically.
- **Rollback:** delete the workflow and the two branches. Nothing depends on
  them.

**What it does NOT give:** independent development. A mirror is a view.
Anyone committing to a mirror has created a fork that the next force-push
orphans.

---

## Stage 2 — FinchCore becomes a VERSIONED PACKAGE

**What it is:** the engine (+ its tests + the parity harness) moves to its own
repo with semver tags; the apps consume it as an ordinary SwiftPM dependency.
This is the first stage with real recurring cost, and the first that changes
how a cross-cutting feature ships.

**Triggers (any one):** a second consumer of FinchCore (another app, a CLI, a
server); a second regular contributor working only on the engine or only on the
apps; or engine release discipline becoming desirable for its own sake
(auditable engine versions on device builds).

**Target topology:**

```
finch (monorepo)                     finch-core (new repo)
├── frontend/   ← oracle, publisher  ├── Package.swift
├── ios/                             ├── Sources/FinchCore/
│   ├── FinchApp/  (app layer)       └── Tests/
│   └── Package.swift → depends on       ├── FinchCoreTests/
│       finch-core from: X.Y.Z           └── ParityTests/  ← consumes artifact
└── plans/
```

**The fixture contract (the heart of this stage).** Today the web writes
fixtures into the engine's tree at the same commit. Split, that becomes a
published artifact with a machine-checked handshake:

- On every merge touching `frontend/lib/db` or the fixture generator, a
  monorepo CI job runs `export-fixtures.ts` and publishes
  `parity-fixtures-<schema_version>.tar.gz` (a GitHub release asset or
  package) containing the fixture tree plus a manifest:

  ```json
  {
    "schema_version": "2026-07-23T00:00:00Z",
    "generated_from": "<monorepo commit sha>",
    "generator": "export-fixtures.ts",
    "fixture_streams": ["selectors", "audit", "projection", "writeparity", "currency"]
  }
  ```

- finch-core's CI fetches the artifact whose `schema_version` **equals its own
  `Schema.version`** and fails loudly when none exists. The today-only-a-comment
  pin ("Matches the web's SCHEMA_VERSION") becomes an enforced equality — the
  parity gates keep their teeth, with the lag window bounded by the frozen
  oracle's low change rate.

**The i18n seam.** `build-xcstrings.ts` reads `frontend/messages/*.json`. Two
options; take (a):

- (a) **Pipeline stays in the monorepo** (recommended): the catalog is an APP
  concern, not an engine concern — `scripts/` and the catalogs already live
  with the app layer, which stays in the monorepo next to `frontend/`. Nothing
  changes at this stage.
- (b) Messages become a published artifact too — only needed at Stage 3.

**Migration, ordered, each step reversible:**

1. `git filter-repo` (not subtree — keeps only core-relevant history) into
   `finch-core`; tag `v1.0.0` at parity with the tree copy.
2. **Dual-home transition:** monorepo's `ios/Package.swift` switches to the
   tagged dependency; the in-tree `FinchCore/` copy stays one release as a
   read-only reference with a tombstone README. Local development uses an
   Xcode workspace / `path:` override for edit-run cycles against a checkout
   of finch-core.
3. Delete the in-tree copy; `ci-local.sh` gains a step that clones/updates the
   pinned core version for `swift test` (or drops the engine tests locally and
   trusts core's own CI — decide by measured pain).
4. Fixture-publisher job lands in the monorepo; core CI flips from in-tree
   fixtures to artifact consumption. **Order matters: publisher before
   consumer.**

**The honest recurring cost, priced with a real example:** the ISO 4217 change
(2026-08-07) was one commit touching `frontend` + `FinchCore` + app layer.
Under Stage 2 it becomes: core PR (table + tests) → tag → monorepo PR (web
table + fixture publish + app wiring + version bump). Two PRs, one release, and
a fixture-artifact cycle — per cross-cutting change. That price is fine when
the triggers hold and obnoxious when they don't; hence the triggers.

**Rollback:** `git subtree add` core back into `ios/`, repoint
`Package.swift` at the path, retire the artifact jobs.

---

## Stage 3 — full multi-repo

**What it is:** `finch-web` (oracle + publisher), `finch-core` (engine),
`finch-apps` (all Apple targets). Docs follow their component; `plans/`
cross-cutting docs move to the repo whose feature they describe, or a slim
`finch-meta`.

**Triggers:** the decision doc's, verbatim — a second regular contributor on
exactly one side, an independent web release cadence, or oracle retirement.
Team boundaries are the only good reason for repo boundaries at this scale.

**Additional contracts beyond Stage 2:** messages artifact (i18n), a
schema-change protocol (web PR must state the new `SCHEMA_VERSION`; core
consumes behind a version gate; apps behind a core release), and a
cross-repo issue/PR convention replacing today's atomic commits entirely.

**What must survive every topology (non-negotiable invariants):**

1. The DAG stays one-way — web never grows a dependency on core or apps.
2. The parity gates never weaken below "machine-checked schema-version
   equality + full fixture replay" — a lag window is acceptable; silent drift
   is not.
3. iOS and macOS keep compiling the same view sources — no per-OS source fork.

---

## Choosing a stage (symptom → action)

| Symptom | Action |
|---|---|
| "I want to browse/clone/share just one platform" | Stage 1 (any time) |
| "The other half clutters my editor/checkout" | Already solved: sparse-checkout |
| "Engine needs its own consumers/versioning" | Stage 2 |
| "A second person owns one side" / web gets its own cadence | Stage 2 → 3 |
| "The repo feels big" with none of the above | No stage — revisit the pain |
