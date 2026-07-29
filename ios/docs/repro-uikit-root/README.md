# Minimal reproducer — iOS 26 scroll-edge shadow on a pushed SwiftUI page

A standalone UIKit app (`UIApplicationDelegate` → `UIWindow` → `UITabBarController`
→ `UINavigationController`) with three pushes. Build with `xcodegen generate`.

Steps, per push: open it, scroll the list down, press Home, wait ~3s, reopen, and
watch the area under the navigation bar for a dark band that fades over ~2–3s.

| Push | Page | iOS 26.5 result |
|---|---|---|
| A | `UITableViewController` | **clean** |
| B | SwiftUI `List` in a `UIHostingController` | **shadows** |
| C | same + `.searchable` | **shadows** |

A is the control: it matches Files/Messages, so the app reproduces the correct
baseline. B differs from A only in that the pushed page is SwiftUI.

Combined with the finch lab (`ShadowLab.swift`, same branch): a pure UIKit table
pushed inside a *SwiftUI* app also shadows. So SwiftUI anywhere in the push path —
the app root or the page — is sufficient; clean requires UIKit on both sides.

The artifact cannot be captured: `simctl` screenshots and video read a framebuffer
without the glass layers, and macOS `screencapture` is TCC-blocked under tmux. It
must be judged by eye.
