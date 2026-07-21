#!/usr/bin/env python3
"""Compare a fresh string extraction against the committed key set.

Used by ci-local.sh (and mirrors the CI guard). Compares the KEY SET rather than
file bytes: the property that matters is whether a UI string is missing from the
catalog — a formatting-only difference in the generated file is noise.

Exits 1 and NAMES the offending keys, because "N insertions" tells you something
drifted but not what, which is a round-trip you don't need.
"""
import json
import sys

FRESH = "/tmp/keys-fresh.json"
COMMITTED = "scripts/extracted-keys.json"

fresh = set(json.load(open(FRESH)))
committed = set(json.load(open(COMMITTED)))

missing = sorted(fresh - committed)   # in the app, absent from the catalog
stale = sorted(committed - fresh)     # in the catalog, gone from the app

if not missing and not stale:
    sys.exit(0)

for k in missing:
    print(f"  + {k!r}  (in the app, NOT in the catalog -> renders English)")
for k in stale:
    print(f"  - {k!r}  (in the catalog, no longer in the app)")
print("    Re-run the pipeline in the header of ios/scripts/build-xcstrings.ts,")
print("    then commit extracted-keys.json AND the rebuilt catalog.")
sys.exit(1)
