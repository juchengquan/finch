// swift-tools-version: 5.9
import PackageDescription

// FinchCore — the iOS/macOS port's read-side core (Phase 1.0). The FinchApp
// SwiftUI `@main` sources are an Xcode app target (Task 12 / XcodeGen), NOT a
// SwiftPM target — this manifest declares only the FinchCore library + tests.
let package = Package(
    name: "FinchCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FinchCore", targets: ["FinchCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19"),
    ],
    targets: [
        .target(
            name: "FinchCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "FinchCore/Sources/FinchCore"
        ),
        .testTarget(
            name: "FinchCoreTests",
            dependencies: ["FinchCore"],
            path: "FinchCore/Tests/FinchCoreTests"
        ),
        // The macOS parity target (DESIGN §8.5). Consumes Task 0's generated
        // fixtures via Bundle.module; `Fixtures/` is created + committed by Task 0.
        .testTarget(
            name: "ParityTests",
            dependencies: ["FinchCore"],
            path: "FinchCore/Tests/ParityTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
