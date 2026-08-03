#!/usr/bin/env bash
# Run the CI iOS job locally, before pushing.
#
# WHY THIS EXISTS — the non-obvious part:
# CI triggers on `pull_request`, which builds the MERGE COMMIT (your branch
# merged into the base), not your branch. A branch that is behind the base
# therefore passes locally and fails in CI on code it does not own. Step 0
# refuses to run when you are behind, because a green result from a stale
# branch is a false signal rather than a pass.
#
#   ios/scripts/ci-local.sh                          # FAST: the inner loop
#   ios/scripts/ci-local.sh --full                   # the pre-push gate (predicts CI)
#   ios/scripts/ci-local.sh --all                    # + the frontend job
#   ios/scripts/ci-local.sh --sim "iPhone 17 Pro"    # pin the simulator
#   FINCH_CI_PLATFORMS=1 ios/scripts/ci-local.sh     # make macOS + watchOS gate again
#
# TWO MODES, and the difference matters:
#
#   FAST (default) answers "did I break something obvious" in the inner loop. It
#   runs every check that costs seconds and the one build that catches most
#   breakage, on a WARM per-worktree DerivedData. It SKIPS the UI tests, the
#   duplicated FinchCoreTests, and the parked platform builds unless your diff
#   touches them. A green fast run is NOT a prediction of CI, and the summary
#   says so — it lists what it skipped and tells you to run --full.
#
#   --full is the gate this script was written to be: everything, on a COLD
#   mktemp DerivedData, so a stale build product cannot manufacture a pass. Run
#   it before you push.
#
# The split exists because the two jobs have opposite priorities. The inner loop
# wants speed and tolerates a stale-build risk; the pre-push gate must not lie,
# and warm DerivedData is exactly how it would (a build phase added by xcodegen
# never re-ran against an already-built app, and three tests failed against a
# stale DerivedData that passed clean — both real, both this repo).
#
# macOS and watchOS are PARKED: still built and reported here, but a failure is a
# warning, not a failure — matching CI, where both run on the merge commit rather
# than on pull requests.
#
# Ordering is fail-fast rather than CI's order: the i18n guards cost seconds and
# catch the drift behind most recent CI failures; the Xcode builds cost minutes.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="${CI_LOCAL_BASE:-origin/feat/frontend}"
RUN_ALL=0
FULL=0
SIM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) RUN_ALL=1 ;;
    --full) FULL=1 ;;
    --sim) SIM="${2:-}"; shift ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
MODE_LABEL=$([ "$FULL" = "1" ] && echo "full (pre-push gate)" || echo "fast (inner loop)")
SKIPPED=()
skipped() { SKIPPED+=("$1"); }

: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

# --- run-scoped scratch ------------------------------------------------------
# Every path this script writes is unique to the run: the DerivedData, the export
# directory and all the logs.
#
# These were fixed /tmp paths, shared by every worktree on the machine. Two
# sessions running this script at once collided three ways: concurrent xcodebuilds
# fought over the shared DerivedData's build.db ("database is locked", failing legs
# that had nothing wrong with them), the logs each step greps for its verdict were
# overwritten by the other run, and — the one that actually misled someone — a
# failed export left another branch's xliff behind for the i18n guard to parse.
#
# The cost is honest: a fresh DerivedData means every run is a COLD build. Set
# FINCH_CI_DERIVED_DATA to a path of your own to keep it warm across runs — use a
# per-worktree path, never one shared with another checkout.
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/finch-ci.XXXXXX")"
# FAST keeps DerivedData warm PER WORKTREE — `ios/DerivedData/` is already in
# ios/.gitignore, so this needs no new ignore rule and it is removed along with
# the worktree. Per-worktree, never shared, so it cannot reproduce the build.db
# collision that made warm DerivedData opt-in in the first place.
#
# --full stays mktemp-COLD. That is not an oversight: the gate exists to predict
# CI, and CI always builds clean, so a warm gate could pass on a product that
# does not match the source.
if [ "$FULL" = "1" ]; then
  DD="${FINCH_CI_DERIVED_DATA:-$RUN_DIR/dd}"
