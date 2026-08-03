#!/bin/bash
# Stamp the commit this build came from into the BUILT app's Info.plist, as
# `FinchGitHash`. Read back by `BuildInfo.gitHash`, shown as the About screen's
# "Hash" row.
#
# Run as a post-build script phase by both projects (`project.yml` for FinchApp,
# `project-mac.yml` for FinchMac) — one script so the two cannot drift.
#
# THREE deliberate choices:
#
#   1. Debug only. The hash is a testing aid; Release bundles carry no such key,
#      and the About row that reads it is `#if DEBUG` to match.
#
#   2. The BUILT product's plist, not a generated source file. Writing a
#      generated .swift into the source tree on every build would make the tree
#      permanently dirty — which would defeat the `-dirty` marker below and add
#      churn to every commit.
#
#   3. `-dirty` counts TRACKED modifications only. Untracked files (there are
#      stray .svg files in this working tree) are not a different build of the
#      source, and letting them mark every build dirty would make the marker
#      meaningless.
#
# Never fails the build: no hash is better than an unbuildable app, so every
# failure path degrades to "unknown" or exits 0.

[ "${CONFIGURATION}" = "Debug" ] || exit 0

PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
[ -f "${PLIST}" ] || exit 0

HASH=$(git -C "${SRCROOT}" rev-parse --short HEAD 2>/dev/null || true)

if [ -n "${HASH}" ]; then
    # `diff --quiet HEAD` covers staged and unstaged changes to tracked files.
    if ! git -C "${SRCROOT}" diff --quiet HEAD 2>/dev/null; then
        HASH="${HASH}-dirty"
    fi
else
    # Built outside a git checkout (an exported source archive, say).
    HASH="unknown"
fi

/usr/libexec/PlistBuddy -c "Set :FinchGitHash ${HASH}" "${PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :FinchGitHash string ${HASH}" "${PLIST}" \
    || true
