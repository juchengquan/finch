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
#   ios/scripts/ci-local.sh                          # the iOS job
#   ios/scripts/ci-local.sh --all                    # + the frontend job
#   ios/scripts/ci-local.sh --sim "iPhone 17 Pro"    # pin the simulator
#
# Ordering is fail-fast rather than CI's order: the i18n guards cost seconds and
# catch the drift behind most recent CI failures; the Xcode builds cost minutes.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="${CI_LOCAL_BASE:-origin/feat/frontend}"
RUN_ALL=0
SIM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) RUN_ALL=1 ;;
    --sim) SIM="${2:-}"; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

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
DD="${FINCH_CI_DERIVED_DATA:-$RUN_DIR/dd}"
# Kept on failure so the full logs survive for inspection; the summary prints the
# path. Removed on success, and removed when it is empty (a step-0 bail writes
# nothing), so runs do not accumulate scratch directories.
cleanup() {
  if [ "${KEEP_RUN_DIR:-0}" = "1" ] && [ -n "$(ls -A "$RUN_DIR" 2>/dev/null)" ]; then
    return
  fi
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

FAILED=()
step() { printf '\n\033[1m> %s\033[0m\n' "$1"; }
pass() { printf '\033[32m  ok  %s\033[0m\n' "$1"; }
fail() { printf '\033[31m  FAIL  %s\033[0m\n' "$1"; FAILED+=("$1"); KEEP_RUN_DIR=1; }

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
if xcodegen generate >/dev/null 2>&1; then pass "FinchApp.xcodeproj"; else fail "xcodegen generate"; fi

if [ -z "$SIM" ]; then
  SIM=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9][0-9A-Za-z ]*' | head -1 | xargs)
fi
echo "  simulator: ${SIM:-<none found>}"

# --- 4. FinchApp build + test ------------------------------------------------
step "Build + test FinchApp"
if xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
     -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DD" \
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

# --- 6. the other platforms --------------------------------------------------
step "Build FinchMac (macOS)"
if xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DD" -quiet \
     -skipPackagePluginValidation -skipMacroValidation \
     COMPILER_INDEX_STORE_ENABLE=NO >"$RUN_DIR/mac.log" 2>&1; then
  pass "FinchMac"
else
  fail "FinchMac"; grep -E "error:" "$RUN_DIR/mac.log" | head -5
fi

step "Build FinchWatch (watchOS)"
if xcodebuild build -project FinchApp.xcodeproj -scheme FinchWatch \
     -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO \
     -derivedDataPath "$DD" -quiet \
     -skipPackagePluginValidation -skipMacroValidation \
     COMPILER_INDEX_STORE_ENABLE=NO >"$RUN_DIR/watch.log" 2>&1; then
  pass "FinchWatch"
else
  fail "FinchWatch"; grep -E "error:" "$RUN_DIR/watch.log" | head -5
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
printf '\n\033[1m-- summary --\033[0m\n'

# The FinchApp build/test step can re-serialize the string catalogs in place
# (Xcode's formatting, zero content change) AFTER the reproducibility guard
# already passed. Committing that churn makes the NEXT run's guard fail — a
# blanket `git add ios` has shipped it before. Warn while it's still cheap.
if ! git -C "$REPO" diff --quiet -- 'ios/**/*.xcstrings' 2>/dev/null; then
  printf '\033[33mNOTE: xcodebuild churned the .xcstrings catalogs during this run (formatting only).\n'
  printf 'Discard before committing:  git checkout -- "ios/FinchApp/Sources/FinchShared/Resources/*.xcstrings"\033[0m\n'
fi

if [ ${#FAILED[@]} -eq 0 ]; then
  printf '\033[32mall checks passed\033[0m\n'
  exit 0
fi
printf '\033[31m%d failed:\033[0m\n' "${#FAILED[@]}"
printf '  - %s\n' "${FAILED[@]}"
# The excerpts above are the first few matching lines; the full logs are what you
# actually need when a build fails. They are kept ONLY on failure (see cleanup).
printf '\nfull logs: %s\n' "$RUN_DIR"
exit 1
