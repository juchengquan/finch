#!/usr/bin/env bash
# frontend/scripts/check-component-filenames.sh — CI check for the
# component file naming convention (PR 4). Enforces:
#   - components/ui/*.tsx must be kebab-case (no capital letters)
#   - components/*.tsx may be PascalCase only if in the allow-list
#     (currently 6 files: 4 intentional, 2 transitional — see below)
#
# Run via: bun run check:naming
# Exit 0 = pass; exit 1 = fail (with details on stderr).
#
# Allow-list (PascalCase in components/):
#   Intentional (kept PascalCase by design):
#     - PageShell.tsx, primitives.tsx, DesktopShell.tsx, MobileShell.tsx
#   Transitional (rename to kebab-case in a follow-up):
#     - MobileTabsEditor.tsx, RowActions.tsx
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
# 6 entries: 4 are the post-PR-4 "intentional" PascalCase files
# (PageShell.tsx, primitives.tsx, DesktopShell.tsx, MobileShell.tsx),
# 2 are transitional feature components that should be renamed to
# kebab-case in a follow-up (MobileTabsEditor.tsx, RowActions.tsx).
# When those 2 are renamed, remove them from this list.
allowlist="PageShell.tsx primitives.tsx DesktopShell.tsx MobileShell.tsx MobileTabsEditor.tsx RowActions.tsx"
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