else
  DD="${FINCH_CI_DERIVED_DATA:-$REPO/ios/DerivedData/ci-local}"
fi
# Kept on failure so the full logs survive for inspection; the summary prints the
# path. Removed on success, and removed when it is empty (a step-0 bail writes
# nothing), so runs do not accumulate scratch directories.
cleanup() {
  # Release the machine lock FIRST — a queued run should start the moment this
  # one is done, not after the log tidy-up.
  [ "${LOCK_HELD:-0}" = "1" ] && rm -rf "$LOCK_DIR"
  if [ "${KEEP_RUN_DIR:-0}" = "1" ] && [ -n "$(ls -A "$RUN_DIR" 2>/dev/null)" ]; then
    return
  fi
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

# --- one run per machine -----------------------------------------------------
# Two of these at once do not take twice as long — they thrash. Measured on this
# machine mid-session: load average 28 on 12 cores with a second ci-local and two
# stray xcodebuilds running, which is roughly 6x oversubscribed. That contention,
# not the script's own work, is what makes a run "sometimes" slow.
#
# `mkdir` because macOS has no flock(1): the directory create is atomic, so the
# race is decided by the kernel rather than by a check-then-write. A lock whose
# owner is gone is taken over rather than waited on forever — a Ctrl-C'd run
# would otherwise wedge every later one.
LOCK_DIR="${TMPDIR:-/tmp}/finch-ci.lock"
acquire_lock() {
  local waited=0 owner
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    owner=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -z "$owner" ] || ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$LOCK_DIR"; continue          # stale: owner died
    fi
    if [ "$waited" = "0" ]; then
      printf '\033[33m> waiting: ci-local is already running\033[0m\n'
      printf '  started %s in %s (pid %s)\n' \
        "$(cat "$LOCK_DIR/started" 2>/dev/null || echo '?')" \
        "$(cat "$LOCK_DIR/tree" 2>/dev/null || echo '?')" "$owner"
      printf '  running both would thrash the machine; this run starts when that one ends.\n'
      printf '  Ctrl-C to bail.\n'
    fi
    sleep 5; waited=$((waited + 5))
  done
  LOCK_HELD=1
  printf '%s' "$$" > "$LOCK_DIR/pid"
  date '+%H:%M' > "$LOCK_DIR/started"
  printf '%s' "$REPO" > "$LOCK_DIR/tree"
  # `if`, not `[ … ] && printf`: the latter is the function's last statement, so
  # a run that never waited would return 1 and any future `acquire_lock || die`
  # would fire on the success path.
  if [ "$waited" -gt 0 ]; then
    printf '\033[33m  waited %ds for the machine\033[0m\n' "$waited"
  fi
}
acquire_lock

FAILED=()
# Per-step wall clock. The script had none, so "it feels slow" could never be
# turned into "this step is slow" — the summary prints the split.
STEP_LOG=()
_step_name=""; _step_t0=0
_record_step() {
  [ -z "$_step_name" ] && return
  STEP_LOG+=("$(printf '%4ds  %s' "$((SECONDS - _step_t0))" "$_step_name")")
}
step() { _record_step; _step_name="$1"; _step_t0=$SECONDS; printf '\n\033[1m> %s\033[0m\n' "$1"; }
pass() { printf '\033[32m  ok  %s\033[0m\n' "$1"; }
fail() { printf '\033[31m  FAIL  %s\033[0m\n' "$1"; FAILED+=("$1"); KEEP_RUN_DIR=1; }

printf '\033[1mmode: %s\033[0m\n' "$MODE_LABEL"

# --- 0. staleness gate -------------------------------------------------------
step "Base check ($BASE)"
git -C "$REPO" fetch -q origin "${BASE#origin/}" 2>/dev/null || true
if ! git -C "$REPO" rev-parse --verify -q "$BASE" >/dev/null; then
  echo "  ! $BASE not found - skipping (set CI_LOCAL_BASE to override)"
elif git -C "$REPO" merge-base --is-ancestor "$BASE" HEAD; then
  pass "up to date with $BASE"
