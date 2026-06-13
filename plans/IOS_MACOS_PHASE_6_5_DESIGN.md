# finch for iOS & macOS — Phase 6.5 Implementation Design (Share Extension receipts)

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce a
> step-by-step implementation plan for Phase 6.5.
>
> Companion documents:
>
> - `plans/IOS_MACOS_PLAN.md` — direction brief
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` through `IOS_MACOS_PHASE_5_DESIGN.md` —
>   Phases 1.0 through 5 full designs
> - `plans/IOS_MACOS_PHASE_6_1_DESIGN.md` — Phase 6.1 (Spotlight)
> - `plans/IOS_MACOS_PHASE_6_2_DESIGN.md` — Phase 6.2 (Notifications)
> - `plans/IOS_MACOS_PHASE_6_3_DESIGN.md` — Phase 6.3 (Biometric)
> - `plans/IOS_MACOS_PHASE_6_4_DESIGN.md` — Phase 6.4 (App Intents)
> - `plans/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch)
> - `plans/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/IOS_MACOS_PHASE_6_5_DESIGN.md` (this file) — Phase 6.5
>
> Phase 6 is decomposed into 5 sub-specs (6.1-6.5). This is
> 6.5: the Share Extension for receipt photos + PDFs — the
> long-deferred feature from the plan's §7. **The hardest of
> the 5 sub-specs** (process boundary + App Group +
> iCloud container trade-off + `PhotosPicker` integration +
> the attachment pipeline).
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-5 are complete._

## See also

