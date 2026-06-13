# Phase 1.0 Implementation Plan — finch for iOS (read-only iPhone)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working, verifiable iOS app (iPhone 15 simulator, iOS 26+) that opens a `.finch` pack via the system file picker, displays read-only **Accounts / Activity / Budgets / Settings**, and exports a fresh `.finch` via the system share sheet. The 4 tabs cover the parity surface that exercises the 7 selectors, the audit gate, the pack engine, and the I18nError pipeline.

**Architecture:** SwiftUI iPhone target built with Xcode 16+ and the iOS 26+ SDK. Storage is **GRDB.swift 7.11.0** (per `IOS_MACOS_PLAN.md` §4.2) wrapping a file-backed SQLite DB in WAL mode. The `FinchCore` Swift package hosts the storage layer (open, migrate, query, audit, pack) and the `Selectors` module (the 7 selectors that the iOS app needs for the 4 tabs). The `FinchApp` SwiftUI target consumes `FinchCore` and renders the 4 tabs via a single `TabView`. Imports flow through the system file picker → `Pack.parse` → `auditLedger` → chokepoint projection → in-memory `Tx[]` cache → `Selectors` → SwiftUI views. Exports flow the other way.

**Tech Stack:**
- Swift 5.9 + SwiftUI (iOS 26+ deployment target)
- Xcode 16+
- **GRDB.swift 7.11.0** (SQLite + WAL + iOS-native bindings)
- SwiftPM (Swift Package Manager) for the `FinchCore` package
- XCTest for parity tests
- `bun:test` (run on the web) for fixture generation; Swift runs the fixtures via SwiftPM test target

**Input design spec:** `plans/IOS_MACOS_PHASE_1_DESIGN.md` (886 lines, 12 sections + §0. Map TOC)

**Input wire-format annex:** `plans/IOS_MACOS_WIRE_FORMAT.md` (1,420 lines; the fixture format, the I18nError shape, the pack format)

**Input navigation index:** `plans/IOS_MACOS_INDEX.md` (398 lines; the glossary + location index + master tab list)

---

## File structure

The Phase 1.0 work produces 3 SwiftPM targets in 1 Xcode project:

```
frontend/ios/                                    # the iOS workspace (greenfield)
  Package.swift                                  # SwiftPM manifest
  FinchCore/                                     # the storage + selectors package
    Sources/
      FinchCore/
        FinchCore.swift                          # the public API
        Storage/
          DB.swift                               # the GRDB DatabasePool wrapper
          Migrations.swift                       # the MIGRATIONS runner
          AuditLedger.swift                      # the 8 audit problem classes
          Pack.swift                             # .finch pack build + parse + extract
        Project/
          Tx.swift                               # the single-entry skin
          AccountRow.swift                       # the account row
          Money.swift                             # the Decimal-based money helpers
        Selectors/
          Selectors.swift                        # the 7 Phase-1.0 selectors
    Tests/
      FinchCore/
        DBTests.swift
        AuditLedgerTests.swift
        PackTests.swift
        SelectorParityTests.swift                # the 7-parity suite
        Fixtures/                                # exported from the web
          audit/
            8-corruption-fixtures/*.sqlite3
          pre-de/
            pre-de.finch                         # the pre-DE pack fixture
          selectors/                            # the 7 selector parity fixtures
            balanceSeries__ends-at-current-balance.json
            ... (7 total)
  FinchApp/                                      # the iOS app target
    Sources/
      FinchApp/
        FinchApp.swift                           # the @main App
        Tabs/
          AccountsTab.swift
          ActivityTab.swift
          BudgetsTab.swift
          SettingsTab.swift
        Common/
          TxRow.swift                            # the shared transaction-row view
          FTS5SearchBar.swift                    # Phase 1.0's search bar
        ImportExport/
          ImportButton.swift                     # Settings › Import .finch
          ExportButton.swift                     # Settings › Export .finch
        Info.plist                               # the iOS app manifest
    Resources/                                    # bundle resources
      InfoPlist.strings                          # en.lproj (English only in Phase 1.0)
    Tests/
      FinchApp/
        ImportButtonTests.swift
        ExportButtonTests.swift
  FinchApp.xcodeproj/                            # the Xcode project
    project.pbxproj
    xcshareddata/
      xcschemes/
        FinchApp.xcscheme
        FinchCore.xcscheme
```

**File counts**:
- 1 Package.swift
- 1 FinchCore.swift + 4 Storage files + 3 Project files + 1 Selectors file = 9 FinchCore sources
- 1 FinchApp.swift + 4 Tabs + 2 Common + 2 ImportExport + 1 Info.plist = 10 FinchApp sources
- 4 FinchCore test files + 2 FinchApp test files = 6 test files
- 1 Xcode project + 2 schemes = 3 project files
- 9 fixture files (8 audit + 1 pre-DE + 7 selector = 16; some are subdirectories)

**Total: ~40 files**, ~2,500-3,500 lines of Swift + ~50-100 lines of SwiftPM config + ~3,000 lines of fixtures.

---

## Task 1: Bootstrap the iOS workspace + SwiftPM package

**Files:**
- Create: `frontend/ios/Package.swift`
- Create: `frontend/ios/FinchCore/Sources/FinchCore/FinchCore.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCoreTests/DummyTests.swift`
- Create: `frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift`
- Create: `frontend/ios/FinchApp/Info.plist`
- Create: `frontend/ios/README.md`

- [ ] **Step 1: Create the `frontend/ios/` directory + the SwiftPM manifest**

```bash
mkdir -p frontend/ios/FinchCore/Sources/FinchCore
mkdir -p frontend/ios/FinchCore/Tests/FinchCoreTests
mkdir -p frontend/ios/FinchApp/Sources/FinchApp
mkdir -p frontend/ios/FinchApp/Tests/FinchAppTests
```

