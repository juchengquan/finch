# Feed: multi-tag filter (Any / All)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** Upgrade the feed filter's single-tag picker to multi-select with an Any/All mode. Small engine change + filter-sheet UI.

## Problem

The feed filter (#286) supports a **single** tag (`ListOptions.tagId` / `TxFilter.tagId`
/ one `Picker`). Users can't filter by several tags at once.

## Design

### 1. Engine — `tagIds` + match mode

In `Models.swift`, replace `ListOptions.tagId: String?` with:

```swift
    public var tagIds: [String]?
    public var tagsMatchAll: Bool
```
(init: `tagIds: [String]? = nil, tagsMatchAll: Bool = false`, defaulting to **Any**.)
`tagId` is an iOS-only field (added in #286; not in the web parity fixtures), so
replacing it is safe.

In `Selectors.selectTransactions`, replace the single-tag line:

```swift
        if let tag = opts.tagId { out = out.filter { ($0.tags ?? []).contains(tag) } }
```
with:

```swift
        if let tags = opts.tagIds, !tags.isEmpty {
            let want = Set(tags)
            out = out.filter {
                let have = Set($0.tags ?? [])
                return opts.tagsMatchAll ? want.isSubset(of: have) : !want.isDisjoint(with: have)
            }
        }
```
**Any** (default) = transaction has *any* selected tag; **All** = has *every* selected tag.

### 2. `TxFilter` — multi-select state

In `TransactionFilterSheet.swift`, replace `var tagId: String? = nil` with:

```swift
    var tagIds: Set<String> = []
    var tagsMatchAll: Bool = false
```
`isActive`: replace `tagId != nil` with `!tagIds.isEmpty`.

### 3. Filter sheet — multi-select tags + Any/All toggle

Replace the single Tag `Picker` with a tag multi-select (when `!store.tags.isEmpty`):

```swift
                    if !store.tags.isEmpty {
                        // mirrors the Add/Edit tag chip rows
                        ForEach(store.tags) { tag in
                            Button {
                                if draft.tagIds.contains(tag.id) { draft.tagIds.remove(tag.id) }
                                else { draft.tagIds.insert(tag.id) }
                            } label: {
                                HStack {
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if draft.tagIds.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                        if draft.tagIds.count >= 2 {
                            Picker("Match", selection: $draft.tagsMatchAll) {
                                Text("Any tag").tag(false)
                                Text("All tags").tag(true)
                            }
                        }
                    }
```
(Placed where the single Tag picker was; the Status picker etc. follow unchanged.)

### 4. Feed — pass through

In `ActivityFeedView.filteredTxns()`, replace `tagId: filter.tagId` with:

```swift
            tagIds: filter.tagIds.isEmpty ? nil : Array(filter.tagIds),
            tagsMatchAll: filter.tagsMatchAll
```

## Out of scope
- Tag filtering anywhere other than the feed filter.
- Per-tag color in the filter rows (a separate small follow-up).

## Testing

**Engine (FinchCore):** migrate the #286 `SelectTransactionsTagTests` to `tagIds`:
- Any (default): `tagIds: ["t1","t2"]` returns txns with t1 **or** t2.
- All: `tagsMatchAll: true` returns only txns with **both**.
- Empty/`nil`: unchanged. `ParityTests` green (tagIds iOS-only).

**App (build + manual sim):** Filter → select 2 tags → feed shows Any-of; toggle **All tags** → narrows to both; Clear resets; combine with other filters.

## Notes
- The only `ListOptions.tagId` caller is the feed; `RulesManagerView`'s `tagId` is an
  unrelated rule-field and is untouched.
- PR targets `feat/frontend`.