else
  behind=$(git -C "$REPO" rev-list --count "HEAD..$BASE")
  fail "branch is $behind commit(s) behind $BASE"
  echo ""
  echo "  CI builds your branch MERGED INTO $BASE, so it compiles code this run"
  echo "  never sees. Rebase first, or these results are a false green:"
  echo ""
  echo "      git rebase $BASE"
  echo ""
  exit 1
fi

cd "$REPO/ios" || exit 1

# --- 1. i18n guard 1: catalog reproducible (seconds, no Xcode) ---------------
step "i18n - catalog is reproducible from its inputs"
if bun run scripts/build-xcstrings.ts >/dev/null 2>&1 \
   && git -C "$REPO" diff --quiet -- ios/FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings; then
  pass "catalog matches its inputs"
else
  fail "Localizable.xcstrings does not match a fresh build"
  echo "    It is GENERATED. Put translations in ios/scripts/zh-manual.json, then:"
  echo "      bun run ios/scripts/build-xcstrings.ts"
fi

# --- 2. FinchCore + ParityTests ---------------------------------------------
step "FinchCore unit tests + ParityTests (swift test)"
if swift test >"$RUN_DIR/swift.log" 2>&1; then
  pass "$(grep -oE 'Executed [0-9]+ tests' "$RUN_DIR/swift.log" | tail -1)"
else
  fail "swift test"
  grep -E "error:|failed" "$RUN_DIR/swift.log" | head -5
fi

# --- 3. project + simulator --------------------------------------------------
step "Generate the Xcode project"
# Two specs, two projects — FinchMac is deliberately NOT in FinchApp.xcodeproj
# (see ios/project-mac.yml for why).
if xcodegen generate --spec project.yml,project-mac.yml >/dev/null 2>&1; then
  pass "FinchApp.xcodeproj + FinchMac.xcodeproj"
else
  fail "xcodegen generate"
fi

# --- which simulator ---------------------------------------------------------
# This used to be `grep -oE 'iPhone [0-9]...' | head -1`, i.e. "the first stock
# device in the list" — which is SHARED. Every session on this machine keeps its
# own sim (ios-finch-splits, ios-finch-wren, ios-finch-x06 …) precisely so runs do
# not collide, and the auto-pick quietly ignored all of them and grabbed the same
# `iPhone 17 Pro` for everyone. `xcodebuild test` installs the app and the demo
# seed on whatever it is handed, so that is someone else's device state.
#
# It also silently ignored SIM_NAME. A session invoking
# `SIM_NAME=ios-finch-splits ./scripts/ci-local.sh` got the stock device instead
# and had no way to tell — the env var was never read, and the old line printed a
# name that looked deliberate. Both spellings are honoured now.
#
# Resolution order, first hit wins:
#   1. --sim
#   2. $FINCH_CI_SIM / $SIM_NAME
#   3. an existing sim named for this worktree
#   4. create that sim
# Never a device someone else might be holding.
if [ -z "$SIM" ]; then
  SIM="${FINCH_CI_SIM:-${SIM_NAME:-}}"
fi
if [ -z "$SIM" ]; then
  # `/tmp/finch-wren-hdr` -> `ios-finch-wren-hdr`, matching the convention already
  # in use by hand. The main checkout gets a name of its own rather than sharing.
  SIM="ios-$(basename "$REPO")"
  if ! xcrun simctl list devices | grep -q "$SIM ("; then
    step "Create this worktree's simulator"
    # A PREFERENCE LIST, not "the last match". Grepping for any iPhone and taking
    # the tail picked iPhone-11 here — a 414pt-wide device, when ios/CLAUDE.md
    # measures this app's layout rules at 390pt and 402pt. The row-height
    # thresholds that decide swipe-action styling are width-sensitive, so the
    # device model is a correctness input to the UI tests, not a detail.
    # Matched up to the CLOSING PAREN, because simctl prints
    #   iPhone 17 Pro (com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
    # An `$` anchor matches nothing here, and an unanchored `iPhone-17` would
    # happily select `iPhone-17-Pro-Max`. The paren is what makes it exact.
    DEV_TYPE=""
    for want in iPhone-17-Pro iPhone-17 iPhone-16-Pro iPhone-16 iPhone-15-Pro iPhone-15; do
      DEV_TYPE=$(xcrun simctl list devicetypes \
                 | grep -oE "com\.apple\.CoreSimulator\.SimDeviceType\.${want}\)" \
                 | head -1 | tr -d ')')
      [ -n "$DEV_TYPE" ] && break
    done
    RUNTIME=$(xcrun simctl list runtimes | grep -oE 'com\.apple[^ ]*iOS[^ ]*' | tail -1)
    if [ -n "$DEV_TYPE" ] && [ -n "$RUNTIME" ] \
       && xcrun simctl create "$SIM" "$DEV_TYPE" "$RUNTIME" >/dev/null 2>&1; then
      pass "created $SIM"
    else
      # Falling back to a shared device is what this block exists to avoid, so
      # stop instead: a wrong device silently rewrites another session's data.
      fail "could not create a simulator named $SIM — pass --sim explicitly"
      echo "      device type: ${DEV_TYPE:-<none found>}"
      echo "      runtime:     ${RUNTIME:-<none found>}"
      exit 1
    fi
  fi
