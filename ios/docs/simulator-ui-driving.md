# Driving the iOS Simulator from the terminal (for Claude / scripts)

How to let an agent (or a script) **tap, navigate, and measure** the booted iOS
Simulator — not just screenshot it. Screenshots work with no special setup;
*interaction* is the part that needs tooling.

## What `simctl` gives you for free

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # else xcrun won't find simctl

xcrun simctl list devices available | grep -i booted   # find the booted sim
xcrun simctl launch <UDID> com.juchengquan.finch       # launch the app
xcrun simctl io <UDID> screenshot /tmp/finch.png       # screenshot
xcrun simctl openurl <UDID> "finch://add"              # deep link
```

`simctl` can launch, terminate, open URLs, set appearance, and screenshot —
**but it has no `tap` or `swipe`.** That gap is what `idb` fills.

## Use `idb` — taps, swipes, and measurement

`idb` talks to the simulator over its own companion socket, so it needs **no
Accessibility permission** and no window-coordinate math. Coordinates are
**device points**.

```bash
IDB=~/.local/idb-venv/bin/idb
UDID=$(xcrun simctl list devices | grep <sim-name> | grep -o '[0-9A-F-]\{36\}')

$IDB ui tap 308 84 --udid $UDID
$IDB ui swipe 30 622 330 622 --duration 0.4 --udid $UDID
$IDB ui describe-all --udid $UDID          # a11y tree with frames, in points
```

### Install

```bash
# companion (moved out of homebrew-core -> facebook tap)
brew install facebook/fb/idb-companion

# client: fb-idb needs Python <= 3.11. It calls asyncio.get_event_loop(), which
# RAISES on 3.12+ ("There is no current event loop"), so a default-Python venv
# dies at startup. Pin 3.11:
python3.11 -m venv ~/.local/idb-venv
~/.local/idb-venv/bin/pip install fb-idb
```

### `describe-all` MEASURES — use it for any layout question

Every element carries `frame {x,y,width,height}` in points, so two screens can
be diffed **numerically** instead of squinting at screenshots. This is how the
#554 sheet top-inset bug was found: several hours of pixel-eyeballing produced
two confidently-wrong "fixes", then one `describe-all` (`caption y=167` vs
`138`) gave the real cause in a few scripted experiments.

**Never eyeball spacing from a screenshot when `describe-all` can give numbers.**

#### Reference measurements — SwiftUI vs UIKit rows (2026-07-31)

Measured on Account detail, iPhone 17 Pro Max sim, same account, same data, by
launching with and without `-uikitActivity YES`:

| element | SwiftUI | UIKit | delta |
|---|---:|---:|---:|
| transaction row | **52.0** | **72.3** | +20.3 (+39%) |
| month header | 20.3 | 15.7 | −4.6 |
| month subtitle | 13.3 | 13.3 | 0 |

**The transaction row is the outlier and it is a real regression.** SwiftUI's
`TxRow` is a purpose-built compact row; the converted screens use a generic
`cell.defaultContentConfiguration()` with `text` + `secondaryText`, which is
Apple's two-line subtitle cell and simply is that tall. Three VCs share the
pattern verbatim — `ActivityFeedVC`, `AccountDetailVC`, `BudgetDetailVC` — so
they are all 39% taller per row than the screens they replaced.

Height is not the only gap it creates. The generic cell also renders
`tx.date` raw (`2026-07-29`) where `TxRow` renders a relative/short date
(`Jul 29 · 12:00`, honouring the `finch.feed.relativeDates` preference), and it
carries neither the tag chips nor the running-balance column that `TxRow` shows
on Account detail. Accessibility differs too: SwiftUI rows surface as `Button`
with a composed label ("Expense, Groceries, Jul 29 · 12:00"), the UIKit ones as
`StaticText` ("Groceries, 2026-07-29").

Fixing it means a custom `UIContentConfiguration` matching `TxRow`, not a height
tweak — `defaultContentConfiguration` has no knob that reaches 52pt while
keeping two lines.

```bash
# print every labelled element with its frame
$IDB ui describe-all --udid $UDID | ~/.local/idb-venv/bin/python -c '
import json,sys
for e in json.load(sys.stdin):
    lbl = e.get("AXLabel") or ""
    f = e["frame"]
    if lbl: print("%-12s y=%6.1f h=%5.1f  %s" % (e["type"], f["y"], f["height"], lbl))
'
```

Caveats:
- Toolbar buttons are often **not** exposed individually in the a11y tree; fall
  back to tapping a point (still in points, so it's stable across screen sizes).
- The companion is old (1.1.8, built 2022) but happily drives iOS 26 simulators.

## Getting to a screen quickly

Prefer jumping straight to the target over tapping through the UI:

- **Deep link:** `xcrun simctl openurl <UDID> "finch://add"` (also
  `finch://add?account=<id>`). This is the only external route the app exposes.
- **DEBUG-only launch args** (`FinchApp.swift init()`):
  `xcrun simctl launch <UDID> com.juchengquan.finch -openAdd YES`, and
  `-initialTab <tab>`.
- On iPhone (compact) the bottom bar is **Accounts · Activity · Budgets ·
  Insights · More**; Settings and Scheduled live under **More** (the system tab
  overflow).

Screens with no deep link (e.g. Archived Accounts) still need navigation — use
`describe-all` to locate the row, then `ui tap` its frame centre.

## Appendix: AppleScript / Accessibility is a dead end under tmux

Historically taps were done by clicking the Simulator window through macOS
Accessibility (`System Events`). **Don't retry this** if your session runs
inside `tmux`:

- TCC attributes `osascript` to the **responsible process**, which for a session
  started in a tmux pane is the *detached tmux server* (`PPID 1`) — not your
  terminal, not ClaudeCode.app. Granting either of those changes nothing. You
  would have to grant `/opt/homebrew/bin/tmux` itself **and restart the tmux
  server**, which kills the session you're working in.
- TCC is evaluated at **process start**, so a long-running agent keeps its old
  denial no matter what you toggle mid-session.
- The obvious check is a **false positive**: enumerating processes succeeds even
  when Accessibility is denied. Only reaching into another process's *windows*
  is actually gated, so test that instead:

  ```bash
  osascript -e 'tell application "System Events" to tell process "Simulator" \
    to get size of window 1' >/dev/null 2>&1 && echo "AX-ok" || echo "AX-blocked"
  ```

Beyond the permission problem, coordinate-clicking needs pixel→point conversion
plus a calibrated title-bar offset, and it drifts between adjacent rows. In this
repo's history it twice mis-clicked into *other* simulator windows. `idb` has
none of these failure modes.
