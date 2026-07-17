# Group color — progress
Worktree: /tmp/finch-gc  Branch: feat/ios-group-color (stacked on #481)
- Task 1: web engine (schema+migration+queries) — pending
- Task 2: iOS engine (schema+migration+domain+tests) — pending
- Task 3: iOS UI (AddGroupSheet + dots) — pending
- Task 4: verify — pending (controller)
- Task 1: DONE (5af3264; 556 tests+typecheck; SCHEMA_VERSION bumped).
- Task 2: DONE (5f957aa; 271/271; import path already migrates staged DB).
- Task 3: DONE (84d53ca; verbatim; builds+12/12).
- Task 4: VERIFIED — upgrade migration on ios-finch2 (pre: no color/06-14 → post: color on both tables/07-17, data intact); Essentials dot renders (screenshot); pack path covered by loadPack staged-migrate + tolerance test.
