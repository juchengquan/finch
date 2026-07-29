#!/usr/bin/env python3
"""Fail when UIKit code puts a bare string literal where the user will read it.

Why this exists
---------------
SwiftUI's `Text("…")` and `.searchable(prompt: "…")` take LocalizedStringKey, so
`xcodebuild -exportLocalizations` finds them and the i18n guards keep the catalog
honest. UIKit takes plain `String`: `label.text = "Total"`,
`UIBarButtonItem(title: "Done")`, `UIAlertAction(title: "OK")`. Those bypass
extraction ENTIRELY — no key, no catalog entry, no guard failure — and ship
English to zh-Hans readers silently.

That risk arrived on the very first converted screen and was caught only because
the author happened to write `String(localized:)`. This guard removes the
"happened to".

The rule: inside the UIKit sources, a string literal in a user-facing position
must be wrapped in `String(localized:)`. Add `// i18n-ignore` on the line for the
rare genuine non-UI string.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UIKIT = ROOT / "FinchApp" / "Sources" / "FinchAppUIKit"

# Positions whose text reaches the screen.
PATTERNS = [
    (re.compile(r"\.text\s*=\s*\""), ".text"),
    (re.compile(r"\.secondaryText\s*=\s*\""), ".secondaryText"),
    (re.compile(r"\.placeholder\s*=\s*\""), ".placeholder"),
    (re.compile(r"\.title\s*=\s*\""), ".title"),
    (re.compile(r"UIBarButtonItem\([^)]*title:\s*\""), "UIBarButtonItem(title:)"),
    (re.compile(r"UIAlertAction\([^)]*title:\s*\""), "UIAlertAction(title:)"),
    (re.compile(r"UIAlertController\([^)]*title:\s*\""), "UIAlertController(title:)"),
    (re.compile(r"UIAlertController\([^)]*message:\s*\""), "UIAlertController(message:)"),
    (re.compile(r"UIAction\([^)]*title:\s*\""), "UIAction(title:)"),
    (re.compile(r"UIMenu\([^)]*title:\s*\""), "UIMenu(title:)"),
    (re.compile(r"UIContextualAction\([^)]*title:\s*\""), "UIContextualAction(title:)"),
    (re.compile(r"UITabBarItem\([^)]*title:\s*\""), "UITabBarItem(title:)"),
    (re.compile(r"accessibilityLabel\s*=\s*\""), "accessibilityLabel"),
]

# A literal that is already localized, empty, or has no letters to translate.
SAFE = re.compile(r'String\(localized:|""|"\s*"|"[^"A-Za-z]*"')


def main() -> int:
    if not UIKIT.is_dir():
        print(f"  (no UIKit sources at {UIKIT.relative_to(ROOT)} — nothing to check)")
        return 0

    problems = []
    for path in sorted(UIKIT.rglob("*.swift")):
        for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//") or "i18n-ignore" in line:
                continue
            for pattern, what in PATTERNS:
                if pattern.search(line) and not SAFE.search(line):
                    problems.append((path.relative_to(ROOT), n, what, stripped[:88]))
                    break

    if not problems:
        return 0

    print("  UIKit strings that bypass localization extraction:\n")
    for rel, n, what, text in problems:
        print(f"    {rel}:{n}  [{what}]")
        print(f"      {text}")
    print(
        "\n    UIKit takes plain String, so these are never extracted and render\n"
        "    English in every language with NO guard failing. Wrap them:\n"
        '        label.text = String(localized: "Total")\n'
        "    or mark a genuine non-UI string with  // i18n-ignore"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
