#!/usr/bin/env bash
# frontend/scripts/check-component-filenames.sh — CI check for the
# component file naming convention (PR 4). Enforces:
#   - components/ui/*.tsx must be kebab-case (no capital letters)
#   - components/*.tsx may be PascalCase only if in the allow-list
#     (currently 4 files — all intentional)
#
# Run via: bun run check:naming
# Exit 0 = pass; exit 1 = fail (with details on stderr).
#
# Allow-list (PascalCase in components/):
#   Intentional (kept PascalCase by design):
#     - PageShell.tsx, primitives.tsx, DesktopShell.tsx, MobileShell.tsx
#   Transitional: none — the 3 transitional files from PR 4 were
#     deleted (MobileComponents.tsx, in PR A) or renamed to
#     kebab-case (MobileTabsEditor.tsx, RowActions.tsx, in PR B).
set -euo pipefail

cd "$(dirname "$0")/.."

# Check 1: components/ui/*.tsx must be kebab-case (no capital letters).
non_kebab=$(find components/ui -maxdepth 1 -name '*.tsx' | grep -E '[A-Z]' || true)
if [ -n "$non_kebab" ]; then
  echo "components/ui/* must be kebab-case (no capital letters):" >&2
  echo "$non_kebab" >&2
  exit 1
fi

# Check 2: components/*.tsx may be PascalCase only if in the allow-list.
# 4 entries: all are the post-PR-4 "intentional" PascalCase files
# (PageShell.tsx, primitives.tsx, DesktopShell.tsx, MobileShell.tsx).
# No transitional entries remain; the 2 transitional files from
# PR 4 (MobileTabsEditor.tsx, RowActions.tsx) were renamed to
# kebab-case in PR B.
allowlist="PageShell.tsx primitives.tsx DesktopShell.tsx MobileShell.tsx"
allowlist_re=$(echo "$allowlist" | tr ' ' '|')

is_pascal() {
  echo "$1" | grep -qE '[A-Z]'
}

non_allowlisted=$(find components -maxdepth 1 -name '*.tsx' | while read f; do
  base=$(basename "$f")
  if is_pascal "$base"; then echo "$f"; fi
done | grep -vE "$allowlist_re" || true)

if [ -n "$non_allowlisted" ]; then
  echo "components/*.tsx must be kebab-case (or in the allow-list):" >&2
  echo "$non_allowlisted" >&2
  echo "" >&2
  echo "Allow-list: $allowlist" >&2
  exit 1
fi

echo "Component filenames OK."