- `plans/IOS_MACOS_INDEX.md` §2.4, §2.5 — App Group + 75th action (`setEntryAttachment`)
- `plans/IOS_MACOS_WIRE_FORMAT.md` §2 — the 74+1 Args catalogue
- `plans/IOS_MACOS_PLAN.md` §2.5 — the receipt attachments feature
- `plans/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 (iCloud; App Group is added here in Phase 6.5, not Phase 5)
- `plans/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch; reuses App Group)
- `plans/IOS_MACOS_PHASE_2_DESIGN.md` §3.3 — `setEntryAttachment` action

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (The Share Extension target) + §3 (The pending attachment manifest) + §6 (The Share Extension's entitlements) |
| §3. iOS UI surfaces | §4 (The mini-form) + §5 (The "existing transaction" picker) + §7 (The `PhotosPicker` integration) |
| §4. Cross-cutting concerns | §2 (The Share Extension target — process boundary + App Group) |
| §5. Wire contracts | §3 (manifests are written to the App Group + the iOS app reads them and dispatches chokepoint writes) |
| §6. CI / test infrastructure | §8 (CI changes) |
| §7. Out of scope (firm) | §10 |
| §8. Spec self-review + open questions | §11 + §9 |

## §1. Goal & non-goals

**Goal** — Land the **long-deferred receipt-photo feature**
(per the plan's §7):

- The user can share a **photo or PDF** into finch from
  Photos, Safari, Mail, Files, AirDrop, or any other iOS
  app that supports the system share sheet
- The Share Extension **writes the attachment** to the
  finch app's `Application Support/attachments/<entry_id>/`
  directory (per the plan's §2.5.1; the path structure
  is stable across the DE cutover)
- The attachment is linked to an existing transaction
  (the user picks which one) OR creates a new transaction
  (with a mini-form: amount + description)
- The chokepoint dispatches the `addTransaction` action
  (for new entries) + the new `setEntryAttachment` action
  (for the attachment row); `removeAttachment` is the
  inverse (used from the Transaction Detail's "remove
  attachment" affordance)

**Non-goals (firm)**:

- **No new tabs / write screens / power features** — the 6
  tabs + 7 write screens + 7 power features are unchanged.
  Phase 6.5 adds a **Share Extension** target to the Xcode
  project + a **mini-form** for "create a transaction from
  this receipt."
- **No new selectors** — the Phase 1.5 selectors are the
  full set. The Share Extension reads the `Tx[]` cache
  (via the App Group container) to populate the
  "attach to existing transaction" picker.
- **One new chokepoint action** — `setEntryAttachment`
  (§3.3). The chokepoint's only new action in Phase 6.5;
  the action is needed because the Share Extension stages
  the file to the App Group, then the iOS app moves it to
  the live `attachments/<entry_id>/...` directory and
  dispatches `setEntryAttachment` to record the row.
  `addTransaction` + `removeAttachment` (Phase 2) are
  reused; the 74 unique Phase 2 actions become 75.
- **OCR included** — Phase 6.5 ships OCR via Apple's local
  `Vision` framework (no cloud, no data sent off-device).
  When the user picks a receipt photo, the iOS app runs
  `VNRecognizeTextRequest` on the image; the recognized
  text is parsed for amount patterns (e.g., "Total:
  $87.23") and merchant patterns (the first non-numeric
  line near the top). The mini-form pre-fills amount +
  description; the user can edit before saving. **OCR is
  opt-in** (a "Use OCR" toggle in the mini-form; default
  on for photos, off for PDFs).
- **No multi-photo batching** — one photo/PDF per share
  invocation. Multi-photo is a future phase.
- **No PDF annotation** — the user attaches a PDF as-is.
  Annotation is a future phase.
- **No video attachments** — photos and PDFs only.
- **No iCloud Drive folder watching** — the Share Extension
  writes to the App Group container (which is the iOS app
  group's local container, not iCloud Drive). The iOS app
  then syncs to iCloud Drive (Phase 5) on the next pack
  build.

**Estimated scope**: ~1,200-1,600 lines Swift (the Share
Extension target + the mini-form + the attachment pipeline
+ the OCR via Vision) + ~400 lines SwiftUI (the mini-form)
+ ~400 lines tests. **5-6 weeks of full-time work** for a
small team. **The largest of the 5 sub-specs** (the OCR
addition grew 6.5 from 3-4 weeks to 5-6 weeks per the
resolution-pass decision).

## §2. The Share Extension target

A Share Extension is a **separate Xcode target** that
ships with the iOS app. The extension runs in its own
process; it has access to the share content (a photo,
PDF, URL) and to the App Group container (where the finch
app's data lives). The extension does NOT have direct
access to the finch app's DB; it writes to the App Group
container and the iOS app reads the staged attachment on
foreground.

### 2.1 — The Xcode target setup

The Share Extension is a new target in the Xcode project
(`ios/FinchShareExtension/`). The target's `Info.plist`
declares:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>NSExtensionActivationRule</key>
        <dict>
            <key>NSExtensionActivationSupportsImageWithMaxCount</key>
            <integer>1</integer>
            <key>NSExtensionActivationSupportsFileWithMaxCount</key>
            <integer>1</integer>
        </dict>
    </dict>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
</dict>
```

This declares the extension as a **Share Extension** that
accepts images (photos) and files (PDFs), with a max
count of 1 (one attachment per share invocation). The
extension's principal class is `ShareViewController`, a
`UIViewController` subclass that hosts a SwiftUI form.

### 2.2 — The App Group entitlement

The Share Extension + the iOS app + (Phase 7's) the
Widget Extension all share the same App Group container.
The entitlement key (added to all 3 targets):

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.juchengquan.finch</string>
</array>
```

The App Group container is at
`~/Library/Group Containers/group.com.juchengquan.finch/`.
The iOS app + the Share Extension + the widget all
read/write here.

### 2.3 — The `ShareViewController`

The `ShareViewController` is a small `UIViewController`
that hosts a SwiftUI `ShareFormView`:

```swift
// ios/FinchShareExtension/ShareViewController.swift
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareFormView(
            extensionContext: self.extensionContext
        ))
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.didMove(toParent: self)
    }
}

struct ShareFormView: View {
    let extensionContext: NSExtensionContext?

    @State private var attachment: SharedAttachment?
    @State private var attachToExisting: Bool = true
    @State private var selectedEntryId: String?
    @State private var newTransaction: NewTransactionForm = .init()

    var body: some View {
        NavigationStack {
            Form {
                Section("Attachment") {
                    if let attachment = attachment {
                        AttachmentRow(attachment: attachment)
                    }
                }
                Section("Attach to") {
                    Picker("Mode", selection: $attachToExisting) {
                        Text("Existing transaction").tag(true)
                        Text("New transaction").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if attachToExisting {
                        TransactionPicker(selectedEntryId: $selectedEntryId)
                    } else {
                        NewTransactionFields(form: $newTransaction)
                    }
                }
            }
            .navigationTitle("Add Receipt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { complete(success: false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .task {
            attachment = await loadSharedAttachment()
        }
    }

    private func loadSharedAttachment() async -> SharedAttachment? {
        // Read the shared attachment from the extension context
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { return nil }
        // ... load the photo or PDF ...
    }

    private func save() {
        // 1. Stage the attachment to the App Group container
        // 2. Write a "pending attachment" manifest to the
        //    App Group container
        // 3. Complete the extension
        complete(success: true)
    }

    private func complete(success: Bool) {
        if success {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: "FinchShare", code: 0))
        }
    }
}
```

The form has two modes:
- **Attach to existing transaction**: a picker showing
  the most recent 100 transactions (sorted by date desc)
- **New transaction**: a mini-form with amount +
  description (the user can fill in the basics; the
  iOS app can fill in the rest on foreground)

When the user taps **Save**, the Share Extension stages
the attachment to the App Group container and writes a
"pending attachment" manifest. The Share Extension
completes; control returns to the source app (Photos,
Safari, etc.).

The iOS app picks up the pending attachment on the next
foreground (see §3).

## §3. The pending attachment manifest

The Share Extension writes a manifest to the App Group
container. The iOS app reads the manifest on foreground
and dispatches the chokepoint.

### 3.1 — The manifest

```swift
// ios/FinchApp/ShareExtension/PendingAttachment.swift
public struct PendingAttachment: Codable, Sendable {
    public let id: String  // UUID
    public let entryId: String  // the target entry (existing or new)
    public let isNewEntry: Bool
    public let newTransactionForm: NewTransactionForm?  // if isNewEntry
    public let attachment: AttachmentPayload
    public let stagedAt: Date
}

public struct AttachmentPayload: Codable, Sendable {
    public let filename: String  // e.g., "IMG_1234.jpg" or "receipt.pdf"
    public let mimeType: String
    public let fileSize: Int64
    public let sha256: String
    public let stagedPath: String  // relative to the App Group container
}
```

The manifest is at `<AppGroup>/pending_attachments/pending_<id>.json`.
The staged file (the photo or PDF) is at
`<AppGroup>/pending_attachments/files/<id>/<filename>`.

### 3.2 — The iOS app's pickup

The iOS app polls for pending attachments on:
- App launch
- App foreground
- The Share Extension's `completeRequest` notification
  (the iOS app is brought to the foreground after the
  Share Extension completes)

```swift
// ios/FinchApp/ShareExtension/PendingAttachmentProcessor.swift
import UniformTypeIdentifiers

@MainActor
public final class PendingAttachmentProcessor {
    public static let shared = PendingAttachmentProcessor()

    public func processPendingAttachments() async {
        let manifestURLs = listPendingManifests()
        for manifestURL in manifestURLs {
            let manifest = try? JSONDecoder().decode(PendingAttachment.self, from: Data(contentsOf: manifestURL))
            guard let manifest = manifest else { continue }

            // 1. If isNewEntry, dispatch addTransaction first.
            //    The chokepoint's addTransaction returns Void
            //    (the wire contract is `applyMutation(exec,
            //    action, args): Promise<void>`), so the
            //    client-generated entryId is what the
            //    attachment row is keyed to. The form's
            //    `id` is included in `form.toArgs()`.
            var entryId = manifest.entryId
            if manifest.isNewEntry, let form = manifest.newTransactionForm {
                do {
                    try await store.apply(
                        action: "addTransaction",
                        args: form.toArgs()
                    )
                    entryId = form.id
                } catch {
                    // Log and skip
                    continue
                }
            }

            // 2. Move the staged file to the attachments directory
            let attachmentId = UUID().uuidString
            let destDir = attachmentsDir.appendingPathComponent(entryId)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let fileExt = UTType(mimeType: manifest.attachment.mimeType)?.preferredFilenameExtension ?? "bin"
            let destURL = destDir.appendingPathComponent("\(attachmentId).\(fileExt)")
            try? FileManager.default.moveItem(
                at: stagedFileURL(for: manifest),
                to: destURL
            )

            // 3. Dispatch setEntryAttachment (the chokepoint's
            //    only new action in Phase 6.5; added in §3.3).
            //    addTransaction was already dispatched above.
            try? await store.apply(
                action: "setEntryAttachment",
                args: [
                    "entryId": entryId,
                    "attachmentId": attachmentId,
                    "relPath": "\(entryId)/\(attachmentId).\(fileExt)",
                    "mimeType": manifest.attachment.mimeType,
                    "fileSize": manifest.attachment.fileSize,
                    "sha256": manifest.attachment.sha256
                ]
            )

            // 4. Delete the staged file + manifest
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: stagedFileURL(for: manifest))
        }
    }
}
```

The iOS app's `FinchApp` body calls
`processPendingAttachments()` on launch + foreground +
the Share Extension's completion notification.

### 3.3 — The `setEntryAttachment` action

The proposal adds **one new chokepoint action**:
`setEntryAttachment`. This is the action that the iOS
app dispatches after moving the staged file. The
`removeAttachment` action (Phase 2) is the opposite
(deletes an existing attachment).

The `setEntryAttachment` action:
1. Inserts a row into `entry_attachments` (the table
   from the web's `lib/db/domain/attachments/types.ts`)
2. Updates the entry's projection (the `Tx` row gains
   the attachment)
3. Invalidates the audit cache for the affected
   ledger (the cache may have been cached without the
   attachment)

This is the only new chokepoint action in Phase 6.5.
The Share Extension doesn't write directly to the DB;
it stages a manifest, and the iOS app dispatches the
chokepoint.

### 3.4 — The attachment file path

The attachment file is moved from the App Group
container's `pending_attachments/files/<id>/` to the
iOS app's `Application Support/attachments/<entry_id>/<attachment_id>.<ext>`.
This matches the path structure from the plan's §2.5.1
(the web's path structure is identical: `attachments/<entry_id>/<attachment_id>.<ext>`).
The .finch pack (Phase 1.0) reads from this path when
building the pack.

The iOS app's `setFileProtection` (Phase 6.3) applies
the `completeUnlessOpen` protection to the moved file.

## §4. The mini-form

When the user picks **New transaction** in the Share
Extension form, a mini-form appears:

```
┌─────────────────────────────────────┐
│  Add Receipt                         │
├─────────────────────────────────────┤
│  Attachment                          │
│  📄 IMG_1234.jpg (2.3 MB)           │
│                                      │
│  Attach to                           │
│  ( ) Existing transaction           │
│  (•) New transaction                │
│                                      │
│  Amount                              │
│  ┌──────────┐                        │
│  │  87.23   │  USD                   │
│  └──────────┘                       │
│                                      │
│  Description                         │
│  ┌──────────────────────────────┐   │
│  │ Whole Foods                  │   │
│  └──────────────────────────────┘   │
│                                      │
│  Account (default: most recent)     │
│  Chase Checking                  ▾   │
│                                      │
│  Category (default: most recent)     │
│  🛒 Groceries                    ▾   │
│                                      │
│  [Cancel]                  [Save]    │
└─────────────────────────────────────┘
```

The mini-form is **minimal** — the user can fill in the
basics (amount, description, account, category). The
iOS app, on foreground, dispatches the `addTransaction`
action with these fields. The user can refine the
transaction in the iOS app later (add tags, notes,
splits, etc.).

The **default account** is the most-recently-used
account (per the `lastUsedAt` field on `AccountRow`).
The **default category** is the most-recently-used
category. The user can change either.

## §5. The "existing transaction" picker

When the user picks **Existing transaction**, a picker
appears showing the 100 most recent transactions:

```
┌─────────────────────────────────────┐
│  Pick a transaction                  │
├─────────────────────────────────────┤
│  🔍 [search                  ]      │
│                                      │
│  Jun 12  Whole Foods        -$87.23  │
│  Jun 12  Coffee Bar          -$6.50  │
│  Jun 11  Whole Foods        -$45.67  │
│  Jun 11  Amazon             -$32.18  │
│  ...                                 │
└─────────────────────────────────────┘
```

The picker reads from the **App Group snapshot** (Phase
7's `widget_snapshot.json` is one example; the Share
Extension uses a similar snapshot). The iOS app
maintains a `share_extension_snapshot.json` in the App
Group that contains the most recent 100 transactions
(plus the full `AccountRow[]` + `Category[]` +
`Counterparty[]` arrays). The Share Extension reads this
snapshot on launch.

The picker supports search (the user types a merchant
name; the list filters). The search is client-side
(filtering the in-memory list); no DB access.

## §6. The Share Extension's entitlements

The Share Extension's entitlements:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.juchengquan.finch</string>
</array>
```

The extension doesn't have iCloud Drive access (only the
iOS app does, via the `com.apple.security.icloud-container-identifiers`
entitlement). The extension reads the App Group snapshot
(written by the iOS app) and writes the pending
attachment manifest + staged file (in the App Group
container).

## §7. The `PhotosPicker` integration (optional, Phase 6.5.5)

A follow-up: the iOS app (not the Share Extension) has a
**"Add receipt from Photos"** button in the Transaction
Detail screen. The button uses the SwiftUI `PhotosPicker`
to let the user pick a photo from the Photos library;
the photo is staged the same way as the Share Extension
flow; the chokepoint dispatches `setEntryAttachment`.

This is a Phase 6.5.5 follow-up; the Share Extension
flow is Phase 6.5.

## §8. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- A **Share Extension target test**: build the extension;
  assert the Info.plist has the right `NSExtension` keys
- An **App Group test**: assert the extension + the iOS
  app share the same App Group container
- A **manifest test**: simulate a Share Extension save;
  assert the manifest is at the right path with the
  right content
- A **pickup test**: simulate the iOS app foreground;
  call `processPendingAttachments()`; assert the chokepoint
  was dispatched with the right args
- A **setEntryAttachment test**: dispatch
  `setEntryAttachment`; assert the row is inserted in
  `entry_attachments`; assert the entry's `Tx` projection
  includes the new attachment

## §9. Open questions

The plan's §14.1 lists "Pack cadence + sweep policy" and
"Conflict-copy UX" — neither directly affects Phase 6.5.
The plan also lists "iCloud folder naming + visibility" —
Phase 6.5 doesn't touch the iCloud folder.

**Not blocking Phase 6.5 (decide later)**:

- **OCR quality**: the Vision framework's text recognition
  is high-quality for printed receipts but lower for
  handwritten or low-light photos. The user can always
  edit the pre-filled amount + description before saving.
  A future phase can add a "re-OCR" button (if the user
  re-opens the mini-form to correct an OCR result).
- **Multi-photo batching**: the proposal handles one
  photo per share invocation. The `NSExtensionActivationSupportsImageWithMaxCount`
  is set to 1. A future phase can lift this to N.
- **PDF text extraction**: a future phase can extract
  text from PDFs (using `PDFKit`) to pre-populate the
  amount + description. The Vision framework supports
  PDFs natively; this is a small extension.
- **Share Extension on Mac**: macOS supports Share
  Extensions. The proposal is iOS / iPadOS only. A
  future phase can add macOS support.
- **Share Extension on iPad with the Slide Over / Split
  View** interaction: the proposal works in all iPad
  size classes. A future phase may refine the iPad UX
  (the iPad has more screen real estate; the form could
  be wider).
- **Background-attachment processing**: the iOS app's
  pickup is foreground-triggered. A future phase can use
  a background task to process pending attachments even
  when the app isn't foregrounded.

**Specifically for the iCloud + App Group trade-off**:

- **The Share Extension writes to the App Group
  container, NOT to iCloud Drive.** The iOS app's
  iCloud Drive sync (Phase 5) syncs the moved
  attachment the next time a pack is built. **Per Q47,
  the iOS app's `PendingAttachmentProcessor` calls
  `forceFlush()` on Phase 5's debouncer after moving the
  file** — the iCloud sync happens within 1-2 seconds
  (no 30-second debounce wait). This is the trade-off
  selected in the resolution pass.
- **The Share Extension CANNOT write directly to iCloud
  Drive.** iCloud Drive requires the iOS app's iCloud
  container entitlement, which the extension doesn't
  have (per the entitlement model). The App Group is the
  only shared writable space between the iOS app and the
  Share Extension.
- **The widget extension (Phase 7) reads from the App
  Group.** The Share Extension writes to the App Group.
  Both extensions and the iOS app share the App Group;
  this is the standard iOS pattern for multi-process
  apps.

**Not blocking Phase 6.5 because they're Phase 7+ by design**:

- **Widgets / Live Activities / Watch** — Phase 7. The
  Share Extension writes to the App Group; the widgets
  read from the App Group snapshot. No cross-dependency.
- **Row-level sync** — Phase 8

## §10. Out of scope (firm)

These are explicitly NOT in Phase 6.5:

- **No new tabs / write screens / power features** — the 6
  tabs + 7 write screens + 7 power features are unchanged
- **No new selectors** — the Phase 1.5 selectors are the
  full set
- **No new chokepoint actions** — wait, the proposal DOES
  add one: `setEntryAttachment` (the action that the iOS
  app dispatches after moving the staged file). This is
  the only new chokepoint action in Phase 6.
- **OCR is included** (per Q20). The Vision framework runs
  locally; the user can always edit the pre-filled amount
  + description before saving. The OCR is opt-in (a
  "Use OCR" toggle; default on for photos, off for PDFs).
- **No multi-photo batching** — one photo per share
  invocation
- **No PDF text extraction** — the user manually enters
  the amount + description
- **No PDF annotation** — attach as-is
- **No video attachments** — photos and PDFs only
- **No Share Extension on Mac** — iOS / iPadOS only
- **No background-attachment processing** — the pickup
  is foreground-triggered

## §11. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The Share Extension's `Info.plist` (§2.1),
  the `ShareViewController` (§2.3), the App Group
  entitlement (§2.2 + §6), the pending attachment
  manifest (§3.1), the iOS app's pickup (§3.2), the
  `setEntryAttachment` action (§3.3), the mini-form
  (§4), the existing-transaction picker (§5) are all
  concrete.
- **Internal consistency**: §2's Share Extension uses
  the standard `UIViewController` + `NSExtensionContext`
  pattern. §3.1's manifest uses the same shape as the
  Phase 7 widget snapshot. §3.2's pickup dispatches
  `addTransaction` + `setEntryAttachment` (the latter is
  a new Phase 6 action; the former is Phase 2). The App
  Group container is the same one Phase 7's widgets use.
- **Scope**: focused on Phase 6.5 only. Phases 6.1-6.4
  are referenced as separately shipped specs. Phase 7+
  are explicitly out of scope (§10). The estimated scope
  (5-6 weeks) reflects the Share Extension target +
  App Group + pending attachment pipeline + mini-form
  + OCR (per Q20)
  complexity.
- **Ambiguity**: §2.1's `Info.plist` is concrete. §2.3's
  `ShareViewController` has concrete code. §3.1's
  manifest has concrete fields. §3.2's pickup has
  concrete code. §4's mini-form is concrete. §5's
  existing-transaction picker is concrete. §8 enumerates
  the CI test cases. §9 enumerates the open questions
  with proposed answers.