fi
echo "  simulator: $SIM"

# --- 4. FinchApp build + test ------------------------------------------------
# The three retry flags MATCH CI — see the long comment on that step in
# .github/workflows/ci.yml for the flake data behind them and for why
# -test-repetition-relaunch-enabled is load-bearing rather than a tuning knob.
# They are here so this script keeps predicting CI's verdict: without them a
# UI-test flake fails locally and passes in CI, which is the false signal this
# script exists to prevent. A green run costs nothing; only failures are re-run.
# FAST narrows the test action to FinchAppTests. The scheme also runs
# FinchAppUITests and FinchCoreTests:
#
#   - the 33 UI tests are simulator automation, the slowest tests here and the
#     reason the retry flags exist — one flake costs three app launches;
#   - FinchCoreTests' 434 methods ALREADY ran in step 2 via `swift test`. The
#     scheme runs the same sources again as an iOS bundle, so the only thing
#     lost is executing the engine on the simulator rather than on macOS, and
#     FinchCore is pure Swift with no UIKit.
#
# Both come back under --full, which is the run that has to match CI.
# Expanded at the call site as ${TEST_SCOPE[@]+"${TEST_SCOPE[@]}"} — macOS ships
# bash 3.2, where "${arr[@]}" on an EMPTY array under `set -u` is an "unbound
# variable" error. Plain "${TEST_SCOPE[@]}" would therefore abort --full, the one
# mode that must never be the broken one.
TEST_SCOPE=()
if [ "$FULL" != "1" ]; then
  TEST_SCOPE=(-only-testing:FinchAppTests)
  skipped "FinchAppUITests (33 UI tests)"
  skipped "FinchCoreTests on iOS (434 methods; swift test already ran them)"
fi
step "Build + test FinchApp"
if xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
     -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DD" \
     ${TEST_SCOPE[@]+"${TEST_SCOPE[@]}"} \
     -retry-tests-on-failure -test-iterations 3 \
     -test-repetition-relaunch-enabled YES \
     -skipPackagePluginValidation -skipMacroValidation \
     COMPILER_INDEX_STORE_ENABLE=NO >"$RUN_DIR/app.log" 2>&1; then
  pass "$(grep -oE 'Executed [0-9]+ tests' "$RUN_DIR/app.log" | tail -1)"
else
  fail "FinchApp build/test"
  grep -E "error:|failed" "$RUN_DIR/app.log" | head -8
fi

# --- 5. i18n guard 2: extracted keys current ---------------------------------
# Compares the KEY SET (what matters is whether a string is missing, not
# byte-identical formatting) and keeps the fresh extraction in a run-scoped temp
# dir, so a failure never mutates your working tree.
#
# The export goes to a RUN-SCOPED directory, not a fixed one. It used to go to
# /tmp/finch-loc, which every worktree on the machine shared: when two sessions
# ran this script at once, one export died on the DerivedData lock and
# xliff-keys.ts parsed the xliff the other branch had left there, reporting keys
# as missing that were present. `mktemp -d` makes that collision impossible.
step "i18n - UIKit strings are localized"
if python3 "$REPO/ios/scripts/uikit-strings-guard.py"; then
  pass "no bare UIKit strings"