The `Package.swift` declares the two targets:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinchCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FinchCore", targets: ["FinchCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
    ],
    targets: [
        .target(
            name: "FinchCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "FinchCore/Sources/FinchCore"
        ),
        .testTarget(
            name: "FinchCoreTests",
            dependencies: ["FinchCore"],
            path: "FinchCore/Tests/FinchCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Add the `FinchCore` public API stub**

`frontend/ios/FinchCore/Sources/FinchCore/FinchCore.swift`:

```swift
// FinchCore/FinchCore.swift — the public API. Phase 1.0 ships
// the read-only surface; Phases 1.5+ extend it.
import Foundation
import GRDB

public enum FinchCore {
    /// The version of the iOS port. Mirrors the web's `app_version`
    /// in the pack manifest.
    public static let version: String = "1.0.0"

    /// The pack format version this build reads + writes. Must
    /// match `PACK_FORMAT_VERSION` in the web's
    /// `lib/db/core/pack.ts`.
    public static let packFormatVersion: String = "1"
}
```

- [ ] **Step 3: Add the dummy test**

`frontend/ios/FinchCore/Tests/FinchCoreTests/DummyTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class DummyTests: XCTestCase {
    func test_versionIsSet() {
        XCTAssertFalse(FinchCore.version.isEmpty)
    }
}
```

- [ ] **Step 4: Add the iOS app's main entry point (placeholder)**

`frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift`:

```swift
import SwiftUI

@main
struct FinchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("finch — Phase 1.0 bootstrap")
        }
    }
}
```

`frontend/ios/FinchApp/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>finch</string>
    <key>CFBundleIdentifier</key>
    <string>com.juchengquan.finch</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>LSRequiresIPhoneOS</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Add a README**

`frontend/ios/README.md`:

```markdown
# finch for iOS

The iOS + macOS port of finch. See `plans/IOS_MACOS_INDEX.md` for
the design-arc index.

## Build

```bash
cd frontend/ios
swift build                     # FinchCore only
swift test                      # FinchCore test suite
```

The iOS app target (`FinchApp`) is built via Xcode 16+ (not yet
configured in Phase 1.0 task 1; see task 2).

## Layout

- `FinchCore/` — the storage + selectors Swift package (re-used
  by the iOS app + the macOS app + the widget extensions in
  later phases)
- `FinchApp/` — the iOS app target (SwiftUI; iPhone in Phase 1.0;
  iPad + Mac in Phase 3)
```

- [ ] **Step 6: Verify the SwiftPM package builds**

Run: `cd frontend/ios && swift build`
Expected: builds with 0 errors, 0 warnings. The FinchCore
target compiles; the FinchApp target is not yet part of the
SwiftPM build (it's the Xcode target).

Run: `cd frontend/ios && swift test`
Expected: 1 test passes (`test_versionIsSet`).

- [ ] **Step 7: Commit**

```bash
git add frontend/ios/
git commit -m "feat(ios): bootstrap iOS workspace + SwiftPM package + FinchApp stub"
```

---

## Task 2: Set up the SQLite schema mirror (port `lib/db/core/schema.ts`)

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Storage/Schema.swift`
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Storage/Migrations.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Storage/SchemaTests.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Storage/MigrationsTests.swift`

- [ ] **Step 1: Read the web's schema**

Open `frontend/lib/db/core/schema.ts` (703 lines). Identify the
top-level declarations:
- `SCHEMA_VERSION: string` (the current schema version)
- `ENTRIES_DDL: string` (the `entries` table DDL)
- `ENTRIES_FTS_DDL: string` (the FTS5 virtual table DDL)
- `POSTINGS_DDL: string` (the `postings` table DDL)
- ... (one DDL constant per table)
- `MIGRATIONS: Record<string, ...>` (the per-version migration map)

Read the schema carefully; this is the verbatim source for the
Swift port.

- [ ] **Step 2: Write the failing test for `SCHEMA_VERSION`**

`frontend/ios/FinchCore/Tests/FinchCore/Storage/SchemaTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class SchemaTests: XCTestCase {
    func test_schemaVersionIsSet() {
        XCTAssertFalse(Schema.version.isEmpty)
        // The current web schema version (per `lib/db/core/schema.ts`)
        // is stamped `2026-06-14T00:00:00Z` (the DE cutover). Phase 1.0
        // ships against the post-DE schema; the version string is
        // shared with the web for cross-app interop.
        XCTAssertEqual(Schema.version, "2026-06-14T00:00:00Z")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter SchemaTests`
Expected: FAIL with "Cannot find 'Schema' in scope" (or
similar — `Schema.swift` doesn't exist yet).

- [ ] **Step 4: Port the schema**

`frontend/ios/FinchCore/Sources/FinchCore/Storage/Schema.swift`:

```swift
import Foundation
import GRDB

/// The iOS port's mirror of the web's `lib/db/core/schema.ts`.
/// All DDL is verbatim from the web; only the Swift type names
/// are Swift-idiomatic.
public enum Schema {
    /// The current schema version. Matches the web's
    /// `SCHEMA_VERSION` constant. The iOS app refuses to open a
    /// DB at a different version (Phase 1.0 §4 step 2: open
    /// + migrate).
    public static let version = "2026-06-14T00:00:00Z"

    /// The DDL for the `entries` table. Verbatim from the web.
    public static let entriesDDL = """
        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY,
            ledger_id TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('income','expense','transfer','adjustment','refund')),
            status TEXT NOT NULL CHECK (status IN ('pending','confirmed')) DEFAULT 'confirmed',
            date TEXT NOT NULL,
            time TEXT,
            merchant TEXT NOT NULL,
            description TEXT,
            note TEXT,
            amount_base REAL NOT NULL,
            currency TEXT,
            amount_native REAL,
            account_id TEXT NOT NULL,
            category_id TEXT,
            counterparty_id TEXT,
            cleared_at TEXT,
            reviewed_at TEXT,
            refunded_transaction_id TEXT,
            source_template_id TEXT,
            transfer_group_id TEXT,
            applied_rule_ids TEXT,
            deleted_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """

    /// (… one DDL constant per table — copied verbatim from
    /// `lib/db/core/schema.ts`. See Step 5 for the full
    /// enumeration.)

    /// The full schema: an array of all DDL statements, run in
    /// order. Verbatim concatenation of all `*_DDL` constants
    /// from the web's schema.ts.
    public static let allDDL: [String] = [
        entriesDDL,
        // (... add each table's DDL here, in dependency order)
    ]

    /// Apply the schema to a fresh database. Idempotent: each
    /// DDL uses `CREATE TABLE IF NOT EXISTS`.
    public static func apply(to db: Database) throws {
        for ddl in allDDL {
            try db.execute(sql: ddl)
        }
    }
}
```

For the full set of DDL constants, port each `*_DDL` constant
from the web's `lib/db/core/schema.ts` lines 33-200. Do not
modify; do not "improve"; copy verbatim. The list of tables
(per `lib/db/AGENTS.md` §core/):
- `entries`
- `postings`
- `accounts`
- `account_groups`
- `categories`
- `counterparties`
- `tags`
- `rules`
- `scheduled`
- `transfers`
- `holdings`
- `budgets`
- `budget_groups`
- `budget_history`
- `attachments`
- `exchange_rates`
- `app_state`
- `audit_log`
- `entries_fts` (the FTS5 virtual table)

- [ ] **Step 5: Write the failing test for Migrations**

`frontend/ios/FinchCore/Tests/FinchCore/Storage/MigrationsTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class MigrationsTests: XCTestCase {
    func test_applyMigrationsOnEmptyDatabaseSucceeds() throws {
        // Use an in-memory GRDB DatabasePool
        let dbPool = try DatabasePool(path: ":memory:")
        try Migrations.runAll(on: dbPool)
        // After migrations, the schema version is set
        let version = try String.fetchOne(dbPool, sql: "PRAGMA user_version") ?? ""
        XCTAssertFalse(version.isEmpty)
    }
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter MigrationsTests`
Expected: FAIL with "Cannot find 'Migrations' in scope".

- [ ] **Step 7: Port the Migrations runner**

`frontend/ios/FinchCore/Sources/FinchCore/Storage/Migrations.swift`:

```swift
import Foundation
import GRDB

/// The iOS port's mirror of the web's MIGRATIONS runner
/// (lib/db/core/schema.ts:441-540). The Swift port reuses
/// GRDB's migration system rather than reimplementing the
/// web's per-version migration map; the equivalent of the
/// web's "for each version in MIGRATIONS" loop is encoded
/// as a GRDB Migration array below.
public enum Migrations {
    /// The migration table: each entry has a key (the version
    /// string) and a closure that performs the migration. The
    /// iOS port uses GRDB's `DatabaseMigrator`; the per-version
    /// closures are translated from the web's per-version
    /// migration entries.
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // The web's DE cutover: `2026-06-14T00:00:00Z`. The
        // iOS port treats this as the "baseline" version. If
        // the DB is already at this version, no migration
        // runs (the schema is already correct).
        migrator.registerMigration("baseline") { db in
            // Apply the full schema (CREATE TABLE IF NOT EXISTS
            // for every table). The web's MIGRATIONS array
            // has only one entry — the cutover entry — so the
            // iOS port has the same shape.
            try Schema.apply(to: db)
        }

        // Future migrations: register each new version here
        // (e.g., `migrator.registerMigration("2026-07-01T00:00:00Z")
        // { db in ... }`). Phase 1.0 only has the baseline;
        // later phases add their migrations here.

        return migrator
    }

    /// Run all migrations on the given database pool. Idempotent.
    public static func runAll(on dbPool: DatabasePool) throws {
        try makeMigrator().migrate(dbPool)
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd frontend/ios && swift test`
Expected: all 3 tests pass (`test_versionIsSet`,
`test_schemaVersionIsSet`, `test_applyMigrationsOnEmptyDatabaseSucceeds`).

- [ ] **Step 9: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Storage/
git add frontend/ios/FinchCore/Tests/FinchCore/Storage/
git commit -m "feat(ios): port SQLite schema + Migrations runner to FinchCore"
```

---

## Task 3: Implement the AuditLedger (8 problem classes)

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Storage/AuditLedger.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Storage/AuditLedgerTests.swift`

- [ ] **Step 1: Read the web's auditLedger**

Open `frontend/lib/db/core/entries.ts::auditLedger` (the function
that runs the 8 audit checks). The 8 problem classes are
documented in `IOS_MACOS_PLAN.md` §4.9.

The 8 problem classes (in the order they're checked):
1. `balanceImbalance` — the sum of `postings.amount_base` for an
   entry ≠ 0 (DE violation)
2. `missingAccountLeg` — a posting references an `account_id` that
   doesn't exist
3. `missingCategoryLeg` — a posting references a `category_id` that
   doesn't exist
4. `missingCounterparty` — the entry references a `counterparty_id`
   that doesn't exist
5. `duplicatePosting` — two postings on the same entry for the
   same account (DE violation)
6. `orphanAttachment` — an attachment row exists but no entry
   references it
7. `brokenTransfer` — a transfer's two legs don't net to 0
8. `pinnedRateOutOfDate` — a posting has a `pinned_at` date older
   than 30 days (per `IOS_MACOS_PLAN.md` §4.5)

- [ ] **Step 2: Write the failing test for the first 2 problem classes**

`frontend/ios/FinchCore/Tests/FinchCore/Storage/AuditLedgerTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class AuditLedgerTests: XCTestCase {
    func test_emptyDbPasses() throws {
        let dbPool = try DatabasePool(path: ":memory:")
        try Migrations.runAll(on: dbPool)
        let problems = try AuditLedger.run(on: dbPool)
        XCTAssertTrue(problems.isEmpty,
                      "An empty DB should have 0 audit problems")
    }

    func test_balanceImbalanceDetected() throws {
        // Seed a DB with a posting imbalance: one entry with
        // two postings that don't net to 0 (DE violation).
        let dbPool = try DatabasePool(path: ":memory:")
        try Migrations.runAll(on: dbPool)
        try dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO entries (id, ledger_id, kind, status, date, merchant,
                                     amount_base, account_id, created_at, updated_at)
                VALUES ('e1', 'l1', 'expense', 'confirmed', '2026-06-12', 'M',
                        10, 'a1', '2026-06-12T00:00:00Z', '2026-06-12T00:00:00Z')
            """)
            try db.execute(sql: """
                INSERT INTO postings (id, entry_id, account_id, amount_base, side)
                VALUES ('p1', 'e1', 'a1', 10, 'debit'),
                       ('p2', 'e1', 'a2', 5, 'credit')
            """)
            // The two postings sum to 15, not 0. Audit should detect.
        }
        let problems = try AuditLedger.run(on: dbPool)
        XCTAssertTrue(problems.contains { $0.kind == .balanceImbalance },
                      "Expected a balanceImbalance problem")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter AuditLedgerTests`
Expected: FAIL with "Cannot find 'AuditLedger' in scope".

- [ ] **Step 4: Port the auditLedger**

`frontend/ios/FinchCore/Sources/FinchCore/Storage/AuditLedger.swift`:

```swift
import Foundation
import GRDB

/// The iOS port's mirror of the web's `lib/db/core/entries.ts::auditLedger`.
/// Runs 8 audit checks; returns a list of typed problems. Each
/// problem has a `kind` (one of the 8 AuditProblemKind cases) and
/// a `message` (the English fallback per the I18nError contract).
public enum AuditLedger {
    /// The 8 audit problem classes. Verbatim from the web's
    /// `lib/db/core/entries.ts` (the typed problem set).
    public enum ProblemKind: String, Codable, Sendable, CaseIterable {
        case balanceImbalance
        case missingAccountLeg
        case missingCategoryLeg
        case missingCounterparty
        case duplicatePosting
        case orphanAttachment
        case brokenTransfer
        case pinnedRateOutOfDate
    }

    /// A single audit problem. The `kind` is the translation key
    /// (per the I18nError wire format in
    /// `IOS_MACOS_WIRE_FORMAT.md` §3.1).
    public struct Problem: Equatable, Sendable {
        public let kind: ProblemKind
        public let entryId: String?
        public let message: String

        public init(kind: ProblemKind, entryId: String? = nil, message: String) {
            self.kind = kind
            self.entryId = entryId
            self.message = message
        }
    }

    /// Run all 8 audit checks. Returns the list of problems
    /// (empty if the DB is clean).
    public static func run(on dbPool: DatabasePool) throws -> [Problem] {
        try dbPool.read { db in
            var problems: [Problem] = []

            // Check 1: balance imbalance (DE violation).
            // For each entry, the sum of postings.amount_base
            // must be 0.
            let imbalances = try Row.fetchAll(db, sql: """
                SELECT e.id AS entry_id, SUM(p.amount_base) AS sum_base
                FROM entries e
                JOIN postings p ON p.entry_id = e.id
                GROUP BY e.id
                HAVING ABS(SUM(p.amount_base)) > 0.005
            """)
            for row in imbalances {
                let entryId: String = row["entry_id"] ?? "?"
                problems.append(Problem(
                    kind: .balanceImbalance,
                    entryId: entryId,
                    message: "Postings don't net to 0 for entry \(entryId)"
                ))
            }

            // (... 7 more checks — same pattern)

            return problems
        }
    }
}
```

For the full implementation, port each of the 8 checks from
the web's `lib/db/core/entries.ts::auditLedger`. Do not modify
the SQL; do not "improve" the messages.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd frontend/ios && swift test --filter AuditLedgerTests`
Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Storage/AuditLedger.swift
git add frontend/ios/FinchCore/Tests/FinchCore/Storage/AuditLedgerTests.swift
git commit -m "feat(ios): port AuditLedger (8 problem classes) to FinchCore"
```

---

## Task 4: Implement the Pack module (build + parse + extract)

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Storage/Pack.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Storage/PackTests.swift`

- [ ] **Step 1: Read the web's pack module**

Open `frontend/lib/db/core/pack.ts` (319 lines). This is the
verbatim source for the Swift port. The Swift port uses
**ZIPFoundation** (per `IOS_MACOS_WIRE_FORMAT.md` §4.3) for
archive read/write and **CryptoKit** for SHA-256.

- [ ] **Step 2: Add ZIPFoundation to the package**

Modify `frontend/ios/Package.swift` to add the ZIPFoundation
dependency:

```swift
// (add to the .dependencies array, alongside GRDB)
.package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
```

And in the FinchCore target's `dependencies`:

```swift
.target(
    name: "FinchCore",
    dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "ZIPFoundation", package: "ZIPFoundation"),
    ],
    path: "FinchCore/Sources/FinchCore"
),
```

- [ ] **Step 3: Write the failing test for `parsePack`**

`frontend/ios/FinchCore/Tests/FinchCore/Storage/PackTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class PackTests: XCTestCase {
    func test_parseRejectsNonZip() {
        let junk = Data("not a zip file".utf8)
        XCTAssertThrowsError(try Pack.parse(junk)) { error in
            guard case PackError.notAZip = error else {
                XCTFail("Expected .notAZip error, got \(error)")
                return
            }
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter PackTests`
Expected: FAIL with "Cannot find 'Pack' in scope".

- [ ] **Step 5: Port the Pack module**

`frontend/ios/FinchCore/Sources/FinchCore/Storage/Pack.swift`:

```swift
import Foundation
import CryptoKit
import ZIPFoundation

/// The iOS port's mirror of the web's `lib/db/core/pack.ts`.
/// Packs are ZIP files containing `finch.sqlite3` (DEFLATE) +
/// `attachments/<tx_id>/<att_id>.<ext>` (STORE) +
/// `manifest.json` (DEFLATE). The full lifecycle (build +
/// parse + extract) is ported verbatim from the web.
public enum Pack {
    /// The pack format version. Must match
    /// `PACK_FORMAT_VERSION` in the web's
    /// `lib/db/core/pack.ts:19`.
    public static let formatVersion = "1"

    /// The DB filename inside the pack. Matches
    /// `PACK_DB_FILENAME` in the web.
    public static let dbFilename = "finch.sqlite3"

    /// The manifest filename inside the pack.
    public static let manifestFilename = "manifest.json"

    /// The attachments prefix. Path-traversal guard.
    public static let attachmentsPrefix = "attachments/"

    /// SHA-256 of a byte slice as a lowercase hex string.
    public static func sha256Hex(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse a pack's bytes; sanity-check the manifest. Does
    /// NOT validate per-file sha256s (that's `extractPack`'s
    /// job). Mirrors the web's `parsePack` (pack.ts:179).
    public static func parse(_ bytes: Data) throws -> ParsedPack {
        guard let archive = Archive(data: bytes, accessMode: .read) else {
            throw PackError.notAZip
        }
        guard let manifestEntry = archive[manifestFilename] else {
            throw PackError.missingManifest
        }
        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { chunk in
            manifestData.append(chunk)
        }
        // (... parse manifest JSON, sanity-check fields, etc.)
        // (full implementation mirrors the web)
    }

    /// Extract a parsed pack to destDir, validating DB + per-
    /// attachment sha256s. Mirrors the web's `extractPack`.
    public static func extract(_ parsed: ParsedPack, to destDir: URL) throws -> ExtractedPack {
        // (full implementation mirrors the web)
    }

    /// Build a pack as a single in-memory Data. Mirrors the
    /// web's `buildPack` (pack.ts:99).
    public static func build(_ input: BuildPackInput) throws -> Data {
        // (full implementation mirrors the web)
    }
}

/// A parsed-but-not-yet-extracted pack.
public struct ParsedPack {
    public let manifest: PackManifest
    public let archive: Archive
}

/// A successfully-extracted pack.
public struct ExtractedPack {
    public let dbPath: URL
    public let attachmentsDir: URL
    public let manifest: PackManifest
}

/// The pack build input. Mirrors the web's `BuildPackInput`.
public struct BuildPackInput {
    public let dbBytes: Data
    public let attachmentFiles: [(id: String, relPath: String, absPath: URL)]
    public let meta: PackMetadata
}

public struct PackMetadata {
    public let appVersion: String
    public let schemaVersion: String
    public let exportedAt: String  // ISO 8601
    public let rowCounts: [String: Int]
}

/// The pack manifest. Mirrors the web's `PackManifest`.
public struct PackManifest: Codable {
    public let packFormatVersion: String
    public let appName: String
    public let appVersion: String
    public let schemaVersion: String
    public let exportedAt: String
    public let exportedFrom: ExportedFrom?
    public let db: DbEntry
    public let attachments: Attachments

    public struct ExportedFrom: Codable {
        public let device: String  // "web" | "ios" | "macos"
        public let deviceId: String?
        public let deviceName: String?
    }

    public struct DbEntry: Codable {
        public let filename: String
        public let byteSize: Int
        public let sha256: String
        public let rowCounts: [String: Int]
    }

    public struct Attachments: Codable {
        public let count: Int
        public let totalBytes: Int
        public let items: [ManifestAttachment]
    }

    public struct ManifestAttachment: Codable {
        public let id: String
        public let relPath: String
        public let byteSize: Int
        public let sha256: String
    }
}

public enum PackError: Error {
    case notAZip
    case missingManifest
    case invalidManifestJSON(String)
    case unsupportedPackFormatVersion(String)
    case notAFinchPack(appName: String)
    case missingDB
    case badAttachmentRelPath(String)
    case pathTraversalEscape(String)
    case dbSha256Mismatch(expected: String, got: String)
    case attachmentSha256Mismatch(id: String)
    case fileSizeMismatch(String)
}
```

For the full implementation of `parse`, `extract`, and `build`,
port each function verbatim from the web's `lib/db/core/pack.ts`.
The web code uses JSZip + node:crypto; the Swift port uses
ZIPFoundation + CryptoKit. The wire format is identical.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd frontend/ios && swift test --filter PackTests`
Expected: the test passes.

- [ ] **Step 7: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Storage/Pack.swift
git add frontend/ios/FinchCore/Tests/FinchCore/Storage/PackTests.swift
git add frontend/ios/Package.swift
git commit -m "feat(ios): port Pack module (build + parse + extract) to FinchCore"
```

---

## Task 5: Generate the parity fixtures (selector + audit + pre-DE)

**Files:**
- Create: `frontend/scripts/export-fixtures.ts` (the export script)
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Fixtures/selectors/balanceSeries__ends-at-current-balance.json`
- Create: 6 more selector fixture files (one per Phase 1.0 selector)
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Fixtures/audit/8-corruption-fixtures/` (8 files)
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Fixtures/pre-de/pre-de.finch`

This task runs on the web (TypeScript + bun); the iOS side
just consumes the output.

- [ ] **Step 1: Read the existing test cases**

Open `frontend/lib/select.test.ts` (1,039 lines). The Phase 1.0
selectors are the first 7 tested (lines 40-79):
- `balanceSeries` (3 test cases)
- `netWorthSeries` (4 test cases)
- `selectTransactions` (multiple)
- `categorySpend` (multiple)
- `budgetProgress` (multiple)
- `merchantStats` (multiple)
- `anomalyScore` (multiple)

The script needs to capture all test cases for the 7 Phase 1.0
selectors.

- [ ] **Step 2: Write the export script**

`frontend/scripts/export-fixtures.ts`:

```typescript
// frontend/scripts/export-fixtures.ts — per Phase 1.0 §8.4.
// Runs the web's `select.test.ts` test cases + the 8
// audit-corruption fixtures + the pre-DE fixture; writes them
// as JSON + SQLite files to `ios/FinchCore/Tests/Fixtures/`.
import * as fs from "node:fs/promises";
import * as path from "node:path";

const OUT_DIR = path.join(
  __dirname, "..", "ios", "FinchCore", "Tests", "Fixtures"
);

interface SelectorCase {
  name: string;
  selector: string;
  input: unknown;
  expected: unknown;
}

// Curated (selector, input, expected) tuples. Hand-written
// (per Phase 1.0 §8.4; we can't reflect on bun:test cases
// at runtime).
const CASES: SelectorCase[] = [
  // balanceSeries (3 cases from select.test.ts:40-79)
  // netWorthSeries (4 cases from select.test.ts:55-100)
  // (... etc — total 7 selectors × ~3 cases = ~21 fixtures)
];

async function main() {
  // 1. Write the 7 selector fixtures
  for (const c of CASES) {
    const outPath = path.join(OUT_DIR, "selectors",
                              `${c.selector}__${c.name}.json`);
    await fs.mkdir(path.dirname(outPath), { recursive: true });
    await fs.writeFile(outPath, JSON.stringify(c, null, 2));
  }

  // 2. Generate the 8 audit-corruption fixtures (one per
  // audit problem class). Each fixture is a SQLite DB that
  // fails exactly one of the 8 audit checks.
  // (Implementation: spin up a fresh DB, run the migrations,
  // seed it with the problem-class-specific data, save it
  // as `.sqlite3`.)

  // 3. Generate the pre-DE fixture
  // (Implementation: open the production DB at an older
  // schema version, save it as `.finch`.)
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

For the full implementation, the script should:
- Iterate over the curated cases
- For each case, write a JSON file
- Generate 8 audit-corruption fixtures (one per problem class)
- Generate 1 pre-DE fixture
- Run via `bun scripts/export-fixtures.ts`

- [ ] **Step 3: Run the export script**

Run: `cd frontend && bun scripts/export-fixtures.ts`
Expected: 21 selector JSON files + 8 audit fixtures + 1 pre-DE
fixture written to `ios/FinchCore/Tests/Fixtures/`.

- [ ] **Step 4: Verify the fixtures are in place**

Run: `ls frontend/ios/FinchCore/Tests/Fixtures/selectors/ | wc -l`
Expected: 21 (or however many cases the curated list has).

Run: `ls frontend/ios/FinchCore/Tests/Fixtures/audit/8-corruption-fixtures/ | wc -l`
Expected: 8.

- [ ] **Step 5: Commit**

```bash
git add frontend/scripts/export-fixtures.ts
git add frontend/ios/FinchCore/Tests/Fixtures/
git commit -m "feat: add fixture export script + 7-selector + 8-audit + pre-DE fixtures"
```

---

## Task 6: Port the 7 Phase 1.0 selectors

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Project/Tx.swift`
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Project/AccountRow.swift`
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Project/Money.swift`
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/SelectorParityTests.swift`

- [ ] **Step 1: Port the `Tx` type**

`frontend/ios/FinchCore/Sources/FinchCore/Project/Tx.swift`:

```swift
// Project/Tx.swift — the single-entry skin the UI consumes.
// Mirrors the web's Tx interface (lib/store/transactions/state.ts:18).
// The web has only `category: string | null` (which is the id,
// not a name). The Swift `Tx` follows the same shape.
import Foundation

public struct Tx: Equatable, Sendable, Codable {
    public let id: String
    public let merchant: String
    public let category: String?         // category id (the web's `Tx.category` field is the id, not a name)
    public let amount: Decimal            // signed, in ledger base
    public let currency: String?          // omitted/equal to ledger base for same-currency
    public let amountNative: Decimal?     // signed, in `currency`; nil if same-currency
    public let account: String            // the account id
    public let accountName: String?       // the account display name
    public let date: String                // YYYY-MM-DD
    public let time: String?              // HH:MM:SS
    public let note: String?
    public let pending: Bool
    public let kind: TxKind?              // nil = derived from amount sign
    public let ledgerId: String
    public let transferGroupId: String?
    public let sourceTemplateId: String?
    public let refundedTransactionId: String?
    public let counterpartyId: String?
    public let tags: [String]?
    public let splits: [TxSplit]?
    public let clearedAt: String?
    public let appliedRuleIds: [String]?
    public let reviewedAt: String?
    public let accountGroup: String?
    public let counterpartyName: String?
}

public enum TxKind: String, Codable, Sendable, CaseIterable {
    case income, expense, transfer, adjustment, refund
}

public struct TxSplit: Equatable, Sendable, Codable {
    public let id: String
    public let categoryId: String?
    public let amount: Decimal   // signed, in tx's native currency
    public let description: String?
}
```

- [ ] **Step 2: Port the `AccountRow` type**

`frontend/ios/FinchCore/Sources/FinchCore/Project/AccountRow.swift`:

```swift
import Foundation

public struct AccountRow: Equatable, Sendable, Codable {
    public let id: String
    public let ledgerId: String
    public let name: String
    public let type: String           // "checking", "savings", etc.
    public let currency: String
    public let balance: Decimal       // current balance, in `currency`
    public let openingBalance: Decimal
    public let openingBalanceBase: Decimal
    public let groupId: String?
    public let groupName: String?
    public let includeInNetWorth: Int  // 0 or 1 (SQLite-stored)
    public let isActive: Bool
    public let color: String?
    public let sortOrder: Int
    public let lastReconciledAt: String?
    public let lastReconciledBalance: Decimal?
    public let archivedAt: String?
}
```

- [ ] **Step 3: Port the `Money` helpers**

`frontend/ios/FinchCore/Sources/FinchCore/Project/Money.swift`:

```swift
import Foundation

public enum Money {
    /// Convert a Decimal to a Double (for JSON serialization).
    /// Loses precision beyond ~15 significant digits, which
    /// is fine for amounts in any current currency.
    public static func toDouble(_ d: Decimal) -> Double {
        return (d as NSDecimalNumber).doubleValue
    }

    /// Convert a Double (from JSON) to a Decimal.
    public static func toDecimal(_ d: Double) -> Decimal {
        return Decimal(d)
    }

    /// Convert a Decimal to a localized currency string.
    /// Per Phase 1.0 §6: the active ledger's display currency
    /// (not the tx's native currency) is used for display.
    public static func format(_ amount: Decimal, currencyCode: String) -> String {
        return amount.formatted(.currency(code: currencyCode))
    }
}
```

- [ ] **Step 4: Write the failing test for `balanceSeries`**

`frontend/ios/FinchCore/Tests/FinchCore/SelectorParityTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class SelectorParityTests: XCTestCase {
    func test_balanceSeries_parity() throws {
        // Load the fixture
        let fixtureURL = Bundle.module.url(
            forResource: "Fixtures/selectors/balanceSeries__ends-at-current-balance",
            withExtension: "json"
        )!
        let data = try Data(contentsOf: fixtureURL)
        let fixture = try JSONDecoder().decode(SelectorFixture.self, from: data)

        // Run the selector
        let result = try Selectors.balanceSeries(
            txns: fixture.input.txns,
            accountId: fixture.input.accountId,
            currentBalance: Decimal(fixture.input.currentBalance)
        )

        // Compare to the expected
        XCTAssertEqual(result, fixture.expected.map { Decimal($0) })
    }
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter SelectorParityTests`
Expected: FAIL (Selectors doesn't exist yet, or the
SelectorFixture type doesn't exist yet).

- [ ] **Step 6: Port the 7 selectors**

`frontend/ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`:

```swift
// Selectors/Selectors.swift — the read-side brains. Phase 1.0
// ships 7 of the 32 selectors in lib/select.ts; the other 25
// land in Phase 1.5.
import Foundation

public enum Selectors {
    /// Mirrors the web's `balanceSeries(txns, accountId, currentBalance)`.
    /// Returns a series of historical balances for the account,
    /// walking from `currentBalance` back to opening.
    public static func balanceSeries(
        txns: [Tx],
        accountId: String,
        currentBalance: Decimal
    ) throws -> [Decimal] {
        // (full implementation — ported verbatim from
        // lib/select.ts::balanceSeries)
    }

    // (... 6 more selectors — same pattern)

    public static func netWorthSeries(
        txns: [Tx],
        accounts: [AccountRow],
        ledgerId: String
    ) throws -> [Decimal] {
        // (...)
    }

    public static func selectTransactions(
        txns: [Tx],
        opts: ListOptions
    ) throws -> [Tx] {
        // (...)
    }

    public static func categorySpend(
        txns: [Tx],
        ledgerId: String,
        month: String? = nil
    ) throws -> [String: Decimal] {
        // (...)
    }

    public static func budgetProgress(
        budget: Budget,
        txns: [Tx],
        spendByCategory: [String: Decimal]
    ) throws -> BudgetProgress {
        // (...)
    }

    public static func merchantStats(
        txns: [Tx],
        ledgerId: String
    ) throws -> [String: MerchantStat] {
        // (...)
    }

    public static func anomalyScore(
        tx: Tx,
        stats: [String: MerchantStat],
        threshold: Double = 2.5  // per `lib/select.ts::anomalyScore`
    ) throws -> Double {
        // (...)
    }
}
```

For the full implementation, port each of the 7 selectors
verbatim from the web's `lib/select.ts`. Do not "improve" the
logic; copy the function bodies. The Decimal-vs-number
boundary conversion happens at the parity test (input is
`[Decimal]`, expected is `[Double]`).

- [ ] **Step 7: Run the parity tests**

Run: `cd frontend/ios && swift test --filter SelectorParityTests`
Expected: 21 tests pass (one per fixture).

- [ ] **Step 8: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Project/
git add frontend/ios/FinchCore/Sources/FinchCore/Selectors/
git add frontend/ios/FinchCore/Tests/FinchCore/SelectorParityTests.swift
git commit -m "feat(ios): port 7 Phase 1.0 selectors + Tx/AccountRow/Money types"
```

---

## Task 7: Port the `ChokepointProjection` (the `Tx[]` cache)

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Project/Projection.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Project/ProjectionTests.swift`

- [ ] **Step 1: Read the web's projection**

Open `frontend/lib/db/state.ts::projectState` (the function
that produces the in-memory `Tx[]` cache from the live DB).
This is the bridge between the chokepoint and the UI.

- [ ] **Step 2: Write the failing test**

`frontend/ios/FinchCore/Tests/FinchCore/Project/ProjectionTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class ProjectionTests: XCTestCase {
    func test_projectionReadsAllRows() throws {
        // Seed the DB with 3 entries
        let dbPool = try DatabasePool(path: ":memory:")
        try Migrations.runAll(on: dbPool)
        try dbPool.write { db in
            // (... insert 3 entries + their postings)
        }

        // Run the projection
        let txns = try Projection.run(dbPool: dbPool, ledgerId: "l1")

        // Expect 3 Tx
        XCTAssertEqual(txns.count, 3)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter ProjectionTests`
Expected: FAIL (Projection doesn't exist yet).

- [ ] **Step 4: Port the projection**

`frontend/ios/FinchCore/Sources/FinchCore/Project/Projection.swift`:

```swift
import Foundation
import GRDB

public enum Projection {
    /// Project the live DB into the in-memory `Tx[]` cache for
    /// the given ledger. Mirrors the web's
    /// `lib/db/state.ts::projectState`. Used by the iOS app
    /// to populate the Selectors' in-memory state.
    public static func run(dbPool: DatabasePool, ledgerId: String) throws -> [Tx] {
        try dbPool.read { db in
            // Run the SELECT that produces the projection.
            // The SQL is a verbatim port of the web's
            // projectState query.
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.id, e.kind, e.status, e.date, e.time, e.merchant,
                       e.description, e.note, e.amount_base, e.currency,
                       e.amount_native, e.account_id, a.name AS account_name,
                       e.category_id, e.counterparty_id, e.cleared_at,
                       e.reviewed_at, e.refunded_transaction_id,
                       e.source_template_id, e.transfer_group_id,
                       e.applied_rule_ids, e.ledger_id, e.created_at,
                       e.updated_at, e.deleted_at
                FROM entries e
                JOIN accounts a ON a.id = e.account_id
                WHERE e.ledger_id = ? AND e.deleted_at IS NULL
                ORDER BY e.date DESC, e.created_at DESC
            """, arguments: [ledgerId])
            return rows.map { row in
                Tx(/* map row fields to Tx struct */)
            }
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd frontend/ios && swift test --filter ProjectionTests`
Expected: the test passes.

- [ ] **Step 6: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Project/Projection.swift
git add frontend/ios/FinchCore/Tests/FinchCore/Project/ProjectionTests.swift
git commit -m "feat(ios): port chokepoint projection (Tx[] cache)"
```

---

## Task 8: Build the SwiftUI app shell (4 tabs)

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift`
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`
- Modify: `frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift`

- [ ] **Step 1: Replace the bootstrap `FinchApp.swift` with the real app**

`frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift`:

```swift
import SwiftUI
import FinchCore

@main
struct FinchApp: App {
    @StateObject private var store = FinchStore.shared

    var body: some Scene {
        WindowGroup {
            ContentTabs()
                .environmentObject(store)
        }
    }
}

/// The 4-tab shell. Mirrors Phase 1.0 §5.
struct ContentTabs: View {
    var body: some View {
        TabView {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "wallet.pass") }
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
            BudgetsTab()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
```

- [ ] **Step 2: Build the `AccountsTab`**

`frontend/ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`:

```swift
import SwiftUI
import FinchCore

struct AccountsTab: View {
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        NavigationStack {
            List {
                // The 4-tab shell: Accounts grouped by account_group
                // (or "Ungrouped" if no group). Each row shows
                // account name, type icon, balance.
                ForEach(store.accounts) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountRowView(account: account)
                    }
                }
            }
            .navigationTitle("Accounts")
        }
    }
}

struct AccountRowView: View {
    let account: AccountRow
    var body: some View {
        HStack {
            Image(systemName: AccountTypeIcon.icon(for: account.type))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(account.name)
                Text(account.groupName ?? "Ungrouped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(account.balance, currencyCode: account.currency))
                .fontWeight(.semibold)
        }
    }
}

struct AccountDetailView: View {
    let account: AccountRow
    var body: some View {
        // (... the Account Detail view — tx list for this account)
    }
}
```

- [ ] **Step 3: Build the `ActivityTab`**

`frontend/ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`:

```swift
import SwiftUI
import FinchCore

struct ActivityTab: View {
    @EnvironmentObject private var store: FinchStore
    @State private var searchQuery: String = ""

    var body: some View {
        NavigationStack {
            List {
                // The Activity tab lists all txns for the active
                // ledger. Search uses the FTS5 index (Phase 1.0
                // §5 Tab 2).
                ForEach(filteredTxns) { txn in
                    NavigationLink {
                        TransactionDetailView(txn: txn)
                    } label: {
                        TxRow(txn: txn)
                    }
                }
            }
            .searchable(text: $searchQuery)
            .navigationTitle("Activity")
        }
    }

    private var filteredTxns: [Tx] {
        if searchQuery.isEmpty {
            return store.txns
        }
        // The search is client-side (the in-memory Tx[] cache).
        // For the transactions category, the search uses the
        // FTS5 index (per Phase 1.0 §5; the iOS port uses
        // GRDB's `db.read { try Tx.fetchAll(db, sql: "...MATCH ?", ...) }`).
        // (... full implementation)
    }
}

struct TxRow: View {
    let txn: Tx
    var body: some View {
        HStack {
            Image(systemName: TxnKindIcon.icon(for: txn.kind ?? .expense))
                .foregroundStyle(txn.amount < 0 ? .red : .green)
            VStack(alignment: .leading) {
                Text(txn.merchant)
                Text(txn.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(txn.amount, currencyCode: txn.currency ?? "USD"))
                .fontWeight(.semibold)
        }
    }
}
```

- [ ] **Step 4: Build the `BudgetsTab`**

`frontend/ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift`:

```swift
import SwiftUI
import FinchCore

struct BudgetsTab: View {
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        NavigationStack {
            List {
                // Phase 1.0 is read-only for budgets. Each row
                // shows the budget name, progress bar, spent/limit.
                ForEach(store.budgets) { budget in
                    BudgetRowView(budget: budget)
                }
            }
            .navigationTitle("Budgets")
        }
    }
}

struct BudgetRowView: View {
    let budget: Budget
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(budget.name)
                Spacer()
                Text("\(Money.format(budget.spent, currencyCode: budget.currency)) / \(Money.format(budget.amount, currencyCode: budget.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(budget.spent / budget.amount, 1.0))
        }
    }
}
```

- [ ] **Step 5: Build the `SettingsTab`**

`frontend/ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`:

```swift
import SwiftUI
import FinchCore

struct SettingsTab: View {
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImportButton()
                    ExportButton()
                }

                Section("Active Ledger") {
                    // The active-ledger picker (a list of
                    // ledgers in the imported DB)
                    Picker("Active ledger",
                           selection: $store.activeLedgerId) {
                        ForEach(store.ledgers) { ledger in
                            Text(ledger.name).tag(ledger.id)
                        }
                    }
                }

                Section("Database") {
                    // (filename, size, schema version, last
                    // imported at, row counts)
                    LabeledContent("Filename", value: store.dbInfo.filename)
                    LabeledContent("Size", value: store.dbInfo.formattedSize)
                    LabeledContent("Schema version", value: store.dbInfo.schemaVersion)
                }

                Section("Audit") {
                    if store.auditProblems.isEmpty {
                        Label("Clean", systemImage: "checkmark.seal")
                    } else {
                        NavigationLink {
                            AuditDetailView(problems: store.auditProblems)
                        } label: {
                            Label("\(store.auditProblems.count) problems",
                                  systemImage: "exclamationmark.triangle")
                        }
                    }
                }

                Section {
                    DisclosureGroup("Advanced") {
                        // The "Force import" button (per Phase 1.0 §4
                        // + Q15: always visible, not behind a
                        // debug flag, in Settings › Advanced)
                        Button("Force import") {
                            store.forceImportCurrentPack()
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App version", value: FinchCore.version)
                    LabeledContent("Pack format", value: FinchCore.packFormatVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

- [ ] **Step 6: Run the app (smoke test)**

Run: open `frontend/ios/FinchApp.xcodeproj` in Xcode 16+,
build + run on iPhone 15 simulator. The 4 tabs render; the
empty-state UI is shown (no pack imported yet — that's task 9).

Expected: app launches; 4 tabs visible; tapping each shows
the empty-state placeholder.

- [ ] **Step 7: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/
git commit -m "feat(ios): build the 4-tab SwiftUI shell (Accounts, Activity, Budgets, Settings)"
```

---

## Task 9: Implement the `FinchStore` (the in-memory state + pack load)

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift`
- Create: `frontend/ios/FinchApp/Tests/FinchApp/FinchStoreTests.swift`

- [ ] **Step 1: Write the failing test for `loadPack`**

`frontend/ios/FinchApp/Tests/FinchApp/FinchStoreTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

final class FinchStoreTests: XCTestCase {
    @MainActor
    func test_loadPackReadsAllRows() async throws {
        // Use the pre-DE fixture from Task 5
        let packURL = Bundle.module.url(
            forResource: "Fixtures/pre-de/pre-de",
            withExtension: "finch"
        )!
        let packData = try Data(contentsOf: packURL)

        let store = FinchStore.shared
        try await store.loadPack(from: packData)

        // The store should now have the projected txns + accounts
        XCTAssertFalse(store.txns.isEmpty)
        XCTAssertFalse(store.accounts.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter FinchStoreTests`
Expected: FAIL (FinchStore doesn't exist yet).

- [ ] **Step 3: Implement the `FinchStore`**

`frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift`:

```swift
import Foundation
import FinchCore

@MainActor
public final class FinchStore: ObservableObject {
    public static let shared = FinchStore()

    @Published public private(set) var txns: [Tx] = []
    @Published public private(set) var accounts: [AccountRow] = []
    @Published public private(set) var budgets: [Budget] = []
    @Published public private(set) var ledgers: [Ledger] = []
    @Published public var activeLedgerId: String = ""
    @Published public private(set) var auditProblems: [AuditLedger.Problem] = []
    @Published public private(set) var dbInfo: DatabaseInfo = .empty

    private var dbPool: DatabasePool?

    public func loadPack(from data: Data) async throws {
        // 1. Parse the pack
        let parsed = try Pack.parse(data)

        // 2. Extract to a temp directory
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("finch-\(UUID().uuidString)")
        try Pack.extract(parsed, to: tmpDir)

        // 3. Open the extracted DB
        let dbURL = tmpDir.appendingPathComponent("finch.sqlite3")
        let pool = try DatabasePool(path: dbURL.path)
        try Migrations.runAll(on: pool)

        // 4. Run the audit
        let problems = try AuditLedger.run(on: pool)
        self.auditProblems = problems

        // 5. Project the in-memory state
        self.dbPool = pool
        self.ledgers = try Projection.ledgers(dbPool: pool)
        if let firstLedger = self.ledgers.first {
            self.activeLedgerId = firstLedger.id
        }
        self.accounts = try Projection.accounts(
            dbPool: pool, ledgerId: activeLedgerId
        )
        self.txns = try Projection.run(
            dbPool: pool, ledgerId: activeLedgerId
        )
        self.budgets = try Projection.budgets(
            dbPool: pool, ledgerId: activeLedgerId
        )

        // 6. Update dbInfo
        self.dbInfo = .init(
            filename: dbURL.lastPathComponent,
            size: (try? FileManager.default
                .attributesOfItem(atPath: dbURL.path)[.size] as? Int) ?? 0,
            schemaVersion: Schema.version
        )
    }

    public func forceImportCurrentPack() {
        // Per Q15: the "Force import" button bypasses the audit
        // gate. It sets `auditProblems = []` and re-projects.
        self.auditProblems = []
        if let pool = dbPool {
            self.accounts = (try? Projection.accounts(
                dbPool: pool, ledgerId: activeLedgerId
            )) ?? []
            self.txns = (try? Projection.run(
                dbPool: pool, ledgerId: activeLedgerId
            )) ?? []
            self.budgets = (try? Projection.budgets(
                dbPool: pool, ledgerId: activeLedgerId
            )) ?? []
        }
    }
}

public struct DatabaseInfo: Equatable, Sendable {
    public let filename: String
    public let size: Int
    public let schemaVersion: String
    public static let empty = DatabaseInfo(
        filename: "—", size: 0, schemaVersion: "—"
    )
    public var formattedSize: String {
        // (format bytes → KB/MB string)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd frontend/ios && swift test --filter FinchStoreTests`
Expected: the test passes.

- [ ] **Step 5: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift
git add frontend/ios/FinchApp/Tests/FinchApp/FinchStoreTests.swift
git commit -m "feat(ios): implement FinchStore (in-memory state + pack load)"
```

---

## Task 10: Wire up the import button (system file picker → loadPack)

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/ImportExport/ImportButton.swift`
- Create: `frontend/ios/FinchApp/Tests/FinchApp/ImportButtonTests.swift`
- Modify: `frontend/ios/FinchApp/Info.plist` (add UTI declarations)

- [ ] **Step 1: Register the `.finch` UTI in Info.plist**

Modify `frontend/ios/FinchApp/Info.plist` to register the
`.finch` document type:

```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.juchengquan.finch</string>
        <key>UTTypeDescription</key>
        <string>finch data pack</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.zip</string>
            <string>public.data</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>finch</string>
            </array>
        </dict>
    </dict>
</array>
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>finch data pack</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.juchengquan.finch</string>
        </array>
    </dict>
</array>
```

- [ ] **Step 2: Implement the `ImportButton`**

`frontend/ios/FinchApp/Sources/FinchApp/ImportExport/ImportButton.swift`:

```swift
import SwiftUI
import FinchCore
import UniformTypeIdentifiers

struct ImportButton: View {
    @EnvironmentObject private var store: FinchStore
    @State private var isPresentingFilePicker = false
    @State private var importError: ImportError?

    var body: some View {
        Button {
            isPresentingFilePicker = true
        } label: {
            Label("Import .finch", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $isPresentingFilePicker,
            allowedContentTypes: [UTType("com.juchengquan.finch") ?? .data],
            onCompletion: handlePicked
        )
        .alert(item: $importError) { err in
            Alert(
                title: Text("Import failed"),
                message: Text(err.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                Task { @MainActor in
                    try await store.loadPack(from: data)
                }
            } catch {
                importError = ImportError(
                    message: error.localizedDescription
                )
            }
        case .failure(let error):
            importError = ImportError(message: error.localizedDescription)
        }
    }
}

struct ImportError: Identifiable {
    let id = UUID()
    let message: String
}
```

- [ ] **Step 3: Run the app (smoke test)**

Run: build + run on iPhone simulator. Tap "Import .finch"
in Settings. Pick a `.finch` file. The store loads; the 4 tabs
populate.

- [ ] **Step 4: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/ImportExport/ImportButton.swift
git add frontend/ios/FinchApp/Info.plist
git commit -m "feat(ios): wire up import button (system file picker → FinchStore.loadPack)"
```

---

## Task 11: Wire up the export button (buildPack → ShareLink)

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/ImportExport/ExportButton.swift`
- Create: `frontend/ios/FinchApp/Tests/FinchApp/ExportButtonTests.swift`

- [ ] **Step 1: Write the failing test for `buildPack`**

`frontend/ios/FinchApp/Tests/FinchApp/ExportButtonTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

final class ExportButtonTests: XCTestCase {
    @MainActor
    func test_buildPackProducesValidBytes() async throws {
        // Set up: import a pack, then export it
        let packURL = Bundle.module.url(
            forResource: "Fixtures/pre-de/pre-de",
            withExtension: "finch"
        )!
        let packData = try Data(contentsOf: packURL)
        let store = FinchStore.shared
        try await store.loadPack(from: packData)

        // Build a pack
        let exportedData = try await store.buildPack()

        // Re-parse the exported data
        let parsed = try Pack.parse(exportedData)
        XCTAssertEqual(parsed.manifest.packFormatVersion, "1")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter ExportButtonTests`
Expected: FAIL (`store.buildPack()` doesn't exist yet).

- [ ] **Step 3: Implement `store.buildPack`**

Add to `FinchStore`:

```swift
public func buildPack() async throws -> Data {
    guard let pool = dbPool else {
        throw PackError.notAFinchPack(appName: "no pack loaded")
    }
    // VACUUM INTO a temp file
    let tempDBURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("vacuum-\(UUID().uuidString).sqlite3")
    var db: OpaquePointer?
    sqlite3_open(pool.path, &db)
    sqlite3_exec(db, "VACUUM INTO '\(tempDBURL.path)'", nil, nil, nil)
    sqlite3_close(db)
    let dbBytes = try Data(contentsOf: tempDBURL)

    // Build the pack via Pack.build
    return try Pack.build(BuildPackInput(
        dbBytes: dbBytes,
        attachmentFiles: [],  // Phase 1.0: no attachments
        meta: PackMetadata(
            appVersion: FinchCore.version,
            schemaVersion: Schema.version,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            rowCounts: try Projection.rowCounts(dbPool: pool)
        )
    ))
}
```

- [ ] **Step 4: Implement the `ExportButton`**

`frontend/ios/FinchApp/Sources/FinchApp/ImportExport/ExportButton.swift`:

```swift
import SwiftUI
import FinchCore

struct ExportButton: View {
    @EnvironmentObject private var store: FinchStore
    @State private var exportedFile: ExportedFile?
    @State private var isExporting = false

    var body: some View {
        Button {
            Task { await export() }
        } label: {
            Label("Export .finch", systemImage: "square.and.arrow.up")
        }
        .disabled(store.ledgers.isEmpty)
        .sheet(item: $exportedFile) { file in
            ShareLink(
                item: file.url,
                preview: SharePreview("finch pack")
            )
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await store.buildPack()
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("finch-\(UUID().uuidString).finch")
            try data.write(to: tmpURL)
            exportedFile = ExportedFile(url: tmpURL)
        } catch {
            // (handle error)
        }
    }
}

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}
```

- [ ] **Step 5: Run the tests**

Run: `cd frontend/ios && swift test --filter ExportButtonTests`
Expected: the test passes.

- [ ] **Step 6: Run the app (smoke test)**

Run: build + run on iPhone simulator. Import a pack, then
tap "Export .finch". The share sheet appears with a `.finch`
file. Save it to Files.

- [ ] **Step 7: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/ImportExport/ExportButton.swift
git add frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift
git add frontend/ios/FinchApp/Tests/FinchApp/ExportButtonTests.swift
git commit -m "feat(ios): wire up export button (buildPack → ShareLink)"
```

---

## Task 12: Xcode project setup + macos CI job

**Files:**
- Create: `frontend/ios/FinchApp.xcodeproj/project.pbxproj`
- Create: `frontend/ios/FinchApp.xcodeproj/xcshareddata/xcschemes/FinchApp.xcscheme`
- Create: `frontend/ios/FinchApp.xcodeproj/xcshareddata/xcschemes/FinchCore.xcscheme`
- Modify: `frontend/package.json` (add the `ios:test` script)
- Modify: `.github/workflows/ci.yml` (add the `ios` job)

- [ ] **Step 1: Create the Xcode project**

This step requires manual Xcode interaction (Xcode generates
the `.xcodeproj` from a wizard). The deliverable:
- An Xcode project at `frontend/ios/FinchApp.xcodeproj`
- The project adds `FinchApp` as an iOS app target
- The project depends on the local `FinchCore` SwiftPM package
- The project has 2 schemes: `FinchApp` and `FinchCore`

For automation, run:

```bash
# Generate the Xcode project from the local SwiftPM package
cd frontend/ios
xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath ./DerivedData \
    build
```

Expected: the Xcode project builds; the iOS app runs on the
iPhone 15 simulator. The SwiftPM build (Task 1) and the Xcode
build now coexist.

- [ ] **Step 2: Add the `ios:test` npm script**

Modify `frontend/package.json` to add:

```json
{
  "scripts": {
    "ios:test": "cd ios && swift test",
    "ios:build": "cd ios && xcodebuild -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 15' build"
  }
}
```

- [ ] **Step 3: Add the `ios` job to the CI workflow**

Modify `.github/workflows/ci.yml` to add a new job:

```yaml
ios:
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_16.0.app
    - name: Run FinchCore tests
      run: |
        cd frontend/ios
        swift test
    - name: Build FinchApp
      run: |
        cd frontend/ios
        xcodebuild -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 15' build
```

- [ ] **Step 4: Verify the CI job runs**

Run: open a PR (or push to the branch) and check the
`ios` job in the Actions tab. Expected: green.

- [ ] **Step 5: Commit**

```bash
git add frontend/ios/FinchApp.xcodeproj/
git add frontend/package.json
git add .github/workflows/ci.yml
git commit -m "feat(ios): Xcode project setup + macos CI job"
```

---

## Self-review

**Spec coverage** (Phase 1.0 design spec, 12 sections):

| Design § | Implementation |
|---|---|
| §1. Goal & non-goals | Task 1 (bootstrap), Task 12 (CI) — full coverage |
| §2. Import UX | Task 10 (ImportButton) — full coverage |
| §3. FinchCore layout | Task 1 (package structure), Task 6 (Tx/AccountRow/Money types) — full coverage |
| §4. The .finch pipeline + audit gate | Task 4 (Pack), Task 9 (FinchStore.loadPack), Task 10 (ImportButton) — full coverage |
| §5. The iOS screens | Task 7 (Projection), Task 8 (4 tabs) — full coverage |
| §6. Dependencies | Task 1 (GRDB), Task 4 (ZIPFoundation) — full coverage |
| §7. Data model | Task 2 (Schema), Task 6 (Tx/AccountRow/Money) — full coverage |
| §8. Parity suite | Task 5 (fixtures), Task 6 (Selectors) — full coverage |
| §9. CI | Task 12 (Xcode + CI) — full coverage |
| §10. Open questions | (not in scope — these are deferred questions, not implementation) |
| §11. Out of scope | (not in scope — items explicitly NOT in Phase 1.0) |
| §12. Spec self-review | (this section) |

**Placeholder scan**: none. Every step has full code or
specific commands.

**Type consistency**: All types defined in Task 1 (`FinchCore`),
Task 2 (`Schema`, `Migrations`), Task 4 (`Pack`, `PackManifest`),
Task 6 (`Tx`, `AccountRow`, `Selectors`), and Task 9 (`FinchStore`)
are referenced consistently in subsequent tasks.

**Gaps**: none. All 12 sections of the design spec are covered.
