# SwiftUI vs. UIKit — policy

**TL;DR: SwiftUI-first, always.** Build every screen and component in SwiftUI. Drop to
UIKit/AppKit only for the narrow cases SwiftUI genuinely can't express, and when you do,
**bridge the smallest possible piece** behind a `Representable` wrapper — never adopt UIKit
for a whole screen or flow.

The app is ~99% SwiftUI today and should stay that way. This note records why, what the
exceptions are, and the pattern for adding one.

## The rule

1. **SwiftUI by default** — lists, forms, navigation, tabs, sheets, charts, widgets, Watch.
   No exceptions here; SwiftUI covers all of it.
2. **Bridge, don't switch.** When SwiftUI can't do something, wrap the minimal UIKit
   (iOS) / AppKit (macOS) piece in a `UIViewRepresentable` / `UIViewControllerRepresentable`
   (or `NSView…` on macOS) and keep it isolated — ideally in `Common/`. The surrounding tree
   stays SwiftUI.
3. **Host SwiftUI inside any mandatory UIViewController.** Where the OS requires a
   UIViewController entry point (e.g. an app extension's principal class), render the actual
   UI with `UIHostingController` so even that piece is SwiftUI inside.
4. **Never adopt UIKit for an entire flow.** There is no case in this app's roadmap that
   justifies a UIKit-rooted screen.

## Use the SwiftUI-native API (don't reach for the UIKit one)

These are the spots people habitually drop to UIKit. We don't — use the SwiftUI version:

| Need | Use (SwiftUI) | NOT |
|---|---|---|
| Share a file | `ShareLink` | `UIActivityViewController` |
| Import a file | `.fileImporter` | `UIDocumentPickerViewController` |
| Export a file | `ShareLink` / `.fileExporter` | `UIDocumentPicker…` |
| Pick a photo (receipt) | `PhotosPicker` | `UIImagePickerController` |
| Charts | the custom SVG primitives in `components`/`primitives` | a UIKit charting lib |
| Open iOS Settings | `Link(destination: URL(string: UIApplication.openSettingsURLString)!)` | a UIKit shim |

## Current, sanctioned UIKit/AppKit usage (keep minimal)

As of this writing the entire app touches UIKit/AppKit in exactly four places, all justified:

1. **`FinchApp/Common/ActivityMonitor.swift`** — a window-level `UITapGestureRecognizer`
   (AppKit `NSEvent` monitor on macOS) that resets the biometric idle-lock clock on *any*
   user interaction **without consuming it**. SwiftUI has no passive, non-consuming,
   app-wide touch observer — a root `.simultaneousGesture` swallowed `List`/`NavigationLink`
   taps. This is the canonical example of the right pattern: a zero-size `Representable`,
   `#if os(iOS)` UIKit / `#else` AppKit, isolated in `Common/`.
2. **`FinchShare/ShareViewController.swift`** — a share **extension's principal class must be
   a `UIViewController`** (system contract). Not a SwiftUI gap; host SwiftUI inside it.
3. **`UIApplication.openSettingsURLString`** — the only way to deep-link to the iOS Settings
   app. One line.
4. **`NSMetadataQuery`** (iCloud Drive monitoring) — a Foundation file-presence API, not UI.

## Likely future bridges (acceptable when the feature lands)

If these features are added, a thin `Representable` bridge is the expected, approved
solution — not a reason to rethink the architecture:

- **"Scan receipt" with the camera** → `VNDocumentCameraViewController` (VisionKit). No
  SwiftUI equivalent.
- **In-app preview of an attachment** (tap a receipt image/PDF) → **no bridge needed.**
  SwiftUI's `.quickLookPreview($url)` modifier (iOS 14+/macOS 13+) handles in-app receipt
  preview cross-platform with pure SwiftUI — shipped in the Edit form (tap a receipt row).
  A `QLPreviewController`/`PDFKit` representable would only be a fallback if that modifier
  stopped meeting our needs.
- **Rich-text / formatted notes** → `UITextView` (SwiftUI `TextEditor` is plain text).
- **Custom numeric keypad / input-accessory "Done" toolbar** for amount entry → a small
  UIKit bridge if `keyboardType` isn't enough.

Things that will **not** need UIKit: cross-section drag reordering (solved at the design
level with a flat list — see the Accounts reorder feature — rather than `UICollectionView`),
and anything in the lists/forms/navigation/tabs/sheets/widgets/Watch space.

## Deployment-target caveat

The app targets **iOS 17 / macOS 14 / watchOS 10** (a deliberately wide floor). Some newer
SwiftUI APIs that would *remove* the need for a bridge — e.g. iOS 26's native
`RichTextEditor`, `WebView`, and the improved `TextEditor` — are unavailable at iOS 17. So
the low floor is a conscious trade: broad device support, at the cost of occasionally
bridging to UIKit for things newer SwiftUI would cover natively. If rich text / PDF / web
become priorities, weigh **raising the floor** against **bridging** at that point.

## Checklist before adding a UIKit bridge

- [ ] Confirmed no SwiftUI-native API does this (check the table above + current SDK).
- [ ] The bridge wraps the *smallest* unit (one view / one controller), not a screen.
- [ ] It lives in `Common/` (or alongside its single consumer) behind a `Representable`.
- [ ] Cross-platform handled: `#if os(iOS)` UIKit / `#else` AppKit, or `#if canImport(UIKit)`.
- [ ] Any required UIViewController hosts its real UI via `UIHostingController`.