else
  fail "UIKit strings bypass extraction"
fi

step "i18n - extracted keys are current"
LOC_DIR="$RUN_DIR/loc"
KEYS_FRESH="$RUN_DIR/keys-fresh.json"
if xcodebuild -exportLocalizations -project FinchApp.xcodeproj -scheme FinchApp \
     -localizationPath "$LOC_DIR" -exportLanguage zh-Hans \
     -derivedDataPath "$DD" -quiet \
     -skipPackagePluginValidation -skipMacroValidation \
     COMPILER_INDEX_STORE_ENABLE=NO >"$RUN_DIR/loc.log" 2>&1 \
   && bun run scripts/xliff-keys.ts "$LOC_DIR" > "$KEYS_FRESH" 2>>"$RUN_DIR/loc.log"; then
  if python3 "$REPO/ios/scripts/ci-local-keydiff.py" "$KEYS_FRESH"; then
    pass "key set matches"
  else
    fail "extracted-keys.json out of date"
  fi
else
  fail "exportLocalizations"
  # `xliff-keys:` catches this script's own diagnostics (stale/missing xliff),
  # which do not say "error:" and were otherwise swallowed.
  grep -E "error:|^xliff-keys:|^  " "$RUN_DIR/loc.log" | head -8
fi

# --- 6. the other platforms (PARKED: built and reported, but NOT gating) ------
# macOS and watchOS are not under active work, and CI matches this: both build on
# the merge commit rather than on pull requests. They still build here — a break is
# worth knowing about before you push — but neither fails this script.
#
# `FINCH_CI_PLATFORMS=1` makes them gate again. To un-park permanently: drop the
# variable, call `fail` instead of `warn`, and delete the `if:` lines from the two
# steps in ci.yml.
#
# macOS only became parkable once FinchMac moved into its own project: while it was
# a target in FinchApp.xcodeproj, `xcodebuild -exportLocalizations` compiled it on
# every run whatever scheme/target you gave it, so a macOS break failed the i18n
# step regardless. See ios/project-mac.yml.
WARNED=()
warn() { printf '\033[33m  warn  %s\033[0m\n' "$1"; WARNED+=("$1"); KEEP_RUN_DIR=1; }
if [ "${FINCH_CI_PLATFORMS:-0}" = "1" ]; then
  nongating() { fail "$1"; }
else
  nongating() { warn "$1 — not gating (parked; FINCH_CI_PLATFORMS=1 to gate)"; }
fi

# FAST builds a parked platform only when the diff can actually break it. Each is
# a full compile for a platform nothing else in this run covers, spent to produce
# a warning you cannot fail on — but skipping them unconditionally would undo the
# rule in ios/CLAUDE.md: build FinchMac when you touch FinchShared or
# FinchAppSwiftUI, because a macOS-only break passes the iOS build
# (`.topBarTrailing` does not exist on macOS).
#
# Sources come from the project specs, so this list is checkable rather than
# remembered: FinchMac compiles FinchShared + FinchAppSwiftUI + Shared and depends
# on FinchCore; FinchWatch compiles FinchWatch + Shared and deliberately carries
# NO FinchCore (the watch payload is Foundation-only).
CHANGED="$(git -C "$REPO" diff --name-only "$BASE"...HEAD 2>/dev/null; git -C "$REPO" diff --name-only HEAD 2>/dev/null)"
touches() { printf '%s\n' "$CHANGED" | grep -qE "$1"; }
want_platform() {   # $1 = human name, $2 = path regex
  [ "$FULL" = "1" ] && return 0
  if touches "$2"; then return 0; fi
  skipped "$1 (diff touches none of its sources)"
  return 1
}

if want_platform "FinchMac build" \
   '^ios/(FinchApp/Sources/(FinchShared|FinchAppSwiftUI)|Shared|FinchCore)/|^ios/project-mac\.yml$'; then
