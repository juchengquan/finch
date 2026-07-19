# Tag merge — design

**Date:** 2026-07-19
**Status:** approved (brainstormed with user)
**Scope:** iOS/macOS app only (`ios/`). Native-ahead of the web — the web engine
and the parity fixtures are untouched, exactly like the existing category merge.

## Problem

The Settings → Tags page (#520) mirrors the Categories page but deliberately
left out **merge** ("tags are flat/color-only"). Yet tags accumulate duplicates
and near-duplicates ("food" / "Food" / "eating-out") more than almost anything
else — they're free-form and multi-select — so consolidation is the natural
cleanup tool, and Categories already offers it. This adds the same merge UX to
tags.

## Decision

Add a tag merge that mirrors the category merge in both the engine and the UI:
a single-tag merge (pick a target, choose which name survives) and a
multi-select "combine several at once" mode. Merge is **iOS-only**, the same as
`mergeCategory` / `mergeCategories` (neither exists in the web engine), so there
are **no `frontend/` changes and no parity-fixture impact**.

Merge is orthogonal to the hierarchy/icons/kind that #520 excluded — it applies
cleanly to flat, color-only tags.

## The tag-specific wrinkle (why this isn't a copy-paste of category merge)

A category is single-valued per posting leg, so category merge is a blind
repoint (`UPDATE postings SET category_id = target WHERE category_id = source`).
Tags are **many-to-many** via `entry_tags (entry_id, tag_id)` — a single
transaction can carry both the source and the target tag. Merging must therefore
**dedup**: a transaction that already has both must end with the target **once**,
never a duplicate join row (the table's `PRIMARY KEY (entry_id, tag_id)` forbids
duplicates anyway). The composite-PK `INSERT OR IGNORE` handles this in one
statement.

## Changes

### 1. Engine — `FinchCore/Sources/FinchCore/Store/Domain/Tags.swift`

Add two handlers mirroring `Categories.merge` / `Categories.mergeMany`, plus
`.mergeTag` / `.mergeTags` cases in
`FinchCore/Sources/FinchCore/Store/ActionName.swift` and their entries in the
`Tags.handlers` map.

**Args**
- `mergeTag`: `{ sourceId: String, targetId: String }`
- `mergeTags`: `{ sourceIds: [String], targetId: String }`

**`validateMerge(source, target)`** (read-only; throws on failure):
- `source == target` → `I18nError("error.tag.mergeSelf", …, "Cannot merge a tag into itself")`.
- Either id missing from `tags` → `I18nError("error.notFound.tag", …, "Tag does not exist")`.
- No kind or hierarchy checks (tags are flat).

**`mergeOne(source, target)`** (repoint only; no validation, no delete; runs
inside the caller's transaction):
1. **Repoint the join, with dedup:**
   ```sql
   INSERT OR IGNORE INTO entry_tags (entry_id, tag_id)
   SELECT entry_id, :target FROM entry_tags WHERE tag_id = :source;
   ```
   Every entry tagged `source` now also carries `target`; rows where the entry
   already had `target` are ignored (composite-PK conflict), so no duplicates.
2. **Repoint rule actions:** any rule whose `actions` JSON references `source` in
   an add-tag / remove-tag action is rewritten to `target`, de-duplicating so the
   same action list never lists `target` twice. (Mirrors how category merge
   rewrites `budgets.category_ids` JSON.) Rules are read via
   `SELECT id, actions FROM rules WHERE actions LIKE '%<source>%'`, parsed,
   rewritten, and written back with `updated_at = datetime('now')`. A row whose
   JSON doesn't actually contain the id (LIKE false-positive) is skipped.
3. The **source join rows are left** to the delete step — deleting the source tag
   cascades them away (`entry_tags.tag_id … ON DELETE CASCADE`).

**`mergeTag`**: `validateMerge` → `mergeOne` → `DELETE FROM tags WHERE id = source`.

**`mergeTags`**: reject empty `sourceIds`
(`I18nError("error.invalidArgs", …, "mergeTags requires at least one source")`);
`validateMerge` **every** source up front (so one bad id aborts the whole set
with nothing merged); then `mergeOne` each; then delete each source. All in the
single transaction `Apply` already wraps.

### 2. UI — `FinchApp/Sources/FinchApp/PowerTools/TagsView.swift`

Mirror `CategoriesView`'s merge, dropping the tree/kind-specific parts:

- **State:** `mergingFrom: TagRow?` (→ target-picker sheet), `pendingMerge`,
  `mergeChoice` (→ keep-which-name alert), `isSelecting` (⋯ → Merge mode),
  `selected: Set<String>`, `mergeManySurvivorChoice: [TagRow]?`. A private
  `MergePair { a: TagRow; b: TagRow }`.
- **Single merge:** each row's swipe / context menu gains **"Merge…"**
  (`arrow.triangle.merge`) → a target-picker sheet listing the other tags (each a
  `TagSwatch` + name) → choosing one stages `pendingMerge`, promoted on dismiss to
  the **"Keep which name after merge?"** alert with `Keep "A"` / `Keep "B"` →
  dispatches `mergeTag(source:, target:)`. Survivor = the kept tag (its own name
  **and** color; the other is removed).
- **Multi-select:** a ⋯ menu (new — TagsView currently has only a `+`) with
  **"Merge"** enters `isSelecting`; rows show tick circles; a toolbar
  **"Merge (N)"** (enabled at ≥2) opens the keep-which-name dialog listing the
  ticked tags → dispatches `mergeTags(sourceIds:, targetId:)`.
- **Impact copy:** reuse the Categories `mergeImpactMessage` shape — "Combining
  moves the tag on N transactions", where N = distinct transactions touched, from
  `Selectors.tagTxCounts(store.txns, store.activeLedgerId)`.
- All dispatches go through `store.apply`; errors via the existing `errorAlert`.

### Non-changes / non-goals (explicit)

- **Web parity:** none. `mergeTag` / `mergeTags` are native-only actions (like
  `mergeCategory` / `mergeCategories`); the web engine and `WRITE_SEQUENCE`
  parity fixtures are untouched.
- **No color merge.** The survivor keeps its own color; no blending or prompt.
- **Saved-search tag filters** (per-device `UserDefaults`, not the DB) are not
  repointed. A merged-away id lingering in a saved filter simply matches nothing —
  harmless; documented, not fixed here.
- **Rule *conditions* on a tag id** (a rule that *matches on* a tag via `has` /
  `has_any` / `has_all`) are **not** repointed — only rule *actions* (`add_tag` /
  `remove_tag`) are. A rule whose condition tests a merged-away tag quietly stops
  matching it; this is non-corrupting (the merged transactions still carry the
  target tag) and the same harmless-stale-id class as saved-search filters. It
  also mirrors category merge, which repoints no rules at all, so a
  `category_id` *condition* goes equally stale. A future follow-up may repoint
  conditions for **both** tags and categories together.
- **Scheduled templates** carry no tag ids (verified — no tag column), so nothing
  to repoint there.
- No reorder, icons, kind, or hierarchy (tags remain flat/color-only, per #520).

## Testing

**FinchCore unit tests** (`FinchCore/Tests/FinchCoreTests/`, e.g. `ApplyTests` or
a new `TagMergeTests`):
- `mergeTag` repoints `entry_tags` from source to target and **deletes** the
  source tag.
- **Dedup:** a transaction tagged with **both** source and target ends with the
  target exactly once (one `entry_tags` row for that entry+target, none for
  source) — no PK violation.
- A rule whose `actions` add the source tag is rewritten to add the target
  (and not twice if it already added target).
- `mergeTags` combines several sources into one target in a single call; all
  sources deleted.
- Validation: `mergeTag` into itself throws; a missing source/target throws;
  `mergeTags` with an empty `sourceIds` throws; one invalid source in a
  `mergeTags` batch aborts the whole batch (nothing merged/deleted).

**Builds:** `xcodebuild` FinchApp (iOS Simulator) **and** FinchMac.

**Manual checklist (PR body):**
1. Tags page → swipe a tag → Merge… → pick a target → keep either name → the
   source tag is gone and its transactions now show the target tag.
2. A transaction that had both tags shows the target once (no duplicate).
3. ⋯ → Merge → tick 3 tags → Merge (3) → pick survivor → all combined.
4. Merge (N) is disabled below 2 ticked.
5. macOS: single + multi-select merge both work.