step "Build FinchMac (macOS)"
if xcodebuild build -project FinchMac.xcodeproj -scheme FinchMac -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DD" -quiet \
     -skipPackagePluginValidation -skipMacroValidation \
     COMPILER_INDEX_STORE_ENABLE=NO >"$RUN_DIR/mac.log" 2>&1; then
  pass "FinchMac"
else
  nongating "FinchMac"; grep -E "error:" "$RUN_DIR/mac.log" | head -5
fi
fi

if want_platform "FinchWatch build" '^ios/(FinchWatch|Shared)/|^ios/project\.yml$'; then
step "Build FinchWatch (watchOS)"
if xcodebuild build -project FinchApp.xcodeproj -scheme FinchWatch \
     -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO \
     -derivedDataPath "$DD" -quiet \
     -skipPackagePluginValidation -skipMacroValidation \
     COMPILER_INDEX_STORE_ENABLE=NO >"$RUN_DIR/watch.log" 2>&1; then
  pass "FinchWatch"
else
  nongating "FinchWatch"; grep -E "error:" "$RUN_DIR/watch.log" | head -5
fi
fi

# --- 7. frontend job (opt-in) ------------------------------------------------
if [ "$RUN_ALL" = "1" ]; then
  cd "$REPO/frontend" || exit 1
  for t in typecheck lint check:naming test build; do
    step "frontend: bun run $t"
    if bun run "$t" >"$RUN_DIR/frontend.log" 2>&1; then
      pass "$t"
    else
      fail "frontend $t"; tail -8 "$RUN_DIR/frontend.log"
    fi
  done
fi

# --- summary -----------------------------------------------------------------
_record_step
printf '\n\033[1m-- summary --\033[0m\n'
# Guarded for the same bash 3.2 reason as TEST_SCOPE above.
if [ ${#STEP_LOG[@]} -gt 0 ]; then printf '%s\n' "${STEP_LOG[@]}"; fi
printf '\033[1m%4ds  total (%s)\033[0m\n' "$SECONDS" "$MODE_LABEL"

# The FinchApp build/test step can re-serialize the string catalogs in place
# (Xcode's formatting, zero content change) AFTER the reproducibility guard
# already passed. Committing that churn makes the NEXT run's guard fail — a
# blanket `git add ios` has shipped it before. Warn while it's still cheap.
if ! git -C "$REPO" diff --quiet -- 'ios/**/*.xcstrings' 2>/dev/null; then
  printf '\033[33mNOTE: xcodebuild churned the .xcstrings catalogs during this run (formatting only).\n'
  printf 'Discard before committing:  git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/*.xcstrings"\033[0m\n'
fi

# Non-gating warnings are printed whether or not anything failed — a parked
# platform breaking is worth seeing even on an otherwise green run.
if [ ${#WARNED[@]} -gt 0 ]; then
  printf '\033[33m%d non-gating warning(s):\033[0m\n' "${#WARNED[@]}"
  printf '  ! %s\n' "${WARNED[@]}"
  printf '\nfull logs: %s\n' "$RUN_DIR"
fi

# A fast green is NOT a prediction of CI, and the single most likely way this
# change does harm is someone reading it as one. Say what was skipped, every
# time, and say it on success too — a green run is exactly when nobody reads.
if [ ${#SKIPPED[@]} -gt 0 ]; then
  printf '\n\033[33mFAST MODE — this did NOT run:\033[0m\n'
  printf '  - %s\n' "${SKIPPED[@]}"
  printf '\033[33mRun before pushing:  ios/scripts/ci-local.sh --full\033[0m\n'
fi

if [ ${#FAILED[@]} -eq 0 ]; then
  if [ "$FULL" = "1" ]; then
    printf '\033[32mall checks passed\033[0m\n'
  else
    printf '\033[32mfast checks passed\033[0m\n'
  fi
  exit 0
fi
printf '\033[31m%d failed:\033[0m\n' "${#FAILED[@]}"
printf '  - %s\n' "${FAILED[@]}"
# The excerpts above are the first few matching lines; the full logs are what you
# actually need when a build fails. They are kept ONLY on failure (see cleanup).
printf '\nfull logs: %s\n' "$RUN_DIR"
exit 1
